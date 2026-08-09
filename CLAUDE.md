# LiftIQ

iOS lifting app: SwiftUI (iOS 17+) + Firebase + Claude via Cloud Functions + YouTube exercise embeds.

## Commands

```bash
# iOS
cd LiftIQ && xcodegen generate
cd LiftIQ && xcodebuild -project LiftIQ.xcodeproj -scheme LiftIQ -destination "generic/platform=iOS Simulator" build
cd LiftIQ && xcodebuild test -project LiftIQ.xcodeproj -scheme LiftIQ -destination "platform=iOS Simulator,name=iPhone 17,OS=latest"

# Cloud Functions
cd firebase/functions && npm install
cd firebase/functions && npm run build
cd firebase/functions && npx vitest run --exclude "**/firestore.rules.test.ts"   # fast path, no emulator

# Firestore rules tests require Java + emulator (CI runs them; this machine has no Java)
cd firebase && firebase emulators:exec --only firestore "cd functions && npm test"
```

## Architecture

App code lives under `LiftIQ/LiftIQ/`; backend code lives under `firebase/functions/src/`.

`docs/architecture-remediation-plan.md` records the 2026-07 architecture review and the fixes made for it.

## Patterns

- `@Observable` + `@MainActor` on every ViewModel and stateful Service; repositories stay nonisolated. No `ObservableObject` or `@Published`.
- Inject `AppDependencies` with `.environment(dependencies)`. It exposes concrete service types (SwiftUI observation needs them); ViewModels take `any WorkoutServicing` / `ProgressServicing` / `ExerciseServicing` so tests can substitute the fakes in `LiftIQTests/ServiceFakes.swift`.
- `WorkoutExecutionViewModel` takes services + userId at init. Set inputs are a `[SetLog.id: SetInput]` dictionary — never index the inputs. Rest timer and its local notification live in `RestTimerController`; both timers derive from wall-clock dates so backgrounding can't drift them.
- Keep Views UI-only. Validation/orchestration in ViewModels, business logic in Services, Firestore details in Repositories.
- Store all weights in kg. Convert only at display/input boundaries via `UnitConversionService`. New users default to imperial.
- Epley e1RM has one client implementation (`Utilities/Epley.swift`; reps <= 1 returns the weight). The server copy in `computeProgressRecords.ts` must stay identical — parity tests exist on both sides.
- Client AI calls go only through `AIService` and Firebase Functions; API keys never ship in the app. Personal-data AI features require `AIConsentManager`/`AIConsentSheet`; bump consent version when shared data changes.
- All AI functions use forced tool use + Zod validation (SDK 0.39 has no structured outputs). The server stamps plan id/userId/createdAt (`normalizePlan`) — never trust model-generated IDs. Keep prompt/schema/client models in sync.
- `modifyWorkout` (scope `plan` = permanent edit, scope `workout` = one-session edit) reuses `generateWorkoutPlan`'s exported tool schema/equipment filter and preserves original identity fields (`normalizeModifiedPlan` keeps plan id/createdAt/isActive, reclaims model-minted ids for existing days by dayNumber, and forces `workoutsPerWeek` = returned day count; `normalizeModifiedWorkout` keeps day id/planId/dayNumber). The prompt (v1.1.0) treats explicit removals as deletions — no substitute exercise unless asked or health-required. Client entry: `AIModifySheet` from plan/day detail toolbars, and mid-workout from the execution screen's "Modify with AI" button with both scopes: workout scope merges via `WorkoutExecutionViewModel.applyModifiedWorkout`; plan scope saves the plan then `applyModifiedPlan` merges this session's day (matched by `workoutTemplateId`; day removed from plan = session untouched). Completed sets, their PRs, and removed-but-completed exercises always survive the merge.
- Every AI function writes an aiUsageLogs entry and checks `assertWithinDailyQuota` before calling Anthropic.
- `analyzePlateau` is deployed server-side but has **no Swift caller** — a dead endpoint kept for possible future use. Don't wire it into per-session detection: per-observation e1RM noise (~10%) vs trained gain rates (1-3%/yr) makes short-window plateau claims statistically meaningless (see `ProgressionService`/`StrengthTrend` notes below and `docs/e1rm-formula-migration-plan.md`).
- `progressRecords` are written only by `computeProgressRecords` (Admin SDK); rules deny client writes. Clients write `personalRecords` (rules-validated), sessions, and plans. Plan activation is a single `WriteBatch`.
- Workout completion triggers `computeProgressRecords` (recomputes on any completed write, deletes records with the session); deterministic progression stays on-device in `ProgressionService`.

## Current UX

- Onboarding: profile, equipment presets, optional AI consent, then a generated active plan. Declining consent ends in "Finish Setup" with pointers to templates; page swipe cannot skip validation. First arrival at MainTabView shows `GettingStartedView`, a one-time in-app tutorial (device-local `liftiq_seen_getting_started` key; replayable from Profile → Help).
- Workout execution: progression/warm-up suggestions live in `WorkoutExecutionViewModel.suggestedSetInputs`, a ghost layer rendered behind empty fields (display units; converted on unit change) — they are never written into `setInputs`, so the user never deletes pre-filled text. Tapping ✓ on empty fields adopts ghosts in priority order suggestion → previous-session set → plan `repsMin` (weighted sets still require a weight); cards with no history show a "First time — aim for sets×reps" guidance box with weight-picking advice (`targetReps`/`firstTimeGuidance`); long-pressing a card opens a context menu with Swap and confirmed Remove Exercise (`removeExercise` rolls back PRs, trims the template group — a surviving one-exercise superset degrades to straight sets — and refuses to empty the session); swapping renames the plan slot's exerciseId so the new exercise inherits the slot's rest/rep prescription; rest timer keeps time in the background and fires a local notification; the timer card minimizes to a compact pill (sticky for the session); PRs appear as a non-blocking top toast; keyboard has a prev/next/Done toolbar; controls have 44pt targets and VoiceOver labels.
- Progression (`ProgressionService`): double progression anchored to the last session's **top** working set (sets at that weight all ≥ repsMax → +equipment increment), floored at the best recent top-set weight that met the rep floor so a deload week can't drag suggestions down. "Plateau detected" is gone: `isStalled` fires only after `Constants.stallThreshold` (3) consecutive rep-floor misses **at the same top weight** (rebuilding reps after an increment is not a stall) and suggests a ~10% back-off probe, keeping last-session context in the pill. Long-term trend claims live in `Utilities/StrengthTrend.swift` (log-space OLS with fixed σ=0.09/observation ≈ real e1RM noise; verdicts insufficientData/unclear/progressing/declining at ~90% one-sided confidence) — shown as a caption on the Progress tab e1RM chart over a 26-week window. Per-session e1RM noise (~10%) vs trained gain rates (1-3%/yr) means "unclear" is the expected verdict; don't add shorter-window plateau detectors.
- Warm-up sets: `WarmUpPlanner` decides prescriptions (plan's `warmUpSets`, else a synthesized 50%x8/70%x5 ramp for the first exercise of the first two straight groups; fresh supersets never receive warm-ups). `WorkoutSession.create` materializes them; `setNumber` counts within each set type. Ghost/prefill and superset-round matching are set-type-aware, so completed warm-ups can survive a mid-workout regroup without shifting working rounds. Warm-ups rest `min(default, 60)`s and are excluded from PRs/volume/progression on both client and server.
- Bodyweight exercises (`Exercise.isBodyweight`: equipment ⊆ {bodyweight, pullUpBar, bench}) complete with reps alone; the weight field shows a "BW" placeholder and any entered weight means added load. Zero-weight sets earn `reps` PRs (rules allow `weight`/`estimated1RM`/`reps`); they produce no server progressRecords (weight>0 filter) — known limitation.
- Post-workout "How hard was it?" slider stores `session.mood` 1-5 as difficulty: Meh/Manageable/Solid/Tough/Brutal (1 = too easy, 5 = overreached; display-only, not read by progression).
- Dashboard has a tappable Monday-Sunday activity strip. Each day shows exact-date LiftIQ sessions plus device-local Apple Health workouts; imported activities never affect lifting stats, PRs, progression, or plan rotation. "Up Next" recommends the plan day after the most recently completed LiftIQ session (`DashboardViewModel.nextWorkout`, cycles at rotation end) — it is not weekday-based. A "Change" menu on the card lets the user pick any plan day instead. Welcome screen has a swipeable tutorial carousel; sign-up validates live with a strength meter.
- History: Dashboard Recent Activity rows open `SessionDetailView` (edit set weights/reps of finished sessions, delete with confirmation); "See All" opens `WorkoutHistoryView`, a weekly calendar of past sessions plus projected upcoming plan days; planned rows are tappable and start that workout. `WorkoutService.deleteSession` best-effort deletes the session's PRs client-side; progressRecords cleanup is server-side.
- Progress tab: an "Overview" section leads (stat tiles + all-exercise charts) with per-exercise drill-down ("By Exercise") kept below, all Swift Charts from progressRecords. `Utilities/ProgressOverview.swift` computes the executive aggregates: a weekly strength index (each lift's log-e1RM vs its own first-two-session baseline, averaged per week — averaging ~N lifts cuts the ~9% single-observation noise by √N, so the composite can show trends single-lift charts can't), total weekly volume, and distinct training days. The composite trend reuses `StrengthTrend.fit` with `observationSD` scaled by √(mean observations/week), floored at 0.035 because same-day lifts aren't independent. The window is an explicit rolling 26 weeks (`ProgressOverview.windowDays`); both overview fetches paginate within it (`getAllRecords`, `getCompletedSessionDates` — date-range + same-field order, no composite index, status filtered client-side), so no fixed limit can truncate baselines or the current week. Volume/training-day series are zero-filled per calendar week through today (time off reads as zeros); training days come from completed-session dates so bodyweight-only days count; the strength index keeps only observed weeks. On a failed load the section stays hidden (first load) or keeps the last successful overview (refresh) — it never replaces the screen.
- Program day rows deep-link into `WorkoutExecutionView`. Resuming an interrupted session rebuilds superset rest and progression suggestions from the plan. Mid-workout edits are session-scoped and never written back to the plan, so on resume the saved template can name more exercises than the session holds (`removeExercise`) or different ones (`swapExercise`); `rebuildTemplateContextIfNeeded` runs the plan's groups through `reconcileGroups` before mapping. Each `ExerciseLog` carries `plannedExerciseId`, the `PlannedExercise.id` it was materialized from, and `alignBySlotIdentity` uses it to realign exactly: removals take the whole log, swaps keep the slot and only change `exerciseId`, so the two never have to be told apart by guesswork. Exercise ids alone can't do that — a plan of A, then B+C as a superset, whose session holds [X, C], is equally "swap A, remove B" and "remove A, swap B", and those reconstruct to different groupings. `alignByExerciseId` is the fallback, taken when no log carries a slot id (sessions written before the field — it decodes nil, no migration needed), when no log's slot id appears in this plan (a workout-scope AI edit re-points logs at the modified template while the plan keeps its own ids), or when the surviving slots don't line up positionally with the session's leading logs. Matching zero slots must return nil, not an empty group list — the positional check passes vacuously on empty and would resume the session with no groups at all. The fallback resolves unequal ids by lookahead; it is a heuristic and can guess wrong, degrading to coarser grouping. Emptied groups are dropped and a superset that lost an exercise degrades to straight. Keep `plannedExerciseId` accurate through any new merge path — `applyModifiedWorkout` re-points kept logs at the modified template's slot and clears it on dropped-but-completed orphans. `exerciseGroupMap` keys are subscripts into `session.exerciseLogs` — `buildGroupMap` and `exerciseLogIndices(forGroupIndex:)` both bound them to that array's count, and `ExerciseCardView` reads its log as an optional, because a stale index used to be a hard crash on scroll (the cards live in a `LazyVStack`, so it only fired when the bad row materialized).
- Rest precedence: a set `UserProfile.defaultRestSeconds` (Profile → Custom Rest Timer) overrides everything; when nil, AI/planned per-exercise rest wins with a 60s fallback. Rest end plays `SoundEffects.restComplete()` + haptic in the foreground; the local notification only sounds in the background (no foreground-presentation delegate — adding one would double-ring). Notification permission is requested by `RestTimerController.requestNotificationAuthorizationIfNeeded()` from `WorkoutExecutionView`'s `.task` (not mid-set); scheduling checks `getNotificationSettings`, computes the trigger from the wall-clock `endDate`, and re-validates a generation counter on the main actor before adding (a skip/adjust/restart during the async settings callback invalidates it). Rest expiring in the background finishes silently on foreground return (the notification already rang); the controller takes an injectable `now` closure for tests. Profile's Workout Settings section shows an "Open Settings" shortcut + footer warning when notifications are denied.
- `HealthKitService` has separate device-local toggles for exporting completed sessions and showing external Apple Health workouts. Exports use `.traditionalStrengthTraining` and `HKMetadataKeyExternalUUID` = session id; dashboard imports exclude LiftIQ's own source to prevent duplicates. Imported `ExternalActivity` values are never persisted or converted to `WorkoutSession`. Export on `completeSession` and cleanup on `deleteSession` are best-effort and must never block those flows.
- External activity import reads `HKWorkout` records only. Oura/iHealth data appears when those apps write workouts to Apple Health; there is no direct Oura or iHealth API integration. HealthKit does not expose read-denial status, so a completed authorization request can legitimately return no activities.
- Equipment presets live in `EquipmentView.swift` as `EquipmentPreset`. Include `bodyweight` when a preset should match pull-up-bar/bodyweight exercises.

## Firestore

```text
/users/{userId}                        LiftIQUser
/users/{userId}/workoutPlans/{id}      WorkoutPlan with embedded WorkoutTemplates
/users/{userId}/workoutSessions/{id}   WorkoutSession with embedded ExerciseLogs + SetLogs
/users/{userId}/progressRecords/{id}   ProgressRecord per exercise/session — server-write-only
/users/{userId}/personalRecords/{id}   PersonalRecord — client-written, rules-validated
/users/{userId}/bodyMeasurements/{id}  Rules exist; the client stack was removed as dead code
/exercises/{id}                        Exercise, global read-only, served cache-first on the client
/aiUsageLogs/{id}                      Server-only usage logs; also the rate-limit ledger
```

Rate limiting needs a composite index on `aiUsageLogs (userId, function, createdAt)`.

## Gotchas

- After adding/removing Swift files, run `cd LiftIQ && xcodegen generate`.
- `GoogleService-Info.plist` is gitignored but referenced by `project.yml`; keep it at `LiftIQ/GoogleService-Info.plist`.
- `Tab()` is iOS 18+; this app targets iOS 17, so use `.tabItem { Label(...) }` with `.tag(...)`.
- `.foregroundStyle(.accentColor)` can fail in ternaries; use `Color.accentColor`.
- `lazy var` does not work with `@Observable`; prefer `let` dependencies.
- Claude model IDs live only in `firebase/functions/src/models.ts`. Sonnet 5 runs adaptive thinking when `thinking` is omitted — keep it explicitly disabled there; Haiku calls must omit `thinking` entirely.
- SDK 0.39 throws "Streaming is strongly recommended" for non-streaming calls with `max_tokens` > ~21k unless `timeout` is set on the `new Anthropic(...)` **constructor** — a per-request timeout does not help (the guard evaluates first). Diagnose any client-facing "internal error" via `npx firebase-tools functions:log --project trainai-3d40a` — the functions log full errors server-side.
- `generateWorkoutPlan`'s system blocks are prompt-cached: keep them byte-stable. Timestamps and per-user values belong in the user message, after the cache breakpoint.
- Firestore rules tests must run through `firebase emulators:exec`, not plain Vitest.
- Release checks fail on missing privacy manifest, placeholder Firebase config, `print()`, `NSLog`, or likely hardcoded secrets.
- Editing `firebase/functions/src/data/exercises.json` does not update Firestore. Redeploy Functions (the JSON is bundled at deploy time), then reseed:
  `curl -X POST -H "x-admin-key: $(firebase functions:secrets:access ADMIN_SEED_KEY --project trainai-3d40a)" https://us-central1-trainai-3d40a.cloudfunctions.net/seedExerciseDatabase`
  The client serves exercises cache-first — force-quit the app after reseeding to see changes.
- Exercise `youtubeVideoId`s must be verified against YouTube's oEmbed endpoint (`https://www.youtube.com/oembed?url=...watch%3Fv%3D<id>`; 404 = dead, 401 = embedding disabled) — 50 of the original seed IDs were hallucinated and never existed.
- Firebase Functions require Node 20 and secrets `ANTHROPIC_API_KEY` and `ADMIN_SEED_KEY`. Node 20 was deprecated 2026-04-30 and is decommissioned 2026-10-30 — upgrade the runtime (and the outdated `firebase-functions` package) before then.
- Callable AI/account functions enforce App Check; debug builds need the App Check debug provider flow.
- `deleteAccount` also purges the user's aiUsageLogs; extend it if new user-keyed collections appear outside `/users/{uid}`.
- YouTube embeds load `https://trainai-3d40a.web.app/embed.html?v=<id>` (source: `firebase/hosting/embed.html`, deploy with `firebase deploy --only hosting --project trainai-3d40a`), which iframes `youtube-nocookie.com` from a genuine https origin. YouTube requires a valid Referer on embed requests and rejects its absence with Error 153; in WKWebView both `loadHTMLString` (even with a remote baseURL) and a direct top-level load of the embed URL fail that check.
- The HealthKit entitlement and `NSHealth*UsageDescription` strings live in `project.yml` (entitlements file is generated); re-run `xcodegen generate` after touching them. Device builds need the HealthKit capability on the App ID.
