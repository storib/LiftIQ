import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";
import {
  WEEKLY_INSIGHTS_SYSTEM_PROMPT,
  WEEKLY_INSIGHTS_PROMPT_VERSION,
} from "./prompts/weeklyInsights";
import {
  WeeklyInsightsRequestSchema,
  WeeklyInsightsSchema,
} from "./validators/schemas";
import { CLAUDE_MODEL_SMALL } from "./models";
import { assertWithinDailyQuota } from "./rateLimit";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

type WeeklyInsightsRequest = ReturnType<typeof WeeklyInsightsRequestSchema.parse>;

// Forced tool use, mirroring analyzePlateau: the model must return
// structured input for this tool, so there is no raw-text JSON path to
// break on preamble or truncated prose.
const SAVE_WEEKLY_INSIGHTS_TOOL = {
  name: "save_weekly_insights",
  description:
    "Save the weekly check-in. Call this tool exactly once with the complete check-in.",
  input_schema: {
    type: "object" as const,
    properties: {
      insights: {
        type: "array",
        items: { type: "string" },
        minItems: 3,
        maxItems: 5,
        description: "3-5 short observations about last week, best news first.",
      },
      actionItem: {
        type: "string",
        description: "One concrete, small thing to do next week.",
      },
      overallRating: { type: "string", enum: ["great", "good", "needsAttention"] },
    },
    required: ["insights", "actionItem", "overallRating"],
  },
};

function describeWeek(label: string, week: WeeklyInsightsRequest["lastWeek"], unit: string): string {
  const lines = [
    `${label} (week of ${week.weekStart}):`,
    `- Sessions completed: ${week.sessionsCompleted}`,
    `- Distinct training days: ${week.distinctDays}`,
    `- Total volume: ${Math.round(week.totalVolume)} ${unit}`,
    `- Personal records: ${week.prCount}`,
  ];
  if (week.averageDifficulty != null) {
    lines.push(`- Average difficulty (1 easy - 5 brutal): ${week.averageDifficulty.toFixed(1)}`);
  }
  return lines.join("\n");
}

export function buildWeeklyInsightsUserPrompt(request: WeeklyInsightsRequest): string {
  const unit = request.weightUnit;
  const parts: string[] = [];
  const profile: string[] = [];
  if (request.plannedSessionsPerWeek != null) profile.push(`planned sessions per week: ${request.plannedSessionsPerWeek}`);
  if (request.goal) profile.push(`goal: ${request.goal}`);
  if (request.experienceLevel) profile.push(`experience: ${request.experienceLevel}`);
  if (profile.length > 0) parts.push(`Lifter: ${profile.join(", ")}.`);

  parts.push(describeWeek("Last week", request.lastWeek, unit));
  if (request.priorWeek) {
    parts.push(describeWeek("The week before", request.priorWeek, unit));
  } else {
    parts.push("The week before: no completed sessions.");
  }

  if (request.lifts.length > 0) {
    const liftLines = request.lifts.map((lift) => {
      const last = `${lift.lastWeek.weight} ${unit} x ${lift.lastWeek.reps}`;
      const prior = lift.priorWeek
        ? `${lift.priorWeek.weight} ${unit} x ${lift.priorWeek.reps}`
        : "not trained";
      return `- ${lift.name}: last week ${last}; week before ${prior}`;
    });
    parts.push(`Best working set per lift:\n${liftLines.join("\n")}`);
  }

  parts.push("Write the check-in, then call the save_weekly_insights tool.");
  return parts.join("\n\n");
}

export const generateWeeklyInsights = onCall(
  { secrets: [anthropicApiKey], maxInstances: 5, enforceAppCheck: true },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const parsedRequest = WeeklyInsightsRequestSchema.safeParse(request.data);
    if (!parsedRequest.success) {
      throw new HttpsError("invalid-argument", "Invalid weekly insights request.");
    }

    const db = admin.firestore();
    await assertWithinDailyQuota(db, request.auth.uid, "generateWeeklyInsights", 7);

    const userPrompt = buildWeeklyInsightsUserPrompt(parsedRequest.data);

    try {
      const client = new Anthropic({ apiKey: anthropicApiKey.value() });

      // Haiku call: no `thinking` parameter at all.
      const message = await client.messages.create({
        model: CLAUDE_MODEL_SMALL,
        max_tokens: 1200,
        system: WEEKLY_INSIGHTS_SYSTEM_PROMPT,
        messages: [{ role: "user", content: userPrompt }],
        tools: [SAVE_WEEKLY_INSIGHTS_TOOL],
        tool_choice: { type: "tool", name: SAVE_WEEKLY_INSIGHTS_TOOL.name },
      });

      const toolBlock = message.content.find(
        (block): block is Anthropic.ToolUseBlock =>
          block.type === "tool_use" &&
          block.name === SAVE_WEEKLY_INSIGHTS_TOOL.name,
      );
      if (!toolBlock) {
        console.error("generateWeeklyInsights: no save_weekly_insights tool_use block", {
          stopReason: message.stop_reason,
        });
        throw new HttpsError("internal", "Unexpected response type");
      }

      const parsed = WeeklyInsightsSchema.safeParse(toolBlock.input);
      if (!parsed.success) {
        console.error("generateWeeklyInsights: response failed validation", {
          issues: parsed.error.issues,
        });
        throw new HttpsError(
          "internal",
          "AI returned a check-in that did not match the expected schema.",
        );
      }

      await db.collection("aiUsageLogs").add({
        userId: request.auth.uid,
        function: "generateWeeklyInsights",
        promptVersion: WEEKLY_INSIGHTS_PROMPT_VERSION,
        inputTokens: message.usage.input_tokens,
        outputTokens: message.usage.output_tokens,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return parsed.data;
    } catch (error: any) {
      if (error instanceof HttpsError) throw error;
      console.error("generateWeeklyInsights failed", {
        name: error?.name,
        message: error?.message,
        status: error?.status,
      });
      throw new HttpsError("internal", "Weekly check-in failed");
    }
  }
);
