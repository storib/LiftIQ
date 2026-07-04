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
import { CLAUDE_MODEL_SMALL } from "./models";
import { assertWithinDailyQuota } from "./rateLimit";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

// Forced tool use (tool_choice type:"tool") mirrors generateWorkoutPlan: the
// model must return structured input for this tool, so there is no raw-text
// JSON.parse path to break on preamble or truncated prose.
const SAVE_PLATEAU_ANALYSIS_TOOL = {
  name: "save_plateau_analysis",
  description:
    "Save the plateau analysis result. Call this tool exactly once with the complete analysis.",
  input_schema: {
    type: "object" as const,
    properties: {
      isPlateaued: { type: "boolean" },
      confidence: { type: "string", enum: ["high", "medium", "low"] },
      analysis: {
        type: "string",
        description: "Explanation of the findings",
      },
      recommendation: {
        type: "string",
        enum: ["deload", "swap", "repSchemeChange", "volumeAdjust", "techniqueFocus"],
      },
      details: {
        type: "string",
        description: "Specific programming changes",
      },
    },
    required: [
      "isPlateaued", "confidence", "analysis", "recommendation", "details",
    ],
  },
};

export const analyzePlateau = onCall(
  { secrets: [anthropicApiKey], maxInstances: 5, enforceAppCheck: true },
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

    const db = admin.firestore();
    await assertWithinDailyQuota(db, request.auth.uid, "analyzePlateau", 20);

    const userPrompt = `Analyze this exercise performance data:

Exercise: ${exercise}
Current program week: ${currentProgramWeek}
User profile: ${JSON.stringify(userProfile)}

Performance history (most recent first):
${JSON.stringify(history)}

Determine if the user has plateaued and recommend adjustments, then call the save_plateau_analysis tool.`;

    try {
      const client = new Anthropic({ apiKey: anthropicApiKey.value() });

      // Haiku call: no `thinking` parameter at all.
      const message = await client.messages.create({
        model: CLAUDE_MODEL_SMALL,
        max_tokens: 2000,
        system: PLATEAU_ANALYSIS_SYSTEM_PROMPT,
        messages: [{ role: "user", content: userPrompt }],
        tools: [SAVE_PLATEAU_ANALYSIS_TOOL],
        tool_choice: { type: "tool", name: SAVE_PLATEAU_ANALYSIS_TOOL.name },
      });

      const toolBlock = message.content.find(
        (block): block is Anthropic.ToolUseBlock =>
          block.type === "tool_use" &&
          block.name === SAVE_PLATEAU_ANALYSIS_TOOL.name,
      );
      if (!toolBlock) {
        console.error("analyzePlateau: no save_plateau_analysis tool_use block", {
          stopReason: message.stop_reason,
        });
        throw new HttpsError("internal", "Unexpected response type");
      }

      const parsedAnalysis = PlateauAnalysisSchema.safeParse(toolBlock.input);
      if (!parsedAnalysis.success) {
        throw new HttpsError(
          "internal",
          "AI returned plateau analysis that did not match the expected schema."
        );
      }

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
      if (error instanceof HttpsError) throw error;
      console.error("analyzePlateau failed", {
        name: error?.name,
        message: error?.message,
        status: error?.status,
      });
      throw new HttpsError("internal", "Analysis failed");
    }
  }
);
