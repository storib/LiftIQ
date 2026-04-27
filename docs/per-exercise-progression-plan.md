# Per-Exercise Progression Suggestions

Status: shipped on branch `tests-and-ci` (PR #1)
Owner: Adrian
Started: 2026-04-26
Completed: 2026-04-26

## Goal

When the workout execution view loads, each exercise card shows a tailored
weight/rep suggestion based on the user's recent performance, and the weight
input is prefilled with that suggestion instead of mirroring last session's
exact weight.

This is the first of three planned adaptive features. The others (plateau
detection via `analyzePlateau` Cloud Function, performance-aware plan
regeneration) are out of scope here.

## Current state (what's already in place)

- `Services/ProgressionService.swift` — pure on-device logic. `suggest(...)`
  returns a `ProgressionSuggestion` with weight, rep range, message, and a
  plateau flag. Already covered by one unit test
  (`ProgressionServiceTests.testProgressionSuggestsWeightIncrease`).
- `WorkoutExecutionViewModel.previousLogs` — currently a single most-recent
  log per exercise. Used only for `prefillFromPreviousSession`.
- `WorkoutService.getPreviousExerciseLog(userId:exerciseId:)` — fetches one log.
- `WorkoutService.getSessionsForExercise(userId:exerciseId:)` — fetches an
  array of recent sessions; the "previous" helper just returns `.first`.
- `ExerciseSwapSheet` is already wired and reachable via
  `viewModel.requestSwap(exerciseLogIndex:)`. The plateau warning's CTA can
  reuse this — no new flow needed.
- `Constants.plateauThreshold = 3` (consecutive failures).
- Weight increments per equipment type are already encoded in
  `ProgressionService.weightIncrement(for:)`.

## What's missing (the gap)

1. The VM only loads ONE prior log per exercise. `ProgressionService.suggest`
   needs the recent N logs to detect plateaus. So plateau detection currently
   never fires even though the logic exists.
2. `ProgressionService.suggest` is **never called** from any view or VM.
3. Prefill uses last week's exact weight; doesn't bump on progression or warn
   on plateau.
4. No UI surface for the suggestion message.

## Plan

### 1. Data layer — fetch recent logs (~30 min)

**File:** `LiftIQ/LiftIQ/Services/WorkoutService.swift`

- Add `getRecentExerciseLogs(userId:exerciseId:limit:Int = 5) async throws -> [ExerciseLog]`.
- Reuse `sessionRepository.getSessionsForExercise(...)` (already returns multiple),
  flatMap each session's `exerciseLogs` to the matching exerciseId, take first `limit`.
- Sort newest-first if not already sorted.

**Acceptance:** call returns `[ExerciseLog]` ordered newest-first, length ≤ 5,
or `[]` when no history exists.

### 2. VM integration (~1 hr)

**File:** `LiftIQ/LiftIQ/ViewModels/Workout/WorkoutExecutionViewModel.swift`

- Add `var progressionSuggestions: [String: ProgressionSuggestion] = [:]`
  keyed by `exerciseId`.
- In `start(...)`, after loading exercises and previous logs:
  - For each unique `exerciseId`, fetch recent logs via the new method.
  - Look up the matching `PlannedExercise` from `templateGroups` (use
    existing `exerciseGroupMap`).
  - Call `dependencies.progressionService.suggest(for:previousLogs:exerciseInfo:)`
    and store the result in `progressionSuggestions[exerciseId]`.
- Rename `prefillFromPreviousSession()` → `prefillFromSuggestions()`. Logic:
  1. If a suggestion exists with `suggestedWeight > 0`, use it.
  2. Else fall back to last session's weight (current behavior).
  3. Else leave empty.
- Convert kg → user units via existing `UnitConversionService` path.

**Acceptance:** after `start(...)`, `progressionSuggestions` is populated for
every exerciseId that has at least one prior log. Weight inputs reflect the
suggested weight when present.

### 3. UI surface (~1-2 hrs)

**File:** `LiftIQ/LiftIQ/Views/Workout/ExerciseCardView.swift`

- Add a slim pill row above the existing card content showing the suggestion
  message:
  - **Progression** (suggestion exists, `!isPlateaued`, weight > previous):
    green tint, e.g. "Try 65 kg (+2.5 kg from last)".
  - **Hold** (suggestion exists, `!isPlateaued`, weight == previous):
    secondary tint, e.g. "Hit \(repsMax) reps to progress".
  - **Plateau** (`isPlateaued == true`): orange tint, "Plateau — consider
    swapping" + a "Swap" button that calls `viewModel.requestSwap(exerciseLogIndex:)`.
  - **No suggestion** (first session or no history): hide the pill entirely.
- Convert weight to user's display unit before formatting.

**Acceptance:** pill renders the right state; tapping Swap on a plateau pill
opens `ExerciseSwapSheet`; pill is absent for fresh exercises with no history.

### 4. Tests (~30 min)

**File:** `LiftIQ/LiftIQTests/WorkoutExecutionViewModelTests.swift`

- `testSuggestionPopulatedAfterStartWithPreviousLog` — seed a fake prior log,
  call start (or a test seam), assert suggestion exists with bumped weight.
- `testPrefillUsesSuggestedWeightWhenPresent` — when suggestion has
  `suggestedWeight = 62.5`, the weightInput[0][0] reflects 62.5 in user unit.
- `testNoSuggestionWhenNoHistory` — empty previousLogs → no entry in
  `progressionSuggestions`.
- `testPlateauSuggestionCarriesIsPlateauedFlag` — seed 3 prior logs with
  failures; assert `suggestion.isPlateaued == true`.

Note: `start(...)` calls Firebase services. To keep tests pure, either:
(a) extract a `loadSuggestions(for:exerciseLogs:previousLogsByExerciseId:)`
helper that's testable without async dependencies, OR
(b) seed `previousLogs` and `progressionSuggestions` directly and test the
prefill helper. Prefer (a) — it gives us the most coverage.

## Edge cases to watch

- **First session, no history** — `suggest()` returns nil. Pill is hidden;
  prefill falls back to AI's planned weight (typically 0, user types in).
- **Exercise swapped mid-workout** — when `swapExercise(...)` runs, the new
  exercise has no history yet. Need to clear/refetch suggestions for the new
  exerciseId. Add this to step 2's swap path.
- **Mixed working/warmup sets** — `suggest()` already filters to working sets.
  Just verify warmup-only logs return nil.
- **Unit display** — `suggestion.suggestedWeight` is in kg. Pill must render
  using `UnitConversionService.convertWeight(_:to:)` and the user's unit.
- **Previous log with all zeros** — early bail in `suggest()` (no working sets).
  Pill hidden.

## Out of scope

- Calling `analyzePlateau` Cloud Function (that's the next feature, #2).
- Adapting rep targets dynamically.
- Regenerating the plan based on aggregate performance (that's #3).
- Showing suggestion history / "why this suggestion" tooltip (nice-to-have).

## How to resume mid-flight

If work pauses, check `progressionSuggestions` ivar in
`WorkoutExecutionViewModel` to see how far step 2 got. If it exists but isn't
populated in `start(...)`, step 2 is partially done. Step 3 is the long pole;
its progress is visible by whether `ExerciseCardView` renders any pill.

Local verification:

```bash
cd LiftIQ && xcodebuild test -project LiftIQ.xcodeproj -scheme LiftIQ \
  -destination "platform=iOS Simulator,name=iPhone 17,OS=latest"
```

The new test names above will surface gaps clearly.
