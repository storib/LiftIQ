# Weight-Dependent e1RM Formula Migration Plan

Status: **planned, not started** (deferred from the 2026-08 plateau/progression rework).

## Why

Replace Epley with the weight-dependent e1RM formula:

```text
e1RM = w × (1 + (r − 1)^0.85 / (−2.55 + 4.58 × ln(w)))    // w in kg, r = reps; r ≤ 1 → w
```

Measured on ~300k near-failure sets, it cuts within-lifter e1RM inconsistency 17-22% vs
Epley/Brzycki (log-space SD ~0.085 vs ~0.103). The gain is largest for light dumbbell and
cable movements — for a 13 kg curl ×10, Brzycki says ~17 kg, this formula ~22 kg — and
Adrian's own accessory work (6.8 kg flys, 18 kg curls, 25 kg DB presses) sits squarely in
that regime, where Epley currently under-credits progress.

Why it can't be a one-line change: Epley parity is load-bearing across four surfaces —
the client (`Utilities/Epley.swift`: PR detection, mid-workout suggestion context), the
server (`computeProgressRecords.ts`, mirrored with parity tests both sides), stored
`progressRecords` (feed the Progress-tab charts and `StrengthTrend`), and stored
`personalRecords` of type `estimated1RM`. Swapping the client alone would make new PRs
incomparable to old ones and put a visible discontinuity in every chart.

## Domain guards (decide before writing code)

- **kg only.** `ln(w)` makes the formula unit-sensitive. It must only ever see stored kg —
  never display-unit (lb) values. This is the highest-risk bug class in the whole migration.
- **Low-weight cutoff.** The denominator `−2.55 + 4.58·ln(w)` is ≤ 0 for w ≤ ~1.75 kg and
  near-zero just above it (exploding estimates). Fall back to Epley below a safe floor —
  propose **w < 5 kg → Epley** (keeps the denominator > 4.8; covers micro-loaded cables).
- **r ≤ 1 → return w**, matching today's Epley contract (both sides already test this).
- **Zero-weight sets** stay excluded (bodyweight; server already filters `weight > 0`).

## Phases

### 1. Shared implementation + parity (client and server, no behavior shipped)

- Client: new `Utilities/E1RM.swift` with `E1RM.estimate(weightKg:reps:)` implementing the
  new formula with the guards above; keep `Epley` (used as the low-weight fallback and by
  the migration comparison script). Server: mirror in `computeProgressRecords.ts` behind a
  `FORMULA_VERSION = 2` constant; stamp `formulaVersion` on every new `progressRecord`.
- Extend the existing client/server parity tests with shared fixtures covering: heavy
  barbell (100 kg × 5), light cable (6.8 kg × 12), the 5 kg fallback boundary (4.9/5.0/5.1),
  r = 1, and r = 30. Update `firebase/functions/src/validators/schemas.ts` if the stamped
  field needs schema coverage.
- Nothing user-visible changes in this phase; the new function is dead code until phase 3.

### 2. Server deploy + full backfill (kills the chart discontinuity)

- `progressRecords` are pure derivations of completed sessions, so history does not need to
  be "migrated" — it needs to be **recomputed**. Admin script (same pattern as
  `seedExerciseDatabase`, gated on `ADMIN_SEED_KEY`): for every user, re-run
  `computeRecordsForSession` over all completed sessions and rewrite their records with
  `formulaVersion: 2`. Idempotent; deterministic ids (`${sessionId}_${exerciseId}`) mean
  rewrites, not duplicates.
- Also recompute stored `estimated1RM`-type `personalRecords` (Admin SDK bypasses the
  client-write rules): recompute each user's e1RM PR history from sessions under the new
  formula. `weight`/`reps`/`volume` PRs are untouched.
- Deploy functions first, then run the backfill immediately — between the two, newly
  completed sessions get v2 records while old records are v1, which is acceptable for the
  minutes the backfill takes.
- Verify: spot-check 2-3 exercises per test user — charts should shift *level* (accessories
  up ~10-25%) but keep shape; no record should exceed the schema's 1000 kg cap.

### 3. Client release

- Switch `ProgressService` PR detection and any e1RM display to `E1RM.estimate`. Session
  PR toasts and the Progress tab then agree with the recomputed server records.
- **Version skew is real and accepted:** older app builds keep minting Epley-based e1RM
  PRs until users update. Server-recomputed records stay canonical; document the skew in
  CLAUDE.md and don't try to gate old clients.
- `StrengthTrend.observationSD` can drop from 0.09 toward 0.08 once the fleet is mostly on
  v2 (the new formula is why the best-case 0.085 exists) — do this later, with data, not in
  the same release.

### 4. Post-migration checks

- Re-run the trend analysis script on Adrian's data; confirm accessory e1RM series are
  less jagged (that's the whole point) and `StrengthTrend` verdicts are unchanged in kind.
- Watch one week of `computeProgressRecords` logs for domain-guard hits (weights < 5 kg).
- Update CLAUDE.md: replace the "Epley parity" bullet with the E1RM/`formulaVersion`
  contract; note Epley remains only as the low-weight fallback.

## Effort / risk

Roughly a focused day: phase 1 is mechanical (the parity-test pattern already exists),
phase 2's script is ~100 lines against existing helpers, phase 3 is a small diff. The two
real risks are the lb/kg mistake in the `ln(w)` term (mitigated by the kg-only API surface
and boundary fixtures) and forgetting a client Epley call site (grep for `Epley.` before
shipping phase 3).
