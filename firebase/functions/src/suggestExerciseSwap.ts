import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";
import {
  EXERCISE_SWAP_SYSTEM_PROMPT,
  EXERCISE_SWAP_PROMPT_VERSION,
} from "./prompts/exerciseSwap";
import {
  ExerciseSwapRequestSchema,
  ExerciseSwapResponseSchema,
} from "./validators/schemas";
import { CLAUDE_MODEL_SMALL } from "./models";
import { assertWithinDailyQuota } from "./rateLimit";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// Forced tool use (tool_choice type:"tool") mirrors generateWorkoutPlan: the
// model must return structured input for this tool, so there is no raw-text
// JSON.parse path to break on preamble or truncated prose.
const SAVE_EXERCISE_SWAPS_TOOL = {
  name: "save_exercise_swaps",
  description:
    "Save the ranked exercise swap suggestions. Call this tool exactly once with 3-5 suggestions ordered from most to least recommended.",
  input_schema: {
    type: "object" as const,
    properties: {
      suggestions: {
        type: "array",
        minItems: 1,
        maxItems: 5,
        items: {
          type: "object",
          properties: {
            exerciseId: {
              type: "string",
              description: "ID of the suggested exercise, from the provided candidates",
            },
            rationale: {
              type: "string",
              description: "One-sentence rationale for the suggestion",
            },
          },
          required: ["exerciseId", "rationale"],
        },
      },
    },
    required: ["suggestions"],
  },
};

export const suggestExerciseSwap = onCall(
  { secrets: [anthropicApiKey], maxInstances: 5, enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const parsedRequest = ExerciseSwapRequestSchema.safeParse(request.data);
    if (!parsedRequest.success) {
      throw new HttpsError("invalid-argument", "Invalid exercise swap request.");
    }

    const { currentExercise, availableEquipment, otherExercisesInWorkout } =
      parsedRequest.data;

    const db = admin.firestore();
    await assertWithinDailyQuota(db, request.auth.uid, "suggestExerciseSwap", 20);

    const availableEquipmentSet = new Set<string>(availableEquipment);
    const exercisesSnap = await db
      .collection("exercises")
      .where(
        "primaryMuscleGroup",
        "==",
        currentExercise.primaryMuscle
      )
      .get();

    const candidates = exercisesSnap.docs
      .map((doc) => ({ ...doc.data(), id: doc.id }))
      .filter(
        (ex: any) =>
          ex.id !== currentExercise.id &&
          !otherExercisesInWorkout.includes(ex.id) &&
          Array.isArray(ex.equipment) &&
          ex.equipment.every(
            (eq: unknown) =>
              typeof eq === "string" && availableEquipmentSet.has(eq)
          )
      );

    if (candidates.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "No alternative exercises match your equipment for this muscle group.",
      );
    }

    // Slim projection keeps the prompt small; the full docs stay in
    // `candidates` for resolving the suggestions without re-reading Firestore.
    const promptCandidates = candidates.map((ex: any) => ({
      id: ex.id,
      name: ex.name,
      equipment: ex.equipment,
      movementPattern: ex.movementPattern,
      isCompound: ex.isCompound,
    }));

    const userPrompt = `Current exercise: ${currentExercise.name} (${currentExercise.primaryMuscle}, ${currentExercise.movementPattern})

Other exercises already in this workout: ${JSON.stringify(otherExercisesInWorkout)}

Available alternatives:
${JSON.stringify(promptCandidates)}

Choose the best 3-5 replacements and call the save_exercise_swaps tool.`;

    try {
      const client = new Anthropic({ apiKey: anthropicApiKey.value() });

      // Haiku call: no `thinking` parameter at all.
      const message = await client.messages.create({
        model: CLAUDE_MODEL_SMALL,
        max_tokens: 3000,
        system: EXERCISE_SWAP_SYSTEM_PROMPT,
        messages: [{ role: "user", content: userPrompt }],
        tools: [SAVE_EXERCISE_SWAPS_TOOL],
        tool_choice: { type: "tool", name: SAVE_EXERCISE_SWAPS_TOOL.name },
      });

      const toolBlock = message.content.find(
        (block): block is Anthropic.ToolUseBlock =>
          block.type === "tool_use" &&
          block.name === SAVE_EXERCISE_SWAPS_TOOL.name,
      );
      if (!toolBlock) {
        console.error("suggestExerciseSwap: no save_exercise_swaps tool_use block", {
          stopReason: message.stop_reason,
        });
        throw new HttpsError("internal", "Unexpected response type");
      }

      const parsedSuggestions = ExerciseSwapResponseSchema.safeParse(
        toolBlock.input,
      );
      if (!parsedSuggestions.success) {
        throw new HttpsError(
          "internal",
          "AI returned exercise swaps that did not match the expected schema."
        );
      }

      // Resolve suggestions from the in-memory candidates (already the full
      // Firestore docs) instead of re-fetching each one.
      const candidatesById = new Map<string, any>(
        candidates.map((ex: any) => [ex.id, ex]),
      );
      const result = [];
      for (const suggestion of parsedSuggestions.data.suggestions) {
        const candidate = candidatesById.get(suggestion.exerciseId);
        if (candidate) result.push(candidate);
      }

      await db.collection("aiUsageLogs").add({
        userId: request.auth.uid,
        function: "suggestExerciseSwap",
        promptVersion: EXERCISE_SWAP_PROMPT_VERSION,
        inputTokens: message.usage.input_tokens,
        outputTokens: message.usage.output_tokens,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return result;
    } catch (error: any) {
      if (error instanceof HttpsError) throw error;
      console.error("suggestExerciseSwap failed", {
        name: error?.name,
        message: error?.message,
        status: error?.status,
      });
      throw new HttpsError("internal", "Swap failed");
    }
  }
);
