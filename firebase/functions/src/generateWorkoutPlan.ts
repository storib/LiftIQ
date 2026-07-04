import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";
import {
  WORKOUT_GENERATION_SYSTEM_PROMPT,
  WORKOUT_GENERATION_PROMPT_VERSION,
} from "./prompts/workoutGeneration";
import {
  GenerateWorkoutPlanRequestSchema,
  WorkoutPlanSchema,
} from "./validators/schemas";
import { CLAUDE_MODEL, THINKING_DISABLED } from "./models";
import { assertWithinDailyQuota } from "./rateLimit";
import * as admin from "firebase-admin";
import { randomUUID } from "node:crypto";

if (!admin.apps.length) admin.initializeApp();

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

const MUSCLE_GROUPS = [
  "chest", "back", "shoulders", "biceps", "triceps", "forearms",
  "quads", "hamstrings", "glutes", "calves", "core",
  "traps", "lats", "rearDelts", "sideDelts", "frontDelts",
];

const SAVE_WORKOUT_PLAN_TOOL = {
  name: "save_workout_plan",
  description:
    "Save the complete workout plan. Call this tool exactly once with the full plan that satisfies the schema.",
  input_schema: {
    type: "object" as const,
    properties: {
      id: { type: "string" },
      userId: { type: "string" },
      name: { type: "string" },
      templateType: {
        type: "string",
        enum: ["ppl", "upperLower", "fullBody", "broSplit", "custom"],
      },
      goal: {
        type: "string",
        enum: ["strength", "hypertrophy", "endurance", "generalFitness"],
      },
      weekCount: { type: "integer", minimum: 1, maximum: 16 },
      currentWeek: { type: "integer", minimum: 1 },
      workoutsPerWeek: { type: "integer", minimum: 1, maximum: 7 },
      workouts: {
        type: "array",
        minItems: 1,
        items: {
          type: "object",
          properties: {
            id: { type: "string" },
            planId: { type: "string" },
            dayNumber: { type: "integer" },
            name: { type: "string" },
            targetMuscleGroups: {
              type: "array",
              items: { type: "string", enum: MUSCLE_GROUPS },
            },
            estimatedDurationMinutes: { type: "integer" },
            exerciseGroups: {
              type: "array",
              minItems: 1,
              items: {
                type: "object",
                properties: {
                  id: { type: "string" },
                  groupType: {
                    type: "string",
                    enum: ["straight", "superset", "triset", "circuit", "dropSet"],
                  },
                  exercises: {
                    type: "array",
                    minItems: 1,
                    items: {
                      type: "object",
                      properties: {
                        id: { type: "string" },
                        exerciseId: { type: "string" },
                        order: { type: "integer" },
                        sets: { type: "integer", minimum: 1, maximum: 10 },
                        repsMin: { type: "integer", minimum: 1, maximum: 50 },
                        repsMax: {
                          type: "integer",
                          minimum: 1,
                          maximum: 50,
                          description: "Must be >= repsMin",
                        },
                        rirTarget: { type: ["number", "null"] },
                        rpeTarget: { type: ["number", "null"] },
                        restSeconds: { type: "integer", minimum: 0, maximum: 600 },
                        warmUpSets: {
                          type: ["array", "null"],
                          items: {
                            type: "object",
                            properties: {
                              id: { type: "string" },
                              percentageOf1RM: { type: "number" },
                              reps: { type: "integer" },
                              label: { type: "string" },
                            },
                            required: ["id", "percentageOf1RM", "reps", "label"],
                          },
                        },
                        notes: { type: ["string", "null"] },
                        isOptional: { type: "boolean" },
                      },
                      required: [
                        "id", "exerciseId", "order", "sets",
                        "repsMin", "repsMax", "restSeconds", "isOptional",
                      ],
                    },
                  },
                  restBetweenRoundsSeconds: { type: ["number", "null"] },
                },
                required: ["id", "groupType", "exercises"],
              },
            },
            notes: { type: ["string", "null"] },
          },
          required: [
            "id", "planId", "dayNumber", "name", "targetMuscleGroups",
            "estimatedDurationMinutes", "exerciseGroups",
          ],
        },
      },
      deloadWeek: { type: ["number", "null"] },
      isActive: { type: "boolean" },
      createdAt: {
        type: "string",
        description: "ISO 8601 datetime string",
      },
      aiGenerated: { type: "boolean" },
      aiPromptContext: { type: ["string", "null"] },
    },
    required: [
      "id", "userId", "name", "templateType", "goal", "weekCount",
      "currentWeek", "workoutsPerWeek", "workouts", "isActive",
      "createdAt", "aiGenerated",
    ],
  },
};

type AttemptResult = {
  message: Anthropic.Message;
  toolInput: unknown;
  rawText: string;
};

export type PlanShapeResult =
  | { ok: true }
  | { ok: false; reason: string };

type ExerciseDoc = { id: string; equipment: unknown };

// Fields the system prompt actually needs for exercise selection: identity
// (id/name), muscle coverage (primary/secondary for volume + injury rules),
// equipment matching, push/pull balance (movementPattern), compound-first
// ordering (isCompound), and experience-level fit (difficulty). Everything
// else (instructions, tips, youtubeVideoId, tags, alternatives) is dropped
// before serialization to keep the prompt small.
export type PromptExercise = {
  id: string;
  name?: unknown;
  primaryMuscleGroup?: unknown;
  secondaryMuscleGroups?: unknown;
  equipment?: unknown;
  movementPattern?: unknown;
  difficulty?: unknown;
  isCompound?: unknown;
};

// Compact, byte-stable serialization of the exercise database for the prompt:
// projected to the selection-relevant fields with a fixed key order, sorted by
// id, and stringified without indentation. Determinism matters — the block
// lives inside a cache_control'd system block, and prompt caching is an exact
// prefix match, so the same equipment set must always serialize to the same
// bytes. Exported for unit tests.
export function serializeExercisesForPrompt(
  exercises: readonly PromptExercise[],
): string {
  const projected = [...exercises]
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0))
    .map((ex) => ({
      id: ex.id,
      name: ex.name,
      primaryMuscleGroup: ex.primaryMuscleGroup,
      secondaryMuscleGroups: ex.secondaryMuscleGroups,
      equipment: ex.equipment,
      movementPattern: ex.movementPattern,
      difficulty: ex.difficulty,
      isCompound: ex.isCompound,
    }));
  return JSON.stringify(projected);
}

// Returns the subset of exercises whose entire `equipment` array is contained
// in the user's `availableEquipment` set. Exported for unit tests; an empty
// result here drives the "no exercises match" precondition error.
export function filterExercisesByEquipment<T extends ExerciseDoc>(
  exercises: T[],
  availableEquipment: readonly string[],
): T[] {
  const set = new Set<string>(availableEquipment);
  return exercises.filter(
    (ex) =>
      Array.isArray(ex.equipment) &&
      ex.equipment.every(
        (eq: unknown) => typeof eq === "string" && set.has(eq),
      ),
  );
}

// Overwrites the identity fields the model is asked to leave as placeholders.
// The server — not the model or the client — is authoritative for the plan id,
// owner, timestamps, and workout back-references. Pure and exported for tests.
export function normalizePlan(
  plan: ReturnType<typeof WorkoutPlanSchema.parse>,
  userId: string,
): ReturnType<typeof WorkoutPlanSchema.parse> {
  const planId = randomUUID();
  return {
    ...plan,
    id: planId,
    userId,
    createdAt: new Date().toISOString(),
    workouts: plan.workouts.map((workout) => ({ ...workout, planId })),
  };
}

export function validatePlanShape(
  plan: ReturnType<typeof WorkoutPlanSchema.parse>,
  expectedWorkoutCount: number,
  stopReason: Anthropic.Message["stop_reason"],
): PlanShapeResult {
  if (stopReason === "max_tokens") {
    return { ok: false, reason: "Response truncated (stop_reason=max_tokens)" };
  }
  if (plan.workouts.length === 0) {
    return { ok: false, reason: "workouts array is empty" };
  }
  if (plan.workouts.length !== expectedWorkoutCount) {
    return {
      ok: false,
      reason: `workouts.length=${plan.workouts.length}, expected ${expectedWorkoutCount}`,
    };
  }
  for (const workout of plan.workouts) {
    const exerciseCount = workout.exerciseGroups.reduce(
      (sum, group) => sum + group.exercises.length,
      0,
    );
    if (exerciseCount === 0) {
      return {
        ok: false,
        reason: `workout "${workout.name}" (day ${workout.dayNumber}) has no exercises`,
      };
    }
  }
  return { ok: true };
}

async function generatePlanAttempt(
  client: Anthropic,
  system: Anthropic.TextBlockParam[],
  userPrompt: string,
): Promise<AttemptResult> {
  const message = await client.messages.create({
    model: CLAUDE_MODEL,
    max_tokens: 24000,
    thinking: THINKING_DISABLED,
    system,
    messages: [{ role: "user", content: userPrompt }],
    tools: [SAVE_WORKOUT_PLAN_TOOL],
    tool_choice: { type: "tool", name: SAVE_WORKOUT_PLAN_TOOL.name },
  });

  let firstToolInput: unknown = null;
  let toolUseCount = 0;
  const textParts: string[] = [];
  for (const block of message.content) {
    if (block.type === "tool_use" && block.name === SAVE_WORKOUT_PLAN_TOOL.name) {
      if (toolUseCount === 0) firstToolInput = block.input;
      toolUseCount++;
    } else if (block.type === "text") {
      textParts.push(block.text);
    }
  }

  // Forced tool_choice should yield exactly one matching call. Anything else
  // is treated as invalid so the retry/error path runs instead of silently
  // collapsing duplicate or missing calls.
  let toolInput: unknown = null;
  if (toolUseCount === 1) {
    toolInput = firstToolInput;
  } else {
    console.error("Unexpected save_workout_plan tool_use block count", {
      count: toolUseCount,
      stopReason: message.stop_reason,
    });
  }

  const rawText =
    toolInput !== null ? JSON.stringify(toolInput) : textParts.join("\n");

  return { message, toolInput, rawText };
}

export const generateWorkoutPlan = onCall(
  {
    secrets: [anthropicApiKey],
    maxInstances: 10,
    enforceAppCheck: true,
    timeoutSeconds: 180,
    memory: "512MiB",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const parsedRequest = GenerateWorkoutPlanRequestSchema.safeParse(request.data);
    if (!parsedRequest.success) {
      throw new HttpsError("invalid-argument", "Invalid workout plan request.");
    }

    const {
      experienceLevel,
      goals,
      availableEquipment,
      trainingDaysPerWeek,
      sessionDurationMinutes,
      injuries,
      templateType,
    } = parsedRequest.data;

    const db = admin.firestore();
    await assertWithinDailyQuota(db, request.auth.uid, "generateWorkoutPlan", 5);

    // Load exercise database
    const exercisesSnap = await db.collection("exercises").get();
    const exercises = exercisesSnap.docs.map((doc) => ({
      id: doc.id,
      name: doc.data().name,
      primaryMuscleGroup: doc.data().primaryMuscleGroup,
      secondaryMuscleGroups: doc.data().secondaryMuscleGroups,
      equipment: doc.data().equipment,
      movementPattern: doc.data().movementPattern,
      difficulty: doc.data().difficulty,
      isCompound: doc.data().isCompound,
    }));

    // Filter exercises by available equipment
    const availableExercises = filterExercisesByEquipment(exercises, availableEquipment);

    if (availableExercises.length === 0) {
      console.error("No exercises match user equipment; aborting before Claude call", {
        availableEquipment,
        totalExercisesInDb: exercises.length,
      });
      throw new HttpsError(
        "failed-precondition",
        "No exercises in the database match your selected equipment. Add equipment in your profile or contact support.",
      );
    }

    // Prompt caching: tools + system render before messages, so the stable
    // content (coaching system prompt + exercise database for this equipment
    // set) lives in system blocks with cache_control on the LAST stable block.
    // Retries within this request and other generations that share the same
    // equipment set hit the cache within the TTL. Nothing per-request
    // (timestamps, uid, injuries, template params) may appear in these blocks
    // — all of that stays in the user message below, after the cached prefix.
    const systemBlocks: Anthropic.TextBlockParam[] = [
      { type: "text", text: WORKOUT_GENERATION_SYSTEM_PROMPT },
      {
        type: "text",
        text: `## Exercise Database
Use ONLY exercise IDs from this database (JSON, sorted by id):
${serializeExercisesForPrompt(availableExercises)}`,
        cache_control: { type: "ephemeral" },
      },
    ];

    const userPrompt = `Create a ${templateType} workout plan with these parameters:
- Experience Level: ${experienceLevel}
- Goals: ${JSON.stringify(goals)}
- Available Equipment: ${JSON.stringify(availableEquipment)}
- Training Days Per Week: ${trainingDaysPerWeek}
- Session Duration: ${sessionDurationMinutes} minutes
- Injuries:
${
  (injuries && injuries.length > 0)
    ? injuries.map((inj: { bodyPart: string; severity: string; notes: string }) =>
        `  * ${inj.severity.toUpperCase()} — ${inj.bodyPart}${inj.notes ? ` (${inj.notes})` : ""}`
      ).join("\n")
    : "  None"
}

When the plan is finalized, call the save_workout_plan tool with the complete plan. Apply these defaults:
- templateType: "${templateType}"
- goal: "${goals[0] || "hypertrophy"}"
- weekCount: 6, currentWeek: 1, deloadWeek: 5
- workoutsPerWeek: ${trainingDaysPerWeek}
- workouts MUST contain exactly ${trainingDaysPerWeek} WorkoutTemplate objects (one per training day). Do not return an empty or partial workouts array.
- Each WorkoutTemplate MUST contain at least one exerciseGroup with at least one exercise.
- estimatedDurationMinutes per workout: ${sessionDurationMinutes}
- createdAt: "${new Date().toISOString()}"
- aiGenerated: true, isActive: true
- userId and planId can be empty strings; the server fills them in.
- Generate unique string ids (e.g. uuid v4) for the plan, each workout, each exerciseGroup, each exercise, and each warm-up set.
- repsMax must be >= repsMin.`;

    const maxAttempts = 2;
    const attempts: AttemptResult[] = [];
    const writeUsageLog = async (success: boolean) => {
      if (attempts.length === 0) return;
      const inputTokens = attempts.reduce(
        (sum, a) => sum + a.message.usage.input_tokens,
        0,
      );
      const outputTokens = attempts.reduce(
        (sum, a) => sum + a.message.usage.output_tokens,
        0,
      );
      // Prompt-cache observability: cache_creation = tokens written to the
      // cache (~1.25x cost), cache_read = tokens served from it (~0.1x cost).
      // If cacheReadInputTokens stays 0 across warm traffic, a silent cache
      // invalidator has crept into the system blocks.
      const cacheCreationInputTokens = attempts.reduce(
        (sum, a) => sum + (a.message.usage.cache_creation_input_tokens ?? 0),
        0,
      );
      const cacheReadInputTokens = attempts.reduce(
        (sum, a) => sum + (a.message.usage.cache_read_input_tokens ?? 0),
        0,
      );
      try {
        await db.collection("aiUsageLogs").add({
          userId: request.auth!.uid,
          function: "generateWorkoutPlan",
          promptVersion: WORKOUT_GENERATION_PROMPT_VERSION,
          inputTokens,
          outputTokens,
          cacheCreationInputTokens,
          cacheReadInputTokens,
          attempts: attempts.length,
          success,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (logError: any) {
        console.error("aiUsageLogs write failed", {
          message: logError?.message,
          success,
        });
      }
    };

    try {
      const client = new Anthropic({ apiKey: anthropicApiKey.value() });

      let plan: ReturnType<typeof WorkoutPlanSchema.parse> | null = null;

      for (let i = 0; i < maxAttempts; i++) {
        const attempt = await generatePlanAttempt(
          client,
          systemBlocks,
          userPrompt,
        );
        attempts.push(attempt);
        const parsed = WorkoutPlanSchema.safeParse(attempt.toolInput);
        if (!parsed.success) {
          console.error(
            `generateWorkoutPlan attempt ${i + 1}/${maxAttempts} failed validation`,
            {
              issues: parsed.error.issues,
              stopReason: attempt.message.stop_reason,
              rawText: attempt.rawText.slice(0, 4000),
            }
          );
          continue;
        }
        const shape = validatePlanShape(
          parsed.data,
          trainingDaysPerWeek,
          attempt.message.stop_reason,
        );
        if (!shape.ok) {
          console.error(
            `generateWorkoutPlan attempt ${i + 1}/${maxAttempts} shape invalid`,
            {
              reason: shape.reason,
              stopReason: attempt.message.stop_reason,
              rawText: attempt.rawText.slice(0, 4000),
            }
          );
          continue;
        }
        plan = parsed.data;
        break;
      }

      if (!plan) {
        throw new HttpsError(
          "internal",
          "AI returned a workout plan that did not match the expected schema."
        );
      }

      const availableExerciseIds = new Set(availableExercises.map((ex) => ex.id));
      const invalidExerciseIds = plan.workouts.flatMap((workout) =>
        workout.exerciseGroups.flatMap((group) =>
          group.exercises
            .map((exercise) => exercise.exerciseId)
            .filter((exerciseId) => !availableExerciseIds.has(exerciseId))
        )
      );

      if (invalidExerciseIds.length > 0) {
        throw new HttpsError(
          "internal",
          "AI returned exercises outside the allowed exercise database."
        );
      }

      // Validate severe injuries: ensure no exercises target the injured area
      if (injuries && injuries.length > 0) {
        const severeInjuries = injuries.filter(
          (inj: { severity: string }) => inj.severity.toLowerCase() === "severe"
        );
        if (severeInjuries.length > 0) {
          const injuryMuscleMap: Record<string, string[]> = {
            "shoulder": ["shoulders", "frontDelts", "sideDelts", "rearDelts"],
            "left shoulder": ["shoulders", "frontDelts", "sideDelts", "rearDelts"],
            "right shoulder": ["shoulders", "frontDelts", "sideDelts", "rearDelts"],
            "knee": ["quads", "hamstrings", "glutes", "calves"],
            "left knee": ["quads", "hamstrings", "glutes", "calves"],
            "right knee": ["quads", "hamstrings", "glutes", "calves"],
            "lower back": ["back", "lats", "core"],
            "back": ["back", "lats", "traps"],
            "upper back": ["back", "lats", "traps"],
            "wrist": ["forearms", "biceps"],
            "left wrist": ["forearms", "biceps"],
            "right wrist": ["forearms", "biceps"],
            "elbow": ["biceps", "triceps", "forearms"],
            "left elbow": ["biceps", "triceps", "forearms"],
            "right elbow": ["biceps", "triceps", "forearms"],
            "hip": ["glutes", "hamstrings", "quads"],
            "left hip": ["glutes", "hamstrings", "quads"],
            "right hip": ["glutes", "hamstrings", "quads"],
            "ankle": ["calves"],
            "left ankle": ["calves"],
            "right ankle": ["calves"],
            "neck": ["traps"],
            "chest": ["chest"],
          };

          const blockedMuscles = new Set<string>();
          for (const inj of severeInjuries) {
            const key = (inj as { bodyPart: string }).bodyPart.toLowerCase().trim();
            const mapped = injuryMuscleMap[key];
            if (mapped) {
              mapped.forEach((m: string) => blockedMuscles.add(m));
            }
          }

          if (blockedMuscles.size > 0) {
            const exerciseIdToMuscle = new Map<string, string>(
              exercises.map((ex) => [ex.id, ex.primaryMuscleGroup])
            );

            const violations = plan.workouts.flatMap((workout) =>
              workout.exerciseGroups.flatMap((group) =>
                group.exercises
                  .filter((exercise) => {
                    const muscle = exerciseIdToMuscle.get(exercise.exerciseId);
                    return muscle && blockedMuscles.has(muscle);
                  })
                  .map((exercise) => exercise.exerciseId)
              )
            );

            if (violations.length > 0) {
              // Log the violation but don't block — the AI prompt should handle it,
              // and we don't want to fail the entire generation for edge cases.
              console.warn(
                `Injury safety warning: plan includes ${violations.length} exercise(s) ` +
                `targeting severely injured areas: ${violations.join(", ")}. ` +
                `Blocked muscles: ${[...blockedMuscles].join(", ")}`
              );
            }
          }
        }
      }

      // Server-authoritative identity fields: fresh plan id, owner uid,
      // creation timestamp, and matching planId on every embedded workout.
      const normalizedPlan = normalizePlan(plan, request.auth.uid);

      await writeUsageLog(true);

      return normalizedPlan;
    } catch (error: any) {
      console.error("generateWorkoutPlan failed", {
        name: error?.name,
        message: error?.message,
        status: error?.status,
        stack: error?.stack,
      });
      await writeUsageLog(false);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", "Plan generation failed");
    }
  }
);
