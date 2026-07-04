# Architecture Remediation Plan

Source: full architecture review (iOS architecture, performance, UI/UX, backend/data model), 2026-07-01.
Phases are ordered by urgency. Each item states the change, the files, and how to do it.

## Phase 0 — Today (production down / data loss)

### 0.1 Migrate off retired Claude model
`claude-sonnet-4-20250514` was retired 2026-06-15; all three AI functions 404.

- **Files:** `firebase/functions/src/generateWorkoutPlan.ts:210`, `analyzePlateau.ts:48`, `suggestExerciseSwap.ts:70`
- **Change:**
  - Add `firebase/functions/src/models.ts` exporting a single `CLAUDE_MODEL = "claude-sonnet-5"` constant; import it in all three functions (no more per-file copies).
  - Set `thinking: { type: "disabled" }` explicitly on all three calls. Sonnet 5 runs adaptive thinking by default when the field is omitted, which would spend thinking tokens inside `max_tokens` and change behavior vs. Sonnet 4.
  - Re-baseline `max_tokens` for the new tokenizer (~30% more tokens for the same text): generateWorkoutPlan 16000 → 24000, analyzePlateau 1500 → 2000, suggestExerciseSwap 2000 → 3000.
- **Verify:** `npm run build && npm test` in `firebase/functions`, then deploy and run one live generation.
- **Note:** cost dashboards keyed to token counts shift with the tokenizer; per-token price is $3/$15 (intro $2/$10 through 2026-08-31).

### 0.2 Surface save/generation errors to the user
`errorMessage` is set but never rendered in the two most critical flows; failures are silent.

- **`LiftIQ/LiftIQ/Views/Workout/WorkoutExecutionView.swift`:** add an `.alert("Couldn't Save", ...)` bound to `viewModel.errorMessage != nil` (clear on dismiss). Covers failed set saves, swap saves, finish, and abandon (`WorkoutExecutionViewModel.swift:213,282,339,454,508,519`).
- **`LiftIQ/LiftIQ/Views/Programs/TemplateBrowserView.swift`:** add an alert bound to `errorMessage` with a **Retry** action (remember the last attempted `TemplateType` in `@State`) and Cancel. Also add expected-duration copy to the generation overlay ("takes about 30 seconds").
- **Verify:** iOS build; force a failure (airplane mode) and confirm the alert shows.

## Phase 1 — This week (correctness in the core loop)

### 1.1 `@MainActor` on all `@Observable` state
No ViewModel/Service is main-actor-isolated; async continuations mutate observed state off-main, and the elapsed timer races `completeSet` on `session`.

- Annotate every `@Observable` class in `ViewModels/` and the stateful services (`WorkoutService`, `AuthService`, `ExerciseService`, `ProgressService`, `AIService`) with `@MainActor`. Repositories stay nonisolated (pure async I/O).
- Fix fallout mechanically (mostly `Task { @MainActor in ... }` removals and test annotations). Run the full test suite.

### 1.2 Wall-clock rest timer + local notification
Timer freezes when backgrounded; no alert when rest ends (`WorkoutExecutionViewModel.swift:462-482, 658-667`).

- Store `restEndDate: Date`; derive `restSecondsRemaining` from wall clock on each tick and on `scenePhase == .active`.
- Same fix for `elapsedSeconds` (derive from `session.startedAt`).
- Request notification permission on first workout start; schedule `UNTimeIntervalNotificationTrigger` when rest starts, cancel on skip/adjust/complete.

### 1.3 Adopt ghost "previous" values on ✓
Tapping complete with empty fields silently no-ops (`SetRowView.swift:37-68`, `completeSet` guard at `WorkoutExecutionViewModel.swift:236`).

- On complete with empty inputs, fall back to the previous-session values shown as placeholders (populate the input arrays, then complete). If no previous values either, fire `Haptics.error()` and flash the fields.

### 1.4 Kill the 600-read workout start
`getSessionsForExercise` fetches 100 full sessions per exercise, serially (`WorkoutSessionRepository.swift:27-34`, VM `start()` loop at :186-202).

- In `start()`: fetch `getSessions(userId:limit:100)` **once**, build a `[exerciseId: [ExerciseLog]]` map in memory, use it for all exercises and for `swapExercise`.
- Delete `getSessionsForExercise` or reimplement later against a denormalized `exerciseIds` array field (Phase 3).

### 1.5 Stop per-second full-list re-render + YouTube reload
- Remove `session.durationSeconds = elapsedSeconds` from the 1s tick (`WorkoutExecutionViewModel.swift:660-664`); it's already stamped at persistence points.
- `YouTubePlayerView.updateUIView`: track last-loaded `videoId` in the `Coordinator`; only `loadHTMLString` on change.

### 1.6 Fast set completion
- Start rest timer + haptic immediately on ✓; run PR check + `updateSession` afterwards.
- Cache best PR values per exercise at `start()` (one bounded query) instead of re-reading all PRs per set; add a `limit` to `PersonalRecordRepository.getRecords(userId:exerciseId:)` (currently unbounded).

### 1.7 Backend contract hardening
- **Zod ints:** add `.int()` to every integer field in `validators/schemas.ts` (`restSeconds`, `rirTarget`*, `dayNumber`, `weekCount`, `currentWeek`, `deloadWeek`, `estimatedDurationMinutes`, `restBetweenRoundsSeconds`); decide `rirTarget` (make Swift `Double?` or keep int). Consider `strict: true` on the tool definition.
- **Server-side normalization** in `generateWorkoutPlan` after validation: `plan.id = randomUUID()`, `plan.userId = auth.uid`, `plan.createdAt = new Date().toISOString()`, `workouts.forEach(w => w.planId = plan.id)`.
- **Rate limiting:** before each Anthropic call, count the user's `aiUsageLogs` in the last 24h (needs a `userId` index) and throw `resource-exhausted` over a cap (e.g. 5 generations/day, 20 swaps/day). Add `maxInstances` to `analyzePlateau` and `suggestExerciseSwap`.

## Phase 2 — Before launch

- **Unit display fixes:** route Dashboard volume/`kg` strings (`DashboardView.swift:149,176`) and Progress PR values (`ProgressDashboardView.swift:28`) through the user's `unitSystem` via the existing formatting helpers.
- **Tap targets & keyboard:** 44×44 frames + `contentShape` on the set checkmark, set-type menu, swap button; `@FocusState` chain with keyboard toolbar (next/Done) across weight→reps→RPE.
- **Rules lockdown:** `progressRecords` client writes → `false` (Admin SDK writes them); add `hasOnlyFields` + numeric bounds to `personalRecords`/`workoutSessions`; add rules tests for `progressRecords`/`bodyMeasurements`.
- **`deleteAccount` erasure gap:** batch-delete `/aiUsageLogs` where `userId == uid`.
- **`computeProgressRecords` fixes:** recompute whenever `after.status == "completed"` (writes are idempotent); delete records on session delete; group logs by `exerciseId` before computing; add `exerciseName` to records.
- **Plateau schema tightening:** replace `z.record(z.unknown())` request shapes with explicit bounded schemas; cap serialized prompt length. Move both small AI functions to tool-use/structured output (kills the raw `JSON.parse`); consider `claude-haiku-4-5` for both (~70% cheaper).
- **Onboarding decline path:** on consent decline, change CTA to "Finish Setup" and land on an explanatory state; block TabView page-swipe past invalid steps.
- **Accessibility pass:** `accessibilityLabel`/`accessibilityValue` on all icon-only buttons (set ✓, swap, ellipsis, injury ✕, plans +, mood emoji); VoiceOver announcement for PR overlay.
- **Confirmation on plan delete** (swipe-to-delete in `WorkoutPlanListView`); make plan activate/deactivate a single `WriteBatch`.
- **Error-handling policy:** adopt the existing `ErrorView`/`EmptyStateView`; add `.refreshable` to Dashboard/Progress/Plans; gate Dashboard empty state on `isLoading`.

## Known tradeoff (accepted, with designed fix)

- **Client PR deletion is best-effort.** Rollback paths (uncomplete/remove/swap/abandon) delete personalRecords docs with `try?`; Firestore's offline queue makes real loss rare, but a server-side rejection could strand a record. Designed fix when wanted: extend the session-write trigger to reconcile — abandoned session → delete PRs with its `sessionId`; completed-session write → delete PRs whose `sessionId` matches but whose id no set's `personalRecordIds` references. Idempotent; no tombstones needed.

## Phase 3 — Post-launch

- **Protocol seams + fakes:** protocols at the Service layer, injected via `AppDependencies`; in-memory fakes; unit tests for `start`/`completeSet`/PR flows. Fix DI stragglers (`AuthService` self-constructs `UserRepository`/`Functions`; VM ignores `AppDependencies.progressionService`).
- **Decompose `WorkoutExecutionViewModel`** (736 lines): init-inject services + userId, extract `RestTimerController` and superset rest policy, move `createSession` into `WorkoutService`. Replace parallel `weightInputs`/`repsInputs`/`rpeInputs` arrays with a `[SetLog.ID: SetInput]` dictionary (removes the force-subscript crash risk).
- **Session ownership:** make `WorkoutService` own the active session; resume path re-fetches template to rebuild `templateGroups` (currently loses superset/progression context).
- **PR lifecycle:** identity-based rollback (store PR ids on SetLog) or defer PR persistence to session completion; clean up PRs in `abandonWorkout`.
- **Epley consolidation:** `SetLog.estimated1RM` delegates to `Epley.estimated1RM` (reps==1 case); verify server formula matches.
- **Exercise catalog caching:** bundle `exercises.json` + version sentinel doc, or Firestore persistent cache (saves 136 reads/launch).
- **Swift Charts in Progress tab:** e1RM line per exercise from `progressRecords` + weekly volume bars; loading/error states.
- **Prompt/cost efficiency:** compact JSON for the exercise DB in prompts (drop unused fields), `cache_control` on the system block; `suggestExerciseSwap` resolves results from in-memory candidates (no re-fetch) and guards empty candidates.
- **Dead-code sweep:** `Epley.swift` (after 3.5), `Constants.defaultRestSeconds` (misleading 90 vs real 60), unused `AIService.suggestExerciseSwap` client path, `BodyMeasurement` stack, unused repo methods; dedupe unit-conversion (x3) and Firebase auth error mapping (x2, use `AuthErrorCode` not magic ints).
- **UI polish:** PR celebration → non-blocking toast; `liftPR` adaptive color; mm:ss header clock; shared card/radius constants (adopt `cardStyle()`); Dynamic Type-safe set-row grid.
