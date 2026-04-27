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
cd firebase/functions && npm test

# Firestore rules tests require Java + emulator
cd firebase && firebase emulators:exec --only firestore "cd functions && npm test"
```

## Architecture

App code lives under `LiftIQ/LiftIQ/`:

```text
App/            Firebase setup, DI container, tab shell
Models/         Codable structs and enums
Services/       @Observable business logic and Firebase calls
Repositories/   Firestore CRUD, one repository per collection
ViewModels/     @Observable view state and validation
Views/          SwiftUI only
Extensions/     Date, Double, Color, View helpers
Utilities/      Constants, Formatters, Epley, Haptics
Resources/      Assets and PrivacyInfo.xcprivacy
```

Backend code lives under `firebase/functions/src/`:

```text
*.ts            Cloud Functions for AI, account deletion, progress, seed
prompts/        Versioned Claude prompts
validators/     Zod request/response schemas
data/           exercises.json seed data
test/           Vitest + Firestore rules tests
```

## Patterns

- Use `@Observable`; do not introduce `ObservableObject` or `@Published`.
- Inject `AppDependencies` with `.environment(dependencies)` and read it via `@Environment(AppDependencies.self)`.
- Keep Views UI-only. Put validation/orchestration in ViewModels, business logic in Services, Firestore details in Repositories.
- User data is under `/users/{uid}`. `WorkoutSession` embeds `ExerciseLog` and `SetLog`. Global `/exercises` is client read-only.
- Store all weights in kg. Convert only at display/input boundaries via `UnitSystem` and formatting helpers. New users default to imperial.
- Client AI calls go only through `AIService` and Firebase Functions. API keys never ship in the app.
- Personal-data AI features require `AIConsentManager`/`AIConsentSheet`; bump consent version when shared data changes.
- `generateWorkoutPlan` uses Anthropic tool use (`save_workout_plan`) plus Zod validation and shape checks. Keep prompt/schema/client models in sync.
- Workout completion triggers `computeProgressRecords`; deterministic progression stays on-device in `ProgressionService`.

## Current UX

- Onboarding collects profile, equipment presets/customization, optional AI consent, and can generate an active plan.
- Program day exercise rows can start `WorkoutExecutionView` deep-linked to that exercise.
- User default rest is `UserProfile.defaultRestSeconds` with a 60s fallback; AI/planned rest values win.
- Equipment presets live in `EquipmentView.swift` as `EquipmentPreset`. Include `bodyweight` when a preset should match pull-up-bar/bodyweight exercises.

## Firestore

```text
/users/{userId}                        LiftIQUser
/users/{userId}/workoutPlans/{id}      WorkoutPlan with embedded WorkoutTemplates
/users/{userId}/workoutSessions/{id}   WorkoutSession with embedded ExerciseLogs + SetLogs
/users/{userId}/progressRecords/{id}   ProgressRecord per exercise/session
/users/{userId}/personalRecords/{id}   PersonalRecord
/users/{userId}/bodyMeasurements/{id}  BodyMeasurement
/exercises/{id}                        Exercise, global read-only client data
/aiUsageLogs/{id}                      Server-only usage logs
```

## Gotchas

- After adding/removing Swift files, run `cd LiftIQ && xcodegen generate`.
- `GoogleService-Info.plist` is gitignored but referenced by `project.yml`; keep it at `LiftIQ/GoogleService-Info.plist`.
- `Tab()` is iOS 18+; this app targets iOS 17, so use `.tabItem { Label(...) }` with `.tag(...)`.
- `.foregroundStyle(.accentColor)` can fail in ternaries; use `Color.accentColor`.
- `lazy var` does not work with `@Observable`; prefer `let` dependencies.
- Firestore rules tests must run through `firebase emulators:exec`, not plain Vitest.
- Release checks fail on missing privacy manifest, placeholder Firebase config, `print()`, `NSLog`, or likely hardcoded secrets.
- Editing `firebase/functions/src/data/exercises.json` does not update Firestore. Redeploy Functions if needed, then rerun `seedExerciseDatabase` with `ADMIN_SEED_KEY`.
- Firebase Functions require Node 20 and secrets `ANTHROPIC_API_KEY` and `ADMIN_SEED_KEY`.
- Callable AI/account functions enforce App Check; debug builds need the App Check debug provider flow.
