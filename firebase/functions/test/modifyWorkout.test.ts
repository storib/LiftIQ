import { describe, it, expect } from "vitest";
import {
  normalizeModifiedPlan,
  normalizeModifiedWorkout,
  collectInvalidExerciseIds,
} from "../src/modifyWorkout";
import {
  ModifyWorkoutRequestSchema,
  ModifiedPlanResponseSchema,
  WorkoutPlanSchema,
  WorkoutTemplateSchema,
} from "../src/validators/schemas";

const workout = WorkoutTemplateSchema.parse({
  id: "wk-1",
  planId: "plan-1",
  dayNumber: 1,
  name: "Upper A",
  targetMuscleGroups: ["chest", "back"],
  estimatedDurationMinutes: 60,
  exerciseGroups: [
    {
      id: "g1",
      groupType: "straight",
      exercises: [
        {
          id: "p1",
          exerciseId: "bench-press",
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
});

const plan = WorkoutPlanSchema.parse({
  id: "plan-1",
  userId: "user-1",
  name: "Test Plan",
  templateType: "upperLower",
  goal: "hypertrophy",
  weekCount: 6,
  currentWeek: 2,
  workoutsPerWeek: 1,
  workouts: [workout],
  deloadWeek: 5,
  isActive: true,
  createdAt: "2026-01-05T10:00:00.000Z",
  aiGenerated: true,
  aiPromptContext: null,
});

describe("normalizeModifiedPlan", () => {
  it("keeps the original plan identity and stamps content from the model", () => {
    const modelPlan = {
      ...plan,
      id: "model-invented-id",
      userId: "model-invented-user",
      createdAt: "2030-01-01T00:00:00.000Z",
      isActive: false,
      name: "Chest-Free Plan",
      workouts: [{ ...workout, id: "wk-1", planId: "model-invented-id" }],
    };

    const result = normalizeModifiedPlan(plan, modelPlan, "auth-uid");

    expect(result.id).toBe("plan-1");
    expect(result.userId).toBe("auth-uid");
    expect(result.createdAt).toBe("2026-01-05T10:00:00.000Z");
    expect(result.isActive).toBe(true);
    expect(result.aiGenerated).toBe(true);
    expect(result.name).toBe("Chest-Free Plan");
    expect(result.workouts.every((w) => w.planId === "plan-1")).toBe(true);
  });
});

describe("normalizeModifiedWorkout", () => {
  it("keeps the original workout identity", () => {
    const modelWorkout = {
      ...workout,
      id: "model-id",
      planId: "model-plan",
      dayNumber: 9,
      name: "Upper A (chest-free)",
    };

    const result = normalizeModifiedWorkout(workout, modelWorkout);

    expect(result.id).toBe("wk-1");
    expect(result.planId).toBe("plan-1");
    expect(result.dayNumber).toBe(1);
    expect(result.name).toBe("Upper A (chest-free)");
  });
});

describe("collectInvalidExerciseIds", () => {
  it("flags exercise ids outside the allowed set", () => {
    const allowed = new Set(["bench-press"]);
    expect(collectInvalidExerciseIds([workout], allowed)).toEqual([]);

    const rogue = {
      ...workout,
      exerciseGroups: [
        {
          ...workout.exerciseGroups[0],
          exercises: [
            { ...workout.exerciseGroups[0].exercises[0], exerciseId: "made-up" },
          ],
        },
      ],
    };
    expect(collectInvalidExerciseIds([rogue], allowed)).toEqual(["made-up"]);
  });
});

describe("ModifyWorkoutRequestSchema", () => {
  const base = {
    instruction: "Remove all chest exercises — I have a chest disability.",
    availableEquipment: ["barbell", "bench"],
    injuries: [{ bodyPart: "chest", severity: "severe", notes: "" }],
    experienceLevel: "intermediate",
  };

  it("requires plan for scope plan", () => {
    expect(ModifyWorkoutRequestSchema.safeParse({ ...base, scope: "plan" }).success).toBe(false);
    expect(ModifyWorkoutRequestSchema.safeParse({ ...base, scope: "plan", plan }).success).toBe(true);
  });

  it("requires workout for scope workout", () => {
    expect(ModifyWorkoutRequestSchema.safeParse({ ...base, scope: "workout" }).success).toBe(false);
    expect(
      ModifyWorkoutRequestSchema.safeParse({ ...base, scope: "workout", workout }).success,
    ).toBe(true);
  });

  it("rejects an over-long instruction", () => {
    const req = { ...base, scope: "workout", workout, instruction: "x".repeat(1001) };
    expect(ModifyWorkoutRequestSchema.safeParse(req).success).toBe(false);
  });
});

describe("ModifiedPlanResponseSchema", () => {
  it("accepts a summary plus a valid plan and rejects a missing summary", () => {
    expect(
      ModifiedPlanResponseSchema.safeParse({ changeSummary: "Removed chest work.", plan }).success,
    ).toBe(true);
    expect(ModifiedPlanResponseSchema.safeParse({ plan }).success).toBe(false);
  });
});
