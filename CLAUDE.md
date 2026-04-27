# LiftIQ

iOS lifting app. SwiftUI (iOS 17+) + Firebase + Claude API through Cloud Functions + YouTube exercise embeds.

## Quick Commands

```bash
# iOS project generation and build
cd LiftIQ && xcodegen generate
cd LiftIQ && xcodebuild -project LiftIQ.xcodeproj -scheme LiftIQ -destination "generic/platform=iOS Simulator" build

# iOS tests
cd LiftIQ && xcodebuild test -project LiftIQ.xcodeproj -scheme LiftIQ -destination "platform=iOS Simulator,name=iPhone 16"

# Cloud Functions
cd firebase/functions && npm install
cd firebase/functions && npm run build
cd firebase/functions && npm test

# Firestore rules tests need the emulator and Java
cd firebase && firebase emulators:exec --only firestore "cd functions && npm test"
```

## Architecture

MVVM + Service + Repository. All app layers live under `LiftIQ/LiftIQ/`:

```
App/            -> Entry point, Firebase setup, DI container, tab nav
Models/         -> Codable structs + Enums/
Services/       -> Business logic (@Observable), local algorithms, Firebase calls
Repositories/   -> Firestore CRUD, one repository per collection
ViewModels/     -> @Observable view state, validation, service calls
Views/          -> SwiftUI only; keep business logic out
Extensions/     -> Date, Double, Color, View helpers
Utilities/      -> Constants, Formatters, Epley, Haptics
Resources/      -> Assets and PrivacyInfo.xcprivacy
```

Firebase backend in `firebase/functions/src/`:

```
*.ts            -> Cloud Functions for AI, account deletion, progress records, seed
prompts/        -> Versioned Claude API system prompts
validators/     -> Zod request and response schemas
data/           -> exercises.json seed file
test/           -> Firestore rules tests
```

## Key Patterns

- **DI**: `AppDependencies` is an `@Observable` root container injected with `.environment(dependencies)`. Views access it with `@Environment(AppDependencies.self)`.
- **State**: Use the iOS 17 `@Observable` macro. Do not introduce `ObservableObject` or `@Published`.
- **Navigation shell**: `ContentView` routes unauthenticated users to auth, onboarded users to `MainTabView`, and newly signed-in users who need setup to onboarding.
- **Firestore**: User data lives below `/users/{uid}` subcollections. `ExerciseLog` and `SetLog` stay embedded in `WorkoutSession` documents. Global `/exercises` is read-only for clients.
- **AI calls**: Client calls only Firebase Functions through `AIService`; API keys never ship in the app. Structured outputs use Anthropic tool use with forced `tool_choice` rather than prompt-only JSON. Function request payloads and tool inputs are validated with Zod.
- **AI consent**: Personal-data AI features are gated by `AIConsentManager` and `AIConsentSheet`. Bump the consent version when shared data changes.
- **Onboarding**: The final onboarding step saves `UserProfile`, asks for AI consent when needed, then generates and saves an active workout plan if consent exists. Template choice is derived from training days. Equipment selection uses `EquipmentPreset` (Full Gym, Home Gym, Dumbbells + Bench, Bodyweight Only) with the per-item grid below for fine-tuning.
- **Workout generation**: `generateWorkoutPlan` enforces App Check, validates input, filters by equipment, fails fast with `failed-precondition` if no exercises match, then calls Claude with the `save_workout_plan` tool. Prompt version `2.1.0`. Validates the tool input with Zod plus a shape check (workouts non-empty, count matches `trainingDaysPerWeek`, every workout has at least one exercise, `stop_reason !== "max_tokens"`); retries once on any failure and logs raw output ≤4KB. `aiUsageLogs` records `success` and `attempts` for both successful and failed runs.
- **Account deletion**: iOS calls the trusted `deleteAccount` callable Function. The backend recursively deletes `/users/{uid}` and then deletes the Firebase Auth user.
- **Progress**: Workout completion triggers `computeProgressRecords`; deterministic progression stays on-device in `ProgressionService`.
- **Security**: Configure App Check before `FirebaseApp.configure()`. `seedExerciseDatabase` requires `ADMIN_SEED_KEY`. Release builds run `Scripts/release-checks.sh`.
- **YouTube**: Use `YouTubePlayerView` with a `videoId` string only.
- **Units**: Store all weights in kg. Convert only for display through `UnitSystem` and formatting helpers. New users default to `.imperial`.

## Naming

- Models: `LiftIQUser`, `WorkoutPlan`, `Exercise`, `WorkoutSession`, `SetLog`, `PersonalRecord`.
- Enums: `MuscleGroup`, `Equipment`, `Goal`, `TemplateType`, `ExperienceLevel`, `UnitSystem`; enums conform to `String, Codable, CaseIterable, Identifiable` where practical.
- Repositories: `{Entity}Repository`, for example `WorkoutPlanRepository`.
- Services: `{Feature}Service`, for example `WorkoutService`, `AIService`, `ProgressionService`.
- Views: `{Feature}View`, for example `DashboardView`, `WorkoutExecutionView`.
- ViewModels: `{Feature}ViewModel`.

## Firestore Collections

```
/users/{userId}                        -> LiftIQUser
/users/{userId}/workoutPlans/{id}      -> WorkoutPlan with embedded WorkoutTemplates
/users/{userId}/workoutSessions/{id}   -> WorkoutSession with embedded ExerciseLogs + SetLogs
/users/{userId}/progressRecords/{id}   -> ProgressRecord per exercise/session
/users/{userId}/personalRecords/{id}   -> PersonalRecord
/users/{userId}/bodyMeasurements/{id}  -> BodyMeasurement
/exercises/{id}                        -> Exercise, global read-only client data
/aiUsageLogs/{id}                      -> Server-only cost/usage logs
```

## Current Status

Phase 2 core flows are in place: auth, onboarding with optional AI plan generation, dashboard, program browsing, workout execution, progress tracking, account deletion, security rules, and release checks.

Before TestFlight, deploy Functions and Firestore rules, set required secrets, seed exercises, enable App Check enforcement in Firebase, confirm production `GoogleService-Info.plist`, and verify App Store privacy labels.

## Gotchas

- `.foregroundStyle(.accentColor)` does not compile in ternaries; use `Color.accentColor` explicitly.
- `Tab()` is iOS 18+; this app targets iOS 17, so use `.tabItem { Label(...) }` with `.tag(...)`.
- `lazy var` does not work with `@Observable`; use `let` dependencies where possible.
- After adding or removing Swift files, run `cd LiftIQ && xcodegen generate`.
- `GoogleService-Info.plist` is gitignored but referenced by `project.yml`; keep the local file at `LiftIQ/GoogleService-Info.plist`.
- Firebase Functions require Node 20 and secrets `ANTHROPIC_API_KEY` and `ADMIN_SEED_KEY`.
- Callable AI/account functions enforce App Check; debug builds need the App Check debug provider flow.
- Firestore rules tests must run through `firebase emulators:exec`, not plain Vitest by itself.
- Release builds fail on missing privacy manifest, placeholder Firebase config, `print()`, `NSLog`, or likely hardcoded secrets.
- Editing `firebase/functions/src/data/exercises.json` does not auto-publish to Firestore; re-run `seedExerciseDatabase` (requires `ADMIN_SEED_KEY`) so `availableExercises` filtering finds the new entries.
- New equipment presets live in `EquipmentView.swift` as `EquipmentPreset`; each preset must include `bodyweight` if it should match `pullUpBar+bodyweight` exercises in the seed.
