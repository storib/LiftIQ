import { describe, it, expect } from "vitest";
import {
  computeRecordsForSession,
  progressRecordIdsForSession,
} from "../src/computeProgressRecords";

const SESSION_ID = "session-123";

function workingSet(weightKg: number, reps: number) {
  return { setType: "working", weightKg, reps };
}

function epley(weightKg: number, reps: number) {
  return weightKg * (1 + reps / 30.0);
}

describe("computeRecordsForSession", () => {
  it("computes one record per exercise with best set, volume, and name", () => {
    const session = {
      startedAt: "2026-06-30T10:00:00Z",
      exerciseLogs: [
        {
          exerciseId: "bench-press",
          exerciseName: "Bench Press",
          sets: [workingSet(100, 5), workingSet(102.5, 3), workingSet(95, 8)],
        },
        {
          exerciseId: "squat",
          exerciseName: "Back Squat",
          sets: [workingSet(140, 5)],
        },
      ],
    };

    const records = computeRecordsForSession(session, SESSION_ID);
    expect(records).toHaveLength(2);

    const bench = records.find((r) => r.exerciseId === "bench-press")!;
    expect(bench.id).toBe(`${SESSION_ID}_bench-press`);
    expect(bench.sessionId).toBe(SESSION_ID);
    expect(bench.exerciseName).toBe("Bench Press");
    expect(bench.date).toBe("2026-06-30T10:00:00Z");
    // 95x8 has the highest Epley e1RM (120.33) of the three sets
    expect(bench.bestSetWeight).toBe(95);
    expect(bench.bestSetReps).toBe(8);
    expect(bench.estimated1RM).toBeCloseTo(epley(95, 8), 6);
    expect(bench.totalVolume).toBeCloseTo(100 * 5 + 102.5 * 3 + 95 * 8, 6);
    expect(bench.totalSets).toBe(3);

    const squat = records.find((r) => r.exerciseId === "squat")!;
    expect(squat.id).toBe(`${SESSION_ID}_squat`);
    expect(squat.exerciseName).toBe("Back Squat");
    expect(squat.totalSets).toBe(1);
  });

  it("aggregates two logs of the same exercise into a single record", () => {
    const session = {
      startedAt: "2026-06-30T10:00:00Z",
      exerciseLogs: [
        {
          exerciseId: "bench-press",
          exerciseName: "Bench Press",
          sets: [workingSet(100, 5), workingSet(100, 5)],
        },
        {
          exerciseId: "bench-press",
          exerciseName: "Bench Press",
          sets: [workingSet(110, 3)],
        },
      ],
    };

    const records = computeRecordsForSession(session, SESSION_ID);
    expect(records).toHaveLength(1);

    const record = records[0];
    expect(record.id).toBe(`${SESSION_ID}_bench-press`);
    // Best set by e1RM across BOTH logs: 110x3 (e1RM 121) beats 100x5 (116.67)
    expect(record.bestSetWeight).toBe(110);
    expect(record.bestSetReps).toBe(3);
    expect(record.estimated1RM).toBeCloseTo(epley(110, 3), 6);
    // Volume and set count sum across both logs
    expect(record.totalVolume).toBeCloseTo(100 * 5 + 100 * 5 + 110 * 3, 6);
    expect(record.totalSets).toBe(3);
  });

  it("ignores warm-up sets and sets with zero weight or reps", () => {
    const session = {
      exerciseLogs: [
        {
          exerciseId: "deadlift",
          exerciseName: "Deadlift",
          sets: [
            { setType: "warmup", weightKg: 60, reps: 10 },
            { setType: "working", weightKg: 0, reps: 5 },
            { setType: "working", weightKg: 100, reps: 0 },
            workingSet(180, 3),
          ],
        },
      ],
    };

    const records = computeRecordsForSession(session, SESSION_ID);
    expect(records).toHaveLength(1);
    expect(records[0].totalSets).toBe(1);
    expect(records[0].bestSetWeight).toBe(180);
    expect(records[0].totalVolume).toBeCloseTo(180 * 3, 6);
  });

  it("skips exercises with no valid working sets", () => {
    const session = {
      exerciseLogs: [
        {
          exerciseId: "plank",
          exerciseName: "Plank",
          sets: [{ setType: "working", weightKg: 0, reps: 1 }],
        },
      ],
    };
    expect(computeRecordsForSession(session, SESSION_ID)).toEqual([]);
  });

  it("returns empty for missing or empty exerciseLogs", () => {
    expect(computeRecordsForSession({}, SESSION_ID)).toEqual([]);
    expect(computeRecordsForSession({ exerciseLogs: [] }, SESSION_ID)).toEqual([]);
  });

  it("skips logs with a missing exerciseId", () => {
    const session = {
      exerciseLogs: [
        { exerciseName: "Mystery", sets: [workingSet(50, 10)] },
        { exerciseId: "", exerciseName: "Empty", sets: [workingSet(50, 10)] },
      ],
    };
    expect(computeRecordsForSession(session, SESSION_ID)).toEqual([]);
  });

  it("produces deterministic ids so re-runs overwrite instead of duplicating", () => {
    const session = {
      exerciseLogs: [
        { exerciseId: "row", exerciseName: "Row", sets: [workingSet(80, 8)] },
      ],
    };
    const first = computeRecordsForSession(session, SESSION_ID);
    const second = computeRecordsForSession(session, SESSION_ID);
    expect(first.map((r) => r.id)).toEqual(second.map((r) => r.id));
    expect(first[0].id).toBe(`${SESSION_ID}_row`);
  });

  it("backfills exerciseName from a later log of the same exercise", () => {
    const session = {
      exerciseLogs: [
        { exerciseId: "curl", sets: [workingSet(20, 12)] },
        { exerciseId: "curl", exerciseName: "Biceps Curl", sets: [workingSet(22.5, 8)] },
      ],
    };
    const records = computeRecordsForSession(session, SESSION_ID);
    expect(records).toHaveLength(1);
    expect(records[0].exerciseName).toBe("Biceps Curl");
  });
});

describe("progressRecordIdsForSession", () => {
  it("derives deterministic doc ids from exerciseLogs, deduplicated", () => {
    const session = {
      exerciseLogs: [
        { exerciseId: "bench-press", sets: [] },
        { exerciseId: "bench-press", sets: [] },
        { exerciseId: "squat", sets: [] },
        { exerciseId: "", sets: [] },
      ],
    };
    const ids = progressRecordIdsForSession(session, SESSION_ID);
    expect(ids.sort()).toEqual([
      `${SESSION_ID}_bench-press`,
      `${SESSION_ID}_squat`,
    ]);
  });

  it("returns empty for a session without logs", () => {
    expect(progressRecordIdsForSession({}, SESSION_ID)).toEqual([]);
  });
});
