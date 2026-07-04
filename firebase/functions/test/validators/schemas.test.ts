import { describe, it, expect } from "vitest";
import {
  GenerateWorkoutPlanRequestSchema,
  WorkoutPlanSchema,
  PlannedExerciseSchema,
  EquipmentSchema,
  ExerciseSwapRequestSchema,
  ExerciseSwapResponseSchema,
  PlateauAnalysisRequestSchema,
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

  it("rejects non-integer restSeconds (Swift decodes Int)", () => {
    expect(
      PlannedExerciseSchema.safeParse({ ...validPlanned, restSeconds: 90.5 }).success,
    ).toBe(false);
  });

  it("rejects non-integer sets, repsMin, repsMax, and order", () => {
    expect(PlannedExerciseSchema.safeParse({ ...validPlanned, sets: 3.5 }).success).toBe(false);
    expect(PlannedExerciseSchema.safeParse({ ...validPlanned, repsMin: 6.1 }).success).toBe(false);
    expect(PlannedExerciseSchema.safeParse({ ...validPlanned, repsMax: 9.9 }).success).toBe(false);
    expect(PlannedExerciseSchema.safeParse({ ...validPlanned, order: 1.5 }).success).toBe(false);
  });

  it("rejects non-integer rirTarget but accepts integer or null", () => {
    expect(PlannedExerciseSchema.safeParse({ ...validPlanned, rirTarget: 1.5 }).success).toBe(false);
    expect(PlannedExerciseSchema.safeParse({ ...validPlanned, rirTarget: 2 }).success).toBe(true);
    expect(PlannedExerciseSchema.safeParse({ ...validPlanned, rirTarget: null }).success).toBe(true);
  });

  it("still accepts fractional rpeTarget (Swift Double)", () => {
    expect(PlannedExerciseSchema.safeParse({ ...validPlanned, rpeTarget: 8.5 }).success).toBe(true);
  });

  it("rejects non-integer warm-up reps but accepts fractional percentageOf1RM", () => {
    const withWarmUps = (warmUpSets: unknown) =>
      PlannedExerciseSchema.safeParse({ ...validPlanned, warmUpSets });
    expect(
      withWarmUps([{ id: "wu1", percentageOf1RM: 0.5, reps: 5.5, label: "warm" }]).success,
    ).toBe(false);
    expect(
      withWarmUps([{ id: "wu1", percentageOf1RM: 0.5, reps: 5, label: "warm" }]).success,
    ).toBe(true);
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

  it("rejects non-integer weekCount, currentWeek, workoutsPerWeek, and deloadWeek", () => {
    expect(WorkoutPlanSchema.safeParse({ ...validPlan, weekCount: 6.5 }).success).toBe(false);
    expect(WorkoutPlanSchema.safeParse({ ...validPlan, currentWeek: 1.5 }).success).toBe(false);
    expect(WorkoutPlanSchema.safeParse({ ...validPlan, workoutsPerWeek: 4.5 }).success).toBe(false);
    expect(WorkoutPlanSchema.safeParse({ ...validPlan, deloadWeek: 5.5 }).success).toBe(false);
    expect(WorkoutPlanSchema.safeParse({ ...validPlan, deloadWeek: 5 }).success).toBe(true);
  });

  it("rejects a plan whose nested exercise has fractional restSeconds", () => {
    const plan = {
      ...validPlan,
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
                  restSeconds: 90.5,
                  isOptional: false,
                },
              ],
            },
          ],
        },
      ],
    };
    expect(WorkoutPlanSchema.safeParse(plan).success).toBe(false);
  });

  it("rejects non-integer dayNumber, estimatedDurationMinutes, and restBetweenRoundsSeconds", () => {
    const makeWorkout = (overrides: Record<string, unknown>) => ({
      ...validPlan,
      workouts: [
        {
          id: "w1",
          planId: "plan-1",
          dayNumber: 1,
          name: "Upper",
          targetMuscleGroups: ["chest"],
          estimatedDurationMinutes: 60,
          exerciseGroups: [],
          ...overrides,
        },
      ],
    });
    expect(WorkoutPlanSchema.safeParse(makeWorkout({ dayNumber: 1.5 })).success).toBe(false);
    expect(
      WorkoutPlanSchema.safeParse(makeWorkout({ estimatedDurationMinutes: 60.5 })).success,
    ).toBe(false);
    expect(
      WorkoutPlanSchema.safeParse(
        makeWorkout({
          exerciseGroups: [
            {
              id: "g1",
              groupType: "superset",
              exercises: [],
              restBetweenRoundsSeconds: 90.5,
            },
          ],
        }),
      ).success,
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

describe("PlateauAnalysisRequestSchema", () => {
  const validHistoryEntry = {
    date: "2026-06-01T10:00:00Z",
    estimated1RM: 120.5,
    bestSetWeight: 100,
    bestSetReps: 6,
    totalVolume: 1800,
    totalSets: 3,
  };

  const validPlateauRequest = {
    exercise: "Bench Press",
    history: [validHistoryEntry, { ...validHistoryEntry, rpe: 8.5 }],
    userProfile: {
      experienceLevel: "intermediate",
      goals: ["strength"],
      trainingDaysPerWeek: 4,
      bodyWeightKg: 82.5,
    },
    currentProgramWeek: 3,
  };

  it("accepts a valid plateau analysis request", () => {
    expect(PlateauAnalysisRequestSchema.safeParse(validPlateauRequest).success).toBe(true);
  });

  it("accepts a minimal user profile", () => {
    expect(
      PlateauAnalysisRequestSchema.safeParse({
        ...validPlateauRequest,
        userProfile: { experienceLevel: "beginner", goals: ["hypertrophy"] },
      }).success,
    ).toBe(true);
  });

  it("rejects history entries with unknown fields", () => {
    expect(
      PlateauAnalysisRequestSchema.safeParse({
        ...validPlateauRequest,
        history: [{ ...validHistoryEntry, injected: "hack" }],
      }).success,
    ).toBe(false);
  });

  it("rejects out-of-range weights in history", () => {
    expect(
      PlateauAnalysisRequestSchema.safeParse({
        ...validPlateauRequest,
        history: [{ ...validHistoryEntry, bestSetWeight: 5000 }],
      }).success,
    ).toBe(false);
  });

  it("rejects empty history", () => {
    expect(
      PlateauAnalysisRequestSchema.safeParse({
        ...validPlateauRequest,
        history: [],
      }).success,
    ).toBe(false);
  });

  it("rejects more than 30 history entries", () => {
    expect(
      PlateauAnalysisRequestSchema.safeParse({
        ...validPlateauRequest,
        history: Array.from({ length: 31 }, () => validHistoryEntry),
      }).success,
    ).toBe(false);
  });

  it("rejects arbitrary userProfile fields", () => {
    expect(
      PlateauAnalysisRequestSchema.safeParse({
        ...validPlateauRequest,
        userProfile: { ...validPlateauRequest.userProfile, email: "a@b.c" },
      }).success,
    ).toBe(false);
  });

  it("rejects program week outside 1..52", () => {
    expect(
      PlateauAnalysisRequestSchema.safeParse({
        ...validPlateauRequest,
        currentProgramWeek: 53,
      }).success,
    ).toBe(false);
  });
});

describe("ExerciseSwapResponseSchema", () => {
  it("accepts 1-5 well-formed suggestions", () => {
    expect(
      ExerciseSwapResponseSchema.safeParse({
        suggestions: [
          { exerciseId: "incline-db-press", rationale: "Same pattern, dumbbell variant." },
        ],
      }).success,
    ).toBe(true);
  });

  it("rejects an empty suggestions array", () => {
    expect(ExerciseSwapResponseSchema.safeParse({ suggestions: [] }).success).toBe(false);
  });

  it("rejects more than five suggestions", () => {
    const suggestion = { exerciseId: "x", rationale: "y" };
    expect(
      ExerciseSwapResponseSchema.safeParse({
        suggestions: Array.from({ length: 6 }, () => suggestion),
      }).success,
    ).toBe(false);
  });

  it("rejects suggestions missing a rationale", () => {
    expect(
      ExerciseSwapResponseSchema.safeParse({
        suggestions: [{ exerciseId: "x" }],
      }).success,
    ).toBe(false);
  });
});
