import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";
import {
  WORKOUT_MODIFICATION_SYSTEM_PROMPT,
  WORKOUT_MODIFICATION_PROMPT_VERSION,
} from "./prompts/workoutModification";
import {
  ModifyWorkoutRequestSchema,
  ModifiedPlanResponseSchema,
  ModifiedWorkoutResponseSchema,
  WorkoutPlanSchema,
  WorkoutTemplateSchema,
} from "./validators/schemas";
import {
  SAVE_WORKOUT_PLAN_TOOL,
  serializeExercisesForPrompt,
  filterExercisesByEquipment,
} from "./generateWorkoutPlan";
import { CLAUDE_MODEL, THINKING_DISABLED } from "./models";
import { assertWithinDailyQuota } from "./rateLimit";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// The plan/workout shapes come from the generation tool so the two functions
// can never drift apart.
const PLAN_INPUT_SCHEMA = SAVE_WORKOUT_PLAN_TOOL.input_schema;
const WORKOUT_INPUT_SCHEMA = (
  PLAN_INPUT_SCHEMA.properties.workouts as { items: object }
).items;

const CHANGE_SUMMARY_SCHEMA = {
  type: "string",
  description:
    "1-3 plain sentences, addressed to the user, describing what changed and why.",
};

const SAVE_MODIFIED_PLAN_TOOL = {
  name: "save_modified_plan",
  description:
    "Save the complete modified workout plan. Call exactly once with every workout, including unchanged ones.",
  input_schema: {
    type: "object" as const,
    properties: {
      changeSummary: CHANGE_SUMMARY_SCHEMA,
      plan: PLAN_INPUT_SCHEMA,
    },
    required: ["changeSummary", "plan"],
  },
};

const SAVE_MODIFIED_WORKOUT_TOOL = {
  name: "save_modified_workout",
  description:
    "Save the single modified workout. Call exactly once with the complete workout.",
  input_schema: {
    type: "object" as const,
    properties: {
      changeSummary: CHANGE_SUMMARY_SCHEMA,
      workout: WORKOUT_INPUT_SCHEMA,
    },
    required: ["changeSummary", "workout"],
  },
};

type Plan = ReturnType<typeof WorkoutPlanSchema.parse>;
type Workout = ReturnType<typeof WorkoutTemplateSchema.parse>;

// The server — not the model — is authoritative for identity fields. A
// modification keeps the original plan's identity (same document, same
// creation time, same activation state); only content comes from the model.
// Pure and exported for tests.
export function normalizeModifiedPlan(original: Plan, modified: Plan, userId: string): Plan {
  return {
    ...modified,
    id: original.id,
    userId,
    createdAt: original.createdAt,
    isActive: original.isActive,
    aiGenerated: true,
    workouts: modified.workouts.map((workout) => ({
      ...workout,
      planId: original.id,
    })),
  };
}

// A one-session modification keeps the original day's identity so history and
// rotation recommendations still map the session back to the plan's day.
export function normalizeModifiedWorkout(original: Workout, modified: Workout): Workout {
  return {
    ...modified,
    id: original.id,
    planId: original.planId,
    dayNumber: original.dayNumber,
  };
}

// Every exerciseId in the returned content must exist in the equipment-filtered
// database. Exported for tests.
export function collectInvalidExerciseIds(
  workouts: readonly Workout[],
  allowedIds: ReadonlySet<string>,
): string[] {
  return workouts.flatMap((workout) =>
    workout.exerciseGroups.flatMap((group) =>
      group.exercises
        .map((exercise) => exercise.exerciseId)
        .filter((exerciseId) => !allowedIds.has(exerciseId)),
    ),
  );
}

export const modifyWorkout = onCall(
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

    const parsedRequest = ModifyWorkoutRequestSchema.safeParse(request.data);
    if (!parsedRequest.success) {
      throw new HttpsError("invalid-argument", "Invalid workout modification request.");
    }

    const {
      scope,
      instruction,
      plan,
      workout,
      availableEquipment,
      injuries,
      experienceLevel,
    } = parsedRequest.data;

    const db = admin.firestore();
    await assertWithinDailyQuota(db, request.auth.uid, "modifyWorkout", 10);

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
    const availableExercises = filterExercisesByEquipment(exercises, availableEquipment);
    if (availableExercises.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "No exercises in the database match your selected equipment.",
      );
    }

    // Same caching layout as generateWorkoutPlan: stable coaching prompt +
    // exercise DB in system blocks with cache_control on the last stable
    // block; everything per-request stays in the user message.
    const systemBlocks: Anthropic.TextBlockParam[] = [
      { type: "text", text: WORKOUT_MODIFICATION_SYSTEM_PROMPT },
      {
        type: "text",
        text: `## Exercise Database
Use ONLY exercise IDs from this database (JSON, sorted by id):
${serializeExercisesForPrompt(availableExercises)}`,
        cache_control: { type: "ephemeral" },
      },
    ];

    const injuryLines =
      injuries.length > 0
        ? injuries
            .map(
              (inj) =>
                `  * ${inj.severity.toUpperCase()} — ${inj.bodyPart}${inj.notes ? ` (${inj.notes})` : ""}`,
            )
            .join("\n")
        : "  None";

    const subject =
      scope === "plan"
        ? `## Current Plan (modify per the request; scope: plan)
${JSON.stringify(plan)}`
        : `## Workout To Modify (one-off change for a single session; scope: workout)
${JSON.stringify(workout)}${plan ? `

## Full Plan (context only — do not return it)
${JSON.stringify(plan)}` : ""}`;

    const tool = scope === "plan" ? SAVE_MODIFIED_PLAN_TOOL : SAVE_MODIFIED_WORKOUT_TOOL;

    const userPrompt = `${subject}

## User Profile
- Experience Level: ${experienceLevel}
- Available Equipment: ${JSON.stringify(availableEquipment)}
- Listed Injuries / Limitations:
${injuryLines}

## Modification Request
${instruction}

Apply the request and call the ${tool.name} tool exactly once.`;

    const attempts: Anthropic.Message[] = [];
    const writeUsageLog = async (success: boolean) => {
      if (attempts.length === 0) return;
      const sum = (pick: (u: Anthropic.Usage) => number | null | undefined) =>
        attempts.reduce((total, a) => total + (pick(a.usage) ?? 0), 0);
      try {
        await db.collection("aiUsageLogs").add({
          userId: request.auth!.uid,
          function: "modifyWorkout",
          promptVersion: WORKOUT_MODIFICATION_PROMPT_VERSION,
          inputTokens: sum((u) => u.input_tokens),
          outputTokens: sum((u) => u.output_tokens),
          cacheCreationInputTokens: sum((u) => u.cache_creation_input_tokens),
          cacheReadInputTokens: sum((u) => u.cache_read_input_tokens),
          attempts: attempts.length,
          success,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      } catch (logError: any) {
        console.error("aiUsageLogs write failed", { message: logError?.message, success });
      }
    };

    try {
      const client = new Anthropic({ apiKey: anthropicApiKey.value() });
      const maxAttempts = 2;
      const allowedIds = new Set(availableExercises.map((ex) => ex.id));

      for (let i = 0; i < maxAttempts; i++) {
        const message = await client.messages.create({
          model: CLAUDE_MODEL,
          max_tokens: 24000,
          thinking: THINKING_DISABLED,
          system: systemBlocks,
          messages: [{ role: "user", content: userPrompt }],
          tools: [tool],
          tool_choice: { type: "tool", name: tool.name },
        });
        attempts.push(message);

        const toolBlocks = message.content.filter(
          (block): block is Anthropic.ToolUseBlock =>
            block.type === "tool_use" && block.name === tool.name,
        );
        if (toolBlocks.length !== 1 || message.stop_reason === "max_tokens") {
          console.error(`modifyWorkout attempt ${i + 1}/${maxAttempts} malformed`, {
            toolUseCount: toolBlocks.length,
            stopReason: message.stop_reason,
          });
          continue;
        }

        if (scope === "plan") {
          const parsed = ModifiedPlanResponseSchema.safeParse(toolBlocks[0].input);
          if (!parsed.success) {
            console.error(`modifyWorkout attempt ${i + 1}/${maxAttempts} failed validation`, {
              issues: parsed.error.issues,
            });
            continue;
          }
          const invalid = collectInvalidExerciseIds(parsed.data.plan.workouts, allowedIds);
          if (invalid.length > 0) {
            console.error(`modifyWorkout attempt ${i + 1}/${maxAttempts} used unknown exercises`, {
              invalid,
            });
            continue;
          }
          const normalized = normalizeModifiedPlan(plan!, parsed.data.plan, request.auth.uid);
          await writeUsageLog(true);
          return { scope, changeSummary: parsed.data.changeSummary, plan: normalized };
        } else {
          const parsed = ModifiedWorkoutResponseSchema.safeParse(toolBlocks[0].input);
          if (!parsed.success) {
            console.error(`modifyWorkout attempt ${i + 1}/${maxAttempts} failed validation`, {
              issues: parsed.error.issues,
            });
            continue;
          }
          const invalid = collectInvalidExerciseIds([parsed.data.workout], allowedIds);
          if (invalid.length > 0) {
            console.error(`modifyWorkout attempt ${i + 1}/${maxAttempts} used unknown exercises`, {
              invalid,
            });
            continue;
          }
          const normalized = normalizeModifiedWorkout(workout!, parsed.data.workout);
          await writeUsageLog(true);
          return { scope, changeSummary: parsed.data.changeSummary, workout: normalized };
        }
      }

      throw new HttpsError(
        "internal",
        "AI returned a modification that did not match the expected schema.",
      );
    } catch (error: any) {
      console.error("modifyWorkout failed", {
        name: error?.name,
        message: error?.message,
        status: error?.status,
      });
      await writeUsageLog(false);
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("internal", "Workout modification failed");
    }
  },
);
