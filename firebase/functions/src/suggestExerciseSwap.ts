import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";
import {
  EXERCISE_SWAP_SYSTEM_PROMPT,
  EXERCISE_SWAP_PROMPT_VERSION,
} from "./prompts/exerciseSwap";
import {
  ExerciseSwapRequestSchema,
  ExerciseSwapSuggestionSchema,
} from "./validators/schemas";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

export const suggestExerciseSwap = onCall(
  { secrets: [anthropicApiKey], enforceAppCheck: true },
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
      .map((doc) => ({ id: doc.id, ...doc.data() }))
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

    const userPrompt = `Current exercise: ${currentExercise.name} (${currentExercise.primaryMuscle}, ${currentExercise.movementPattern})

Other exercises already in this workout: ${JSON.stringify(otherExercisesInWorkout)}

Available alternatives:
${JSON.stringify(candidates, null, 2)}

Suggest the best 3-5 replacements.`;

    try {
      const client = new Anthropic({ apiKey: anthropicApiKey.value() });

      const message = await client.messages.create({
        model: "claude-sonnet-4-20250514",
        max_tokens: 2000,
        system: EXERCISE_SWAP_SYSTEM_PROMPT,
        messages: [{ role: "user", content: userPrompt }],
      });

      const content = message.content[0];
      if (content.type !== "text") {
        throw new HttpsError("internal", "Unexpected response type");
      }

      const rawSuggestions = JSON.parse(content.text);
      const parsedSuggestions = ExerciseSwapSuggestionSchema.array()
        .min(1)
        .max(5)
        .safeParse(rawSuggestions);
      if (!parsedSuggestions.success) {
        throw new HttpsError(
          "internal",
          "AI returned exercise swaps that did not match the expected schema."
        );
      }

      // Resolve full exercise objects
      const candidateIds = new Set(candidates.map((ex: any) => ex.id));
      const result = [];
      for (const suggestion of parsedSuggestions.data) {
        if (!candidateIds.has(suggestion.exerciseId)) continue;
        const exDoc = await db
          .collection("exercises")
          .doc(suggestion.exerciseId)
          .get();
        if (exDoc.exists) {
          result.push({ ...exDoc.data(), id: exDoc.id });
        }
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
      throw new HttpsError("internal", error.message || "Swap failed");
    }
  }
);
