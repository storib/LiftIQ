import { describe, it, expect } from "vitest";
import {
  filterExercisesByEquipment,
  validatePlanShape,
} from "../src/generateWorkoutPlan";
import { WorkoutPlanSchema } from "../src/validators/schemas";

describe("filterExercisesByEquipment", () => {
  const exercises = [
    { id: "bench-press", equipment: ["barbell", "bench"] },
    { id: "pull-up", equipment: ["pullUpBar", "bodyweight"] },
    { id: "cable-fly", equipment: ["cables"] },
    { id: "kettlebell-swing", equipment: ["kettlebell"] },
    { id: "weird", equipment: "barbell" }, // malformed: not an array
  ];

  it("returns only exercises whose equipment is fully covered by user's set", () => {
    const result = filterExercisesByEquipment(exercises, ["barbell", "bench", "cables"]);
    const ids = result.map((e) => e.id);
    expect(ids).toEqual(["bench-press", "cable-fly"]);
  });

  it("excludes exercises that need any missing equipment", () => {
    const result = filterExercisesByEquipment(exercises, ["barbell"]);
    expect(result.map((e) => e.id)).toEqual([]);
  });

  it("returns empty array when user has no equipment", () => {
    expect(filterExercisesByEquipment(exercises, [])).toEqual([]);
  });

  it("returns empty array when exercise database is empty", () => {
    expect(filterExercisesByEquipment([], ["barbell", "bench"])).toEqual([]);
  });

  it("returns all exercises when user has every piece needed", () => {
    const result = filterExercisesByEquipment(exercises, [
      "barbell", "bench", "pullUpBar", "bodyweight", "cables", "kettlebell",
    ]);
    // The malformed entry is excluded because its equipment is not an array
    expect(result.map((e) => e.id).sort()).toEqual(
      ["bench-press", "cable-fly", "kettlebell-swing", "pull-up"].sort(),
    );
  });

  it("ignores entries with non-array equipment field (defensive)", () => {
    const result = filterExercisesByEquipment(exercises, [
      "barbell", "bench", "pullUpBar", "bodyweight", "cables", "kettlebell",
    ]);
    expect(result.map((e) => e.id)).not.toContain("weird");
  });
});

// ──────────────────────────────────────────────
// validatePlanShape
// ──────────────────────────────────────────────

function makePlan(overrides: Partial<{ workouts: unknown[] }> = {}) {
  const base = {
    id: "plan-1",
    userId: "u",
    name: "Test",
    templateType: "upperLower",
    goal: "hypertrophy",
    weekCount: 6,
    currentWeek: 1,
    workoutsPerWeek: 4,
    workouts: [
      {
        id: "w1",
        planId: "plan-1",
        dayNumber: 1,
        name: "Upper",
        targetMuscleGroups: ["chest"],
        estimatedDurationMinutes: 60,
        exerciseGroups: [
          {
            id: "g1",
            groupType: "straight",
            exercises: [
              {
                id: "e1",
                exerciseId: "bench",
                order: 1,
                sets: 3,
                repsMin: 8,
                repsMax: 10,
                restSeconds: 90,
                isOptional: false,
              },
            ],
          },
        ],
      },
    ],
    isActive: true,
    createdAt: new Date().toISOString(),
    aiGenerated: true,
    ...overrides,
  };
  // Coerce through the schema so the typed value matches what validatePlanShape expects
  const parsed = WorkoutPlanSchema.parse(base);
  return parsed;
}

describe("validatePlanShape", () => {
  it("returns ok for a valid single-workout plan when expectedWorkoutCount=1", () => {
    const plan = makePlan();
    const result = validatePlanShape(plan, 1, "tool_use");
    expect(result.ok).toBe(true);
  });

  it("rejects when stop_reason is max_tokens (truncation)", () => {
    const plan = makePlan();
    const result = validatePlanShape(plan, 1, "max_tokens");
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/truncated/i);
  });

  it("rejects when workouts array is empty", () => {
    const plan = makePlan({ workouts: [] });
    const result = validatePlanShape(plan, 0, "tool_use");
    // expectedWorkoutCount=0 still fails because the empty-check fires first
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/empty/i);
  });

  it("rejects when workouts.length doesn't match expected count", () => {
    const plan = makePlan();
    const result = validatePlanShape(plan, 4, "tool_use");
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/expected 4/);
  });

  it("rejects when a workout has no exercises", () => {
    const planWithEmptyWorkout = {
      id: "plan-2",
      userId: "u",
      name: "Test",
      templateType: "upperLower" as const,
      goal: "hypertrophy" as const,
      weekCount: 6,
      currentWeek: 1,
      workoutsPerWeek: 1,
      workouts: [
        {
          id: "w1",
          planId: "plan-2",
          dayNumber: 1,
          name: "Empty Day",
          targetMuscleGroups: ["chest" as const],
          estimatedDurationMinutes: 60,
          exerciseGroups: [],
        },
      ],
      isActive: true,
      createdAt: new Date().toISOString(),
      aiGenerated: true,
    };
    const parsed = WorkoutPlanSchema.parse(planWithEmptyWorkout);
    const result = validatePlanShape(parsed, 1, "tool_use");
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toMatch(/no exercises/i);
  });
});
