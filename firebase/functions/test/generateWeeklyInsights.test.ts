import { describe, it, expect } from "vitest";
import { buildWeeklyInsightsUserPrompt } from "../src/generateWeeklyInsights";
import { WeeklyInsightsRequestSchema } from "../src/validators/schemas";

const request = WeeklyInsightsRequestSchema.parse({
  weightUnit: "lb",
  plannedSessionsPerWeek: 4,
  goal: "strength",
  experienceLevel: "intermediate",
  lastWeek: {
    weekStart: "2026-08-31",
    sessionsCompleted: 3,
    totalVolume: 24500.4,
    distinctDays: 3,
    prCount: 1,
    averageDifficulty: 3.67,
  },
  priorWeek: {
    weekStart: "2026-08-24",
    sessionsCompleted: 4,
    totalVolume: 26000,
    distinctDays: 4,
    prCount: 0,
    averageDifficulty: null,
  },
  lifts: [
    { name: "Bench Press", lastWeek: { weight: 185, reps: 8 }, priorWeek: { weight: 180, reps: 8 } },
    { name: "Squat", lastWeek: { weight: 245, reps: 5 }, priorWeek: null },
  ],
});

describe("buildWeeklyInsightsUserPrompt", () => {
  it("includes both weeks, the unit label, and every lift", () => {
    const prompt = buildWeeklyInsightsUserPrompt(request);
    expect(prompt).toContain("Last week (week of 2026-08-31)");
    expect(prompt).toContain("The week before (week of 2026-08-24)");
    expect(prompt).toContain("Sessions completed: 3");
    expect(prompt).toContain("Total volume: 24500 lb");
    expect(prompt).toContain("Average difficulty (1 easy - 5 brutal): 3.7");
    expect(prompt).toContain("Bench Press: last week 185 lb x 8; week before 180 lb x 8");
    expect(prompt).toContain("Squat: last week 245 lb x 5; week before not trained");
    expect(prompt).toContain("planned sessions per week: 4");
    expect(prompt).toContain("save_weekly_insights");
  });

  it("says so when there was no prior week and omits the difficulty line when unrated", () => {
    const first = WeeklyInsightsRequestSchema.parse({
      weightUnit: "kg",
      lastWeek: { ...request.lastWeek, averageDifficulty: null },
      priorWeek: null,
      lifts: [],
    });
    const prompt = buildWeeklyInsightsUserPrompt(first);
    expect(prompt).toContain("The week before: no completed sessions.");
    expect(prompt).not.toContain("Average difficulty");
    expect(prompt).not.toContain("Best working set");
    expect(prompt).not.toContain("Lifter:");
  });
});
