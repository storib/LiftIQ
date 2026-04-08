import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";
import {
  EXERCISE_SWAP_SYSTEM_PROMPT,
  EXERCISE_SWAP_PROMPT_VERSION,
} from "./prompts/exerciseSwap";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

export const suggestExerciseSwap = onCall(
  { secrets: [anthropicApiKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const { currentExercise, availableEquipment, otherExercisesInWorkout } =
      request.data;

    const db = admin.firestore();
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
          ex.equipment.every((eq: string) => availableEquipment.includes(eq))
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

      const suggestions = JSON.parse(content.text);

      // Resolve full exercise objects
      const result = [];
      for (const suggestion of suggestions) {
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
