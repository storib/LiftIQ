import { describe, it, expect } from "vitest";
import {
  GenerateWorkoutPlanRequestSchema,
  WorkoutPlanSchema,
  PlannedExerciseSchema,
  EquipmentSchema,
  ExerciseSwapRequestSchema,
} from "../../src/validators/schemas";

const validRequest = {
  experienceLevel: "intermediate",
  goals: ["hypertrophy"],
  availableEquipment: ["barbell", "dumbbell", "bench"],
  trainingDaysPerWeek: 4,
  sessionDurationMinutes: 60,
  injuries: [],
  templateType: "upperLower",
};

describe("GenerateWorkoutPlanRequestSchema", () => {
  it("accepts a fully populated valid request", () => {
    const result = GenerateWorkoutPlanRequestSchema.safeParse(validRequest);
    expect(result.success).toBe(true);
  });

  it("defaults injuries to empty when omitted", () => {
    const { injuries: _omit, ...rest } = validRequest;
    const result = GenerateWorkoutPlanRequestSchema.safeParse(rest);
    expect(result.success).toBe(true);
    if (result.success) expect(result.data.injuries).toEqual([]);
  });

  it("rejects empty equipment array", () => {
    const result = GenerateWorkoutPlanRequestSchema.safeParse({
      ...validRequest,
      availableEquipment: [],
    });
    expect(result.success).toBe(false);
  });

  it("rejects unknown equipment values", () => {
    const result = GenerateWorkoutPlanRequestSchema.safeParse({
      ...validRequest,
      availableEquipment: ["barbell", "rocketship"],
    });
    expect(result.success).toBe(false);
  });

  it("rejects unknown experience level", () => {
    const result = GenerateWorkoutPlanRequestSchema.safeParse({
      ...validRequest,
      experienceLevel: "godlike",
    });
    expect(result.success).toBe(false);
  });

  it("rejects training days outside 1..7", () => {
    expect(
      GenerateWorkoutPlanRequestSchema.safeParse({ ...validRequest, trainingDaysPerWeek: 0 }).success,
    ).toBe(false);
    expect(
      GenerateWorkoutPlanRequestSchema.safeParse({ ...validRequest, trainingDaysPerWeek: 8 }).success,
    ).toBe(false);
  });

  it("rejects session duration below 20 or above 180 minutes", () => {
    expect(
      GenerateWorkoutPlanRequestSchema.safeParse({ ...validRequest, sessionDurationMinutes: 19 }).success,
    ).toBe(false);
    expect(
      GenerateWorkoutPlanRequestSchema.safeParse({ ...validRequest, sessionDurationMinutes: 181 }).success,
    ).toBe(false);
  });

  it("rejects empty goals", () => {
    const result = GenerateWorkoutPlanRequestSchema.safeParse({
      ...validRequest,
      goals: [],
    });
    expect(result.success).toBe(false);
  });

  it("rejects unknown keys via strict mode", () => {
    const result = GenerateWorkoutPlanRequestSchema.safeParse({
      ...validRequest,
      sneakyExtraField: "bad",
    });
    expect(result.success).toBe(false);
  });

  it("accepts a valid injury entry", () => {
    const result = GenerateWorkoutPlanRequestSchema.safeParse({
      ...validRequest,
      injuries: [{ bodyPart: "left knee", severity: "moderate", notes: "post-op" }],
    });
    expect(result.success).toBe(true);
  });

  it("rejects injury with missing fields", () => {
    const result = GenerateWorkoutPlanRequestSchema.safeParse({
      ...validRequest,
      injuries: [{ bodyPart: "knee" }],
    });
    expect(result.success).toBe(false);
  });
});

describe("EquipmentSchema", () => {
  it("accepts every documented equipment value", () => {
    const allEquipment = [
      "barbell",
      "dumbbell",
      "cables",
      "machines",
      "bodyweight",
      "bands",
      "kettlebell",
      "smithMachine",
      "pullUpBar",
      "bench",
      "ezBar",
    ];
    for (const eq of allEquipment) {
      expect(EquipmentSchema.safeParse(eq).success).toBe(true);
    }
  });
});

describe("PlannedExerciseSchema", () => {
  const validPlanned = {
    id: "p1",
    exerciseId: "barbell-bench-press",
    order: 1,
    sets: 4,
    repsMin: 6,
    repsMax: 10,
    restSeconds: 120,
    isOptional: false,
  };

  it("accepts a minimal valid planned exercise", () => {
    expect(PlannedExerciseSchema.safeParse(validPlanned).success).toBe(true);
  });

  it("rejects when repsMax < repsMin (refinement)", () => {
    const result = PlannedExerciseSchema.safeParse({
      ...validPlanned,
      repsMin: 12,
      repsMax: 8,
    });
    expect(result.success).toBe(false);
  });

  it("accepts equal repsMin and repsMax", () => {
    expect(
      PlannedExerciseSchema.safeParse({ ...validPlanned, repsMin: 5, repsMax: 5 }).success,
    ).toBe(true);
  });

  it("rejects sets out of 1..10 range", () => {
    expect(PlannedExerciseSchema.safeParse({ ...validPlanned, sets: 0 }).success).toBe(false);
    expect(PlannedExerciseSchema.safeParse({ ...validPlanned, sets: 11 }).success).toBe(false);
  });
});

describe("WorkoutPlanSchema", () => {
  const validPlan = {
    id: "plan-1",
    userId: "user-1",
    name: "Test Plan",
    templateType: "upperLower",
    goal: "hypertrophy",
    weekCount: 6,
    currentWeek: 1,
    workoutsPerWeek: 4,
    workouts: [],
    isActive: true,
    createdAt: new Date().toISOString(),
    aiGenerated: true,
  };

  it("accepts a structurally valid plan with empty workouts (shape check is separate)", () => {
    expect(WorkoutPlanSchema.safeParse(validPlan).success).toBe(true);
  });

  it("rejects bad templateType enum", () => {
    expect(
      WorkoutPlanSchema.safeParse({ ...validPlan, templateType: "bogus" }).success,
    ).toBe(false);
  });

  it("rejects createdAt that isn't ISO datetime", () => {
    expect(
      WorkoutPlanSchema.safeParse({ ...validPlan, createdAt: "yesterday" }).success,
    ).toBe(false);
  });

  it("rejects weekCount outside 1..16", () => {
    expect(
      WorkoutPlanSchema.safeParse({ ...validPlan, weekCount: 0 }).success,
    ).toBe(false);
    expect(
      WorkoutPlanSchema.safeParse({ ...validPlan, weekCount: 17 }).success,
    ).toBe(false);
  });
});

describe("ExerciseSwapRequestSchema", () => {
  const validSwap = {
    currentExercise: {
      id: "ex-1",
      name: "Bench Press",
      primaryMuscle: "chest",
      movementPattern: "horizontalPush",
    },
    availableEquipment: ["barbell", "bench"],
    otherExercisesInWorkout: ["ex-2", "ex-3"],
  };

  it("accepts a valid swap request", () => {
    expect(ExerciseSwapRequestSchema.safeParse(validSwap).success).toBe(true);
  });

  it("rejects bad muscle group", () => {
    expect(
      ExerciseSwapRequestSchema.safeParse({
        ...validSwap,
        currentExercise: { ...validSwap.currentExercise, primaryMuscle: "tail" },
      }).success,
    ).toBe(false);
  });

  it("rejects bad movement pattern", () => {
    expect(
      ExerciseSwapRequestSchema.safeParse({
        ...validSwap,
        currentExercise: { ...validSwap.currentExercise, movementPattern: "wiggle" },
      }).success,
    ).toBe(false);
  });
});
