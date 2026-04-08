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

export const GroupTypeSchema = z.enum([
  "straight", "superset", "triset", "circuit", "dropSet",
]);

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
  templateType: z.enum(["ppl", "upperLower", "fullBody", "broSplit", "custom"]),
  goal: z.enum(["strength", "hypertrophy", "endurance", "generalFitness"]),
  weekCount: z.number().min(1).max(16),
  currentWeek: z.number().min(1),
  workoutsPerWeek: z.number().min(2).max(7),
  workouts: z.array(WorkoutTemplateSchema),
  deloadWeek: z.number().nullable().optional(),
  isActive: z.boolean(),
  createdAt: z.string(),
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
