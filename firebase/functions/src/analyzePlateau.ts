import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";
import {
  PLATEAU_ANALYSIS_SYSTEM_PROMPT,
  PLATEAU_ANALYSIS_PROMPT_VERSION,
} from "./prompts/plateauAnalysis";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

export const analyzePlateau = onCall(
  { secrets: [anthropicApiKey] },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const { exercise, history, userProfile, currentProgramWeek } = request.data;

    const userPrompt = `Analyze this exercise performance data:

Exercise: ${exercise}
Current program week: ${currentProgramWeek}
User profile: ${JSON.stringify(userProfile)}

Performance history (most recent first):
${JSON.stringify(history, null, 2)}

Determine if the user has plateaued and recommend adjustments.`;

    try {
      const client = new Anthropic({ apiKey: anthropicApiKey.value() });

      const message = await client.messages.create({
        model: "claude-sonnet-4-20250514",
        max_tokens: 1500,
        system: PLATEAU_ANALYSIS_SYSTEM_PROMPT,
        messages: [{ role: "user", content: userPrompt }],
      });

      const content = message.content[0];
      if (content.type !== "text") {
        throw new HttpsError("internal", "Unexpected response type");
      }

      const analysis = JSON.parse(content.text);

      const db = admin.firestore();
      await db.collection("aiUsageLogs").add({
        userId: request.auth.uid,
        function: "analyzePlateau",
        promptVersion: PLATEAU_ANALYSIS_PROMPT_VERSION,
        inputTokens: message.usage.input_tokens,
        outputTokens: message.usage.output_tokens,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return analysis;
    } catch (error: any) {
      throw new HttpsError("internal", error.message || "Analysis failed");
    }
  }
);
