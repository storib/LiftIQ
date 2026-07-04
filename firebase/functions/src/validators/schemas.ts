import { z } from "zod";

export const MuscleGroupSchema = z.enum([
  "chest", "back", "shoulders", "biceps", "triceps", "forearms",
  "quads", "hamstrings", "glutes", "calves", "core",
  "traps", "lats", "rearDelts", "sideDelts", "frontDelts",
]);

export const EquipmentSchema = z.enum([
  "barbell", "dumbbell", "cables", "machines", "bodyweight",
  "bands", "kettlebell", "smithMachine", "pullUpBar", "bench", "ezBar",
]);

export const ExperienceLevelSchema = z.enum([
  "beginner", "intermediate", "advanced",
]);

export const GoalSchema = z.enum([
  "strength", "hypertrophy", "endurance", "generalFitness",
]);

export const GroupTypeSchema = z.enum([
  "straight", "superset", "triset", "circuit", "dropSet",
]);

export const MovementPatternSchema = z.enum([
  "horizontalPush", "horizontalPull", "verticalPush", "verticalPull",
  "hipHinge", "squat", "lunge", "isolation", "carry", "core",
]);

export const TemplateTypeSchema = z.enum([
  "ppl", "upperLower", "fullBody", "broSplit", "custom",
]);

const InjurySchema = z.object({
  bodyPart: z.string().min(1).max(100),
  severity: z.string().min(1).max(50),
  notes: z.string().max(500),
}).strict();

export const GenerateWorkoutPlanRequestSchema = z.object({
  experienceLevel: ExperienceLevelSchema,
  goals: z.array(GoalSchema).min(1).max(4),
  availableEquipment: z.array(EquipmentSchema).min(1).max(11),
  trainingDaysPerWeek: z.number().int().min(1).max(7),
  sessionDurationMinutes: z.number().int().min(20).max(180),
  injuries: z.array(InjurySchema).max(20).optional().default([]),
  templateType: TemplateTypeSchema,
}).strict();

// Field names/shapes match what AIService.swift sends for suggestExerciseSwap:
// currentExercise {id, name, primaryMuscle, movementPattern}, availableEquipment
// raw values, and the workout's other exercise IDs.
export const ExerciseSwapRequestSchema = z.object({
  currentExercise: z.object({
    id: z.string().min(1).max(200),
    name: z.string().min(1).max(200),
    primaryMuscle: MuscleGroupSchema,
    movementPattern: MovementPatternSchema,
  }).strict(),
  availableEquipment: z.array(EquipmentSchema).min(1).max(11),
  otherExercisesInWorkout: z.array(z.string().min(1).max(200)).max(30),
}).strict();

export const ExerciseSwapSuggestionSchema = z.object({
  exerciseId: z.string().min(1).max(200),
  rationale: z.string().min(1).max(500),
}).strict();

// Shape of the forced save_exercise_swaps tool input.
export const ExerciseSwapResponseSchema = z.object({
  suggestions: z.array(ExerciseSwapSuggestionSchema).min(1).max(5),
}).strict();

// One data point of exercise history, mirroring the ProgressRecord fields the
// client stores per exercise/session. There is no client caller of
// analyzePlateau today; this bounds the shape for when one is added.
export const PlateauHistoryEntrySchema = z.object({
  date: z.string().min(1).max(40),
  estimated1RM: z.number().min(0).max(1000),
  bestSetWeight: z.number().min(0).max(1000),
  bestSetReps: z.number().int().min(0).max(100),
  totalVolume: z.number().min(0).max(1000000),
  totalSets: z.number().int().min(0).max(100),
  rpe: z.number().min(0).max(10).optional(),
}).strict();

export const PlateauUserProfileSchema = z.object({
  experienceLevel: ExperienceLevelSchema,
  goals: z.array(GoalSchema).min(1).max(4),
  trainingDaysPerWeek: z.number().int().min(1).max(7).optional(),
  bodyWeightKg: z.number().min(20).max(500).optional(),
}).strict();

export const PlateauAnalysisRequestSchema = z.object({
  exercise: z.string().min(1).max(200),
  history: z.array(PlateauHistoryEntrySchema).min(1).max(30),
  userProfile: PlateauUserProfileSchema,
  currentProgramWeek: z.number().int().min(1).max(52),
}).strict();

export const PlannedExerciseSchema = z.object({
  id: z.string(),
  exerciseId: z.string(),
  order: z.number().int(),
  sets: z.number().int().min(1).max(10),
  repsMin: z.number().int().min(1).max(50),
  repsMax: z.number().int().min(1).max(50),
  rirTarget: z.number().int().nullable().optional(),
  rpeTarget: z.number().nullable().optional(),
  restSeconds: z.number().int().min(0).max(600),
  warmUpSets: z.array(z.object({
    id: z.string(),
    percentageOf1RM: z.number(),
    reps: z.number().int(),
    label: z.string(),
  })).nullable().optional(),
  notes: z.string().nullable().optional(),
  isOptional: z.boolean(),
}).refine((exercise) => exercise.repsMax >= exercise.repsMin, {
  message: "repsMax must be greater than or equal to repsMin",
  path: ["repsMax"],
});

export const ExerciseGroupSchema = z.object({
  id: z.string(),
  groupType: GroupTypeSchema,
  exercises: z.array(PlannedExerciseSchema),
  restBetweenRoundsSeconds: z.number().int().nullable().optional(),
});

export const WorkoutTemplateSchema = z.object({
  id: z.string(),
  planId: z.string(),
  dayNumber: z.number().int(),
  name: z.string(),
  targetMuscleGroups: z.array(MuscleGroupSchema),
  estimatedDurationMinutes: z.number().int(),
  exerciseGroups: z.array(ExerciseGroupSchema),
  notes: z.string().nullable().optional(),
});

export const WorkoutPlanSchema = z.object({
  id: z.string(),
  userId: z.string(),
  name: z.string(),
  templateType: TemplateTypeSchema,
  goal: GoalSchema,
  weekCount: z.number().int().min(1).max(16),
  currentWeek: z.number().int().min(1),
  workoutsPerWeek: z.number().int().min(1).max(7),
  workouts: z.array(WorkoutTemplateSchema),
  deloadWeek: z.number().int().nullable().optional(),
  isActive: z.boolean(),
  createdAt: z.string().datetime(),
  aiGenerated: z.boolean(),
  aiPromptContext: z.string().nullable().optional(),
});

export const PlateauAnalysisSchema = z.object({
  isPlateaued: z.boolean(),
  confidence: z.enum(["high", "medium", "low"]),
  analysis: z.string(),
  recommendation: z.enum(["deload", "swap", "repSchemeChange", "volumeAdjust", "techniqueFocus"]),
  details: z.string(),
});

export const WeeklyInsightsSchema = z.object({
  insights: z.array(z.string()),
  actionItem: z.string(),
  overallRating: z.enum(["great", "good", "needsAttention"]),
});
