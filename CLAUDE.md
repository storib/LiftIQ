# LiftIQ

iOS lifting app. SwiftUI (iOS 17+) + Firebase + Claude API + YouTube embeds.

## Build

```bash
# iOS — requires xcodegen
cd LiftIQ && xcodegen generate
xcodebuild -project LiftIQ.xcodeproj -scheme LiftIQ -destination "generic/platform=iOS Simulator" build

# Cloud Functions
cd firebase/functions && npm install && npm run build
```

## Architecture

MVVM + Service + Repository. All layers in `LiftIQ/LiftIQ/`:

```
App/            → Entry point, DI container (AppDependencies), tab nav
Models/         → Codable structs + Enums/
Services/       → Business logic (@Observable), local algorithms
Repositories/   → Firestore CRUD (one per collection)
ViewModels/     → @Observable, owns view state, calls Services
Views/          → SwiftUI only, no business logic
Extensions/     → Date, Double, Color, View helpers
Utilities/      → Constants, Formatters, Epley (1RM calc), Haptics
```

Firebase backend in `firebase/functions/src/`:
```
*.ts            → Cloud Functions (generateWorkoutPlan, suggestExerciseSwap, analyzePlateau, seed)
prompts/        → Versioned Claude API system prompts
validators/     → Zod schemas for AI output validation
data/           → exercises.json (100 exercises, seed file)
```

## Key Patterns

- **DI**: `AppDependencies` (@Observable) → injected via `.environment()` at root. Views access with `@Environment(AppDependencies.self)`.
- **State**: iOS 17 `@Observable` macro everywhere (not ObservableObject/@Published).
- **Firestore**: User data in subcollections (`/users/{uid}/workoutSessions/...`). ExerciseLogs/Sets embedded in session docs (not subcollections). Global `/exercises` collection is read-only.
- **AI calls**: Always through Cloud Functions (API key never on client). Prompts versioned in `prompts/`. Output validated with Zod before returning.
- **Progressive overload**: Deterministic, runs on-device in `ProgressionService`. AI reserved for plan generation, swaps, plateau analysis.
- **YouTube**: WKWebView iframe embed via `YouTubePlayerView`. Pass `videoId` string only.
- **Units**: All weights stored in kg internally. Converted at display time via `UnitSystem` enum.

## Naming

- Models: `LiftIQUser`, `WorkoutPlan`, `Exercise`, `SetLog`, etc.
- Enums: `MuscleGroup`, `Equipment`, `Goal`, `TemplateType`, etc. All conform to `String, Codable, CaseIterable, Identifiable`.
- Repos: `{Entity}Repository` (e.g., `WorkoutPlanRepository`)
- Services: `{Feature}Service` (e.g., `WorkoutService`, `ProgressionService`)
- Views: `{Feature}View` (e.g., `DashboardView`, `WorkoutExecutionView`)
- ViewModels: `{Feature}ViewModel`

## Firestore Collections

```
/users/{userId}                        → LiftIQUser
/users/{userId}/workoutPlans/{id}      → WorkoutPlan (embedded WorkoutTemplates)
/users/{userId}/workoutSessions/{id}   → WorkoutSession (embedded ExerciseLogs + SetLogs)
/users/{userId}/progressRecords/{id}   → ProgressRecord (per-exercise time series)
/users/{userId}/personalRecords/{id}   → PersonalRecord
/users/{userId}/bodyMeasurements/{id}  → BodyMeasurement
/exercises/{id}                        → Exercise (global, read-only, seeded)
```

## Current Status

Phase 1 complete. See `engineering-roadmap.md` for full phased plan.

## Gotchas

- `.foregroundStyle(.accentColor)` doesn't compile in ternaries — use `Color.accentColor` explicitly.
- `Tab()` API is iOS 18+ — use `.tabItem { Label() }` + `.tag()` instead.
- `lazy var` doesn't work with `@Observable` — use `let` instead.
- After adding/removing Swift files, re-run `xcodegen generate` to update the .xcodeproj.
- `GoogleService-Info.plist` is gitignored — each dev needs their own Firebase project config.
