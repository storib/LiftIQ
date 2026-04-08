# LiftIQ Engineering Roadmap

## Overview

Native iOS lifting app with AI-powered workout programming, exercise execution logging, progressive overload tracking, plateau detection, and progress reporting.

**Stack:** SwiftUI (iOS 17+) | Firebase (Auth, Firestore, Cloud Functions) | Claude API | YouTube embeds

---

## Phase 1: Foundation -- COMPLETE

- [x] Xcode project setup via xcodegen, SPM dependencies (firebase-ios-sdk, swift-algorithms)
- [x] All data models (12 structs) and enums (10)
- [x] MVVM + Service + Repository architecture with @Observable DI
- [x] Auth flow — email/password sign in, sign up, forgot password (4 views, 2 VMs)
- [x] Onboarding flow — 8-step profile builder (experience, goals, equipment, schedule, injuries, metrics, summary)
- [x] Firebase repositories — 7 Firestore CRUD abstractions
- [x] Core services — Auth, Workout, Exercise, Progress, AI, Progression, UnitConversion
- [x] Dashboard — today's workout card, streak, weekly stats, recent activity
- [x] Programs — plan list, plan detail, day detail, template browser with AI generation trigger
- [x] Progress & Profile — placeholder views
- [x] Shared components — YouTubePlayerView, ExerciseSearchView, LoadingView, ErrorView
- [x] Exercise database — 100 exercises with muscle groups, equipment, YouTube IDs, alternatives
- [x] Cloud Functions — generateWorkoutPlan, suggestExerciseSwap, analyzePlateau, seedExerciseDatabase
- [x] Claude API prompts — versioned system prompts for all AI features
- [x] Zod validators for AI output
- [x] Firestore security rules and composite indexes
- [x] Unit test scaffold (ProgressionServiceTests)

**Files:** 75 Swift (3,579 LOC) + 10 TypeScript (533 LOC) + 100-exercise JSON

---

## Phase 2: Workout Execution -- UP NEXT

The core user experience. This is the most complex screen in the app.

- [ ] `WorkoutExecutionView` — scrollable exercise list with set-by-set input
- [ ] `ExerciseCardView` — YouTube video (collapsible), previous session numbers, set rows
- [ ] `SetRowView` — weight/reps/RPE input fields, completion checkbox, PR indicator
- [ ] `RestTimerView` — countdown overlay, configurable duration, auto-start on set completion, skip/adjust
- [ ] Superset/circuit visual grouping with shared rest timers
- [ ] `WorkoutSummaryView` — post-workout stats, PR highlights, duration, volume, mood selector
- [ ] Session persistence — Firestore write-through after each set (survives app kill)
- [ ] Active session recovery — check for in-progress session on app launch
- [ ] `ExerciseSwapSheet` — manual search-based swap (AI swap in Phase 3)
- [ ] `computeProgressRecords` Cloud Function — Firestore trigger on session completion
- [ ] Previous session's numbers displayed per exercise
- [ ] Unit conversion toggle (kg/lb) in workout execution

**Key files to create:**
- `Views/Workout/WorkoutExecutionView.swift`
- `Views/Workout/ExerciseCardView.swift`
- `Views/Workout/SetRowView.swift`
- `Views/Workout/RestTimerView.swift`
- `Views/Workout/ExerciseSwapSheet.swift`
- `Views/Workout/WorkoutSummaryView.swift`
- `Views/Workout/PRCelebrationOverlay.swift`
- `ViewModels/Workout/WorkoutExecutionViewModel.swift`

---

## Phase 3: Smart Features

- [ ] `ProgressionService` integration — show weight/rep suggestions in workout execution UI
- [ ] `PlateauDetectionService` — flag stalled exercises (3+ sessions no 1RM increase + RPE creep)
- [ ] AI exercise swap — `suggestExerciseSwap` Cloud Function with Claude API
- [ ] AI plateau analysis — `analyzePlateau` Cloud Function with detailed recommendations
- [ ] `DeloadService` — fatigue accumulation tracking, auto-deload week recommendations
- [ ] PR detection during workout — compare each completed set against historical bests
- [ ] `PRCelebrationOverlay` — confetti animation + haptic on new PRs
- [ ] Sign in with Apple + Sign in with Google (Firebase Auth providers)
- [ ] Warm-up set auto-generation based on working weight (Epley formula)

---

## Phase 4: Progress & Reporting

- [ ] `ProgressDashboardView` — summary cards (weekly volume, PRs, body weight trend)
- [ ] `ExerciseProgressView` — per-exercise strength curves (Swift Charts, line chart of est. 1RM over time)
- [ ] `MuscleGroupVolumeView` — stacked bar chart of sets per muscle group per week
- [ ] `PRListView` — chronological PR history with exercise/type filters
- [ ] `BodyMeasurementsView` — log and chart body weight, body fat, circumferences
- [ ] `WeeklyCheckInView` — AI-generated weekly summary with insights and action items
- [ ] `generateWeeklyInsights` Cloud Function (scheduled, runs weekly per active user)
- [ ] Estimated 1RM tracking per exercise over time
- [ ] `ExerciseDatabaseView` — browsable/searchable exercise library with video previews
- [ ] Expand exercise database to 150-200 exercises

---

## Phase 5: Polish & Launch

- [ ] Push notifications (Firebase Cloud Messaging) — workout reminders, rest day suggestions
- [ ] `NotificationSettingsView` — reminder toggles and time pickers
- [ ] Local notifications for rest timer when app is backgrounded
- [ ] Offline support — Firestore offline persistence, graceful network-unavailable handling
- [ ] App icon and launch screen design
- [ ] Accessibility audit (VoiceOver labels, Dynamic Type support)
- [ ] Performance optimization (lazy loading, pagination for long histories)
- [ ] Error handling polish (user-friendly messages, retry logic)
- [ ] Unit tests — ProgressionService, PlateauDetectionService, DeloadService, key ViewModels
- [ ] UI tests — onboarding flow, workout execution flow
- [ ] App Store assets (screenshots, description, keywords, privacy policy)
- [ ] TestFlight beta distribution

---

## Verification Checkpoints

| # | Test | Phase |
|---|------|-------|
| 1 | Complete onboarding, verify personalized plan generates with correct exercises | 1 |
| 2 | Start workout, log sets, verify rest timer and previous session numbers | 2 |
| 3 | Complete multiple sessions hitting all reps, verify weight increase suggestion | 3 |
| 4 | Simulate stalled sessions, verify plateau indicator and AI analysis | 3 |
| 5 | Swap exercise, verify alternatives filtered by equipment and muscle group | 3 |
| 6 | Log several sessions, verify strength curves and volume charts render | 4 |
| 7 | Beat a previous best, verify PR celebration and persistence | 3 |
| 8 | Turn off network, log workout, verify sync on reconnect | 5 |
| 9 | Sign out, sign back in, verify all data persists | 1 |

---

## Technical Decisions

| Decision | Rationale |
|----------|-----------|
| Cloud Functions as AI proxy | API key never on client; prompt updates don't need App Store releases; output validation before client receives data |
| Embedded exercise logs (not subcollections) | 1 read per session (vs. N+M reads); typical session is 5-15 KB, well under 1 MB Firestore doc limit |
| Local progressive overload (not AI) | Deterministic rules don't need AI; instant, offline-capable; AI reserved for higher-order decisions |
| YouTube via WKWebView (not library) | YouTube iOS Player Helper is deprecated; WKWebView gives full control, no third-party dependency |
| Swift Charts (not third-party) | Native to iOS 16+; no dependency risk; supports line, bar, and point annotations |
| xcodegen (not manual .xcodeproj) | Avoids merge conflicts in .xcodeproj; declarative project config; re-run after adding files |
