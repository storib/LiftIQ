import { describe, it, expect } from "vitest";
import {
  computeRecordsForSession,
  epley,
  progressRecordIdsForSession,
  staleProgressRecordIds,
} from "../src/computeProgressRecords";

const SESSION_ID = "session-123";

function workingSet(weightKg: number, reps: number) {
  return { setType: "working", weightKg, reps };
}

// Reference implementation mirroring the Swift client (Epley.swift):
// reps <= 1 returns the weight unchanged.
function referenceEpley(weightKg: number, reps: number) {
  if (reps <= 1) return weightKg;
  return weightKg * (1 + reps / 30.0);
}

describe("epley (Swift client parity)", () => {
  it("returns the weight unchanged for a 1-rep set", () => {
    expect(epley(100, 1)).toBe(100);
    expect(epley(142.5, 1)).toBe(142.5);
  });

  it("applies the (1 + reps/30) multiplier for reps >= 2", () => {
    expect(epley(100, 2)).toBeCloseTo(100 * (1 + 2 / 30.0), 10);
    expect(epley(95, 8)).toBeCloseTo(95 * (1 + 8 / 30.0), 10);
  });

  it("matches the Swift reference across a grid of inputs", () => {
    for (const weight of [20, 60, 100, 142.5, 200]) {
      for (const reps of [1, 2, 3, 5, 8, 12, 20]) {
        expect(epley(weight, reps)).toBeCloseTo(referenceEpley(weight, reps), 10);
      }
    }
  });
});

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

  it("uses the raw weight as e1RM for a 1-rep set (Swift client parity)", () => {
    const session = {
      startedAt: "2026-06-30T10:00:00Z",
      exerciseLogs: [
        {
          exerciseId: "deadlift",
          exerciseName: "Deadlift",
          sets: [workingSet(180, 1)],
        },
      ],
    };
    const records = computeRecordsForSession(session, SESSION_ID);
    expect(records).toHaveLength(1);
    // No (1 + 1/30) inflation: a single at 180 estimates exactly 180.
    expect(records[0].estimated1RM).toBe(180);
    expect(records[0].bestSetWeight).toBe(180);
    expect(records[0].bestSetReps).toBe(1);
  });

  it("compares best sets using the reps==1 special case", () => {
    const session = {
      exerciseLogs: [
        {
          exerciseId: "squat",
          exerciseName: "Back Squat",
          // 150x1 → e1RM 150 (not 155); 145x2 → e1RM 154.67. Under the old
          // formula the single would have won (155 > 154.67); with client
          // parity the double wins.
          sets: [workingSet(150, 1), workingSet(145, 2)],
        },
      ],
    };
    const records = computeRecordsForSession(session, SESSION_ID);
    expect(records).toHaveLength(1);
    expect(records[0].bestSetWeight).toBe(145);
    expect(records[0].bestSetReps).toBe(2);
    expect(records[0].estimated1RM).toBeCloseTo(145 * (1 + 2 / 30.0), 6);
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

describe("staleProgressRecordIds", () => {
  it("returns ids for exercises the new record set no longer produces", () => {
    const before = {
      exerciseLogs: [
        { exerciseId: "bench-press", sets: [workingSet(100, 5)] },
        { exerciseId: "squat", sets: [workingSet(140, 5)] },
      ],
    };
    // Edited session dropped squat entirely.
    const after = {
      exerciseLogs: [{ exerciseId: "bench-press", sets: [workingSet(100, 5)] }],
    };
    const records = computeRecordsForSession(after, SESSION_ID);

    expect(staleProgressRecordIds(before, records, SESSION_ID)).toEqual([
      `${SESSION_ID}_squat`,
    ]);
  });

  it("flags an exercise whose working sets were all invalidated", () => {
    const before = {
      exerciseLogs: [{ exerciseId: "squat", sets: [workingSet(140, 5)] }],
    };
    // Same exercise still present, but no valid working sets -> no record.
    const after = {
      exerciseLogs: [{ exerciseId: "squat", sets: [{ setType: "working", weightKg: 0, reps: 0 }] }],
    };
    const records = computeRecordsForSession(after, SESSION_ID);

    expect(records).toEqual([]);
    expect(staleProgressRecordIds(before, records, SESSION_ID)).toEqual([
      `${SESSION_ID}_squat`,
    ]);
  });

  it("returns nothing when the record set covers everything the before snapshot had", () => {
    const session = {
      exerciseLogs: [{ exerciseId: "bench-press", sets: [workingSet(100, 5)] }],
    };
    const records = computeRecordsForSession(session, SESSION_ID);

    expect(staleProgressRecordIds(session, records, SESSION_ID)).toEqual([]);
  });

  it("returns nothing without a before snapshot (session creation)", () => {
    expect(staleProgressRecordIds(undefined, [], SESSION_ID)).toEqual([]);
  });
});
