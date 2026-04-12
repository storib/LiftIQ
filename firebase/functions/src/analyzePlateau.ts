import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";
import {
  PLATEAU_ANALYSIS_SYSTEM_PROMPT,
  PLATEAU_ANALYSIS_PROMPT_VERSION,
} from "./prompts/plateauAnalysis";
import {
  PlateauAnalysisRequestSchema,
  PlateauAnalysisSchema,
} from "./validators/schemas";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

export const analyzePlateau = onCall(
  { secrets: [anthropicApiKey], enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const parsedRequest = PlateauAnalysisRequestSchema.safeParse(request.data);
    if (!parsedRequest.success) {
      throw new HttpsError("invalid-argument", "Invalid plateau analysis request.");
    }

    const { exercise, history, userProfile, currentProgramWeek } =
      parsedRequest.data;

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

      const rawAnalysis = JSON.parse(content.text);
      const parsedAnalysis = PlateauAnalysisSchema.safeParse(rawAnalysis);
      if (!parsedAnalysis.success) {
        throw new HttpsError(
          "internal",
          "AI returned plateau analysis that did not match the expected schema."
        );
      }

      const db = admin.firestore();
      await db.collection("aiUsageLogs").add({
        userId: request.auth.uid,
        function: "analyzePlateau",
        promptVersion: PLATEAU_ANALYSIS_PROMPT_VERSION,
        inputTokens: message.usage.input_tokens,
        outputTokens: message.usage.output_tokens,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return parsedAnalysis.data;
    } catch (error: any) {
      throw new HttpsError("internal", error.message || "Analysis failed");
    }
  }
);
