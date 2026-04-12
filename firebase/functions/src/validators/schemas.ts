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

export const ExerciseSwapRequestSchema = z.object({
  currentExercise: z.object({
    id: z.string().min(1),
    name: z.string().min(1).max(200),
    primaryMuscle: MuscleGroupSchema,
    movementPattern: MovementPatternSchema,
  }).strict(),
  availableEquipment: z.array(EquipmentSchema).min(1).max(11),
  otherExercisesInWorkout: z.array(z.string().min(1)).max(50),
}).strict();

export const ExerciseSwapSuggestionSchema = z.object({
  exerciseId: z.string().min(1),
  rationale: z.string().min(1).max(500),
}).strict();

export const PlateauAnalysisRequestSchema = z.object({
  exercise: z.string().min(1).max(200),
  history: z.array(z.record(z.unknown())).min(1).max(30),
  userProfile: z.record(z.unknown()),
  currentProgramWeek: z.number().int().min(1).max(52),
}).strict();

export const PlannedExerciseSchema = z.object({
  id: z.string(),
  exerciseId: z.string(),
  order: z.number(),
  sets: z.number().min(1).max(10),
  repsMin: z.number().min(1).max(50),
  repsMax: z.number().min(1).max(50),
  rirTarget: z.number().nullable().optional(),
  rpeTarget: z.number().nullable().optional(),
  restSeconds: z.number().min(0).max(600),
  warmUpSets: z.array(z.object({
    id: z.string(),
    percentageOf1RM: z.number(),
    reps: z.number(),
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
  restBetweenRoundsSeconds: z.number().nullable().optional(),
});

export const WorkoutTemplateSchema = z.object({
  id: z.string(),
  planId: z.string(),
  dayNumber: z.number(),
  name: z.string(),
  targetMuscleGroups: z.array(MuscleGroupSchema),
  estimatedDurationMinutes: z.number(),
  exerciseGroups: z.array(ExerciseGroupSchema),
  notes: z.string().nullable().optional(),
});

export const WorkoutPlanSchema = z.object({
  id: z.string(),
  userId: z.string(),
  name: z.string(),
  templateType: TemplateTypeSchema,
  goal: GoalSchema,
  weekCount: z.number().min(1).max(16),
  currentWeek: z.number().min(1),
  workoutsPerWeek: z.number().min(1).max(7),
  workouts: z.array(WorkoutTemplateSchema),
  deloadWeek: z.number().nullable().optional(),
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
