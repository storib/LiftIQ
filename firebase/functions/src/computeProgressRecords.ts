import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

type SetLog = {
  setType?: string;
  weightKg?: number;
  reps?: number;
};

type ExerciseLog = {
  exerciseId?: string;
  exerciseName?: string;
  sets?: SetLog[];
};

export type SessionData = {
  startedAt?: unknown;
  exerciseLogs?: ExerciseLog[];
};

export type ProgressRecordDoc = {
  id: string;
  exerciseId: string;
  exerciseName: string;
  sessionId: string;
  date: unknown;
  estimated1RM: number;
  bestSetWeight: number;
  bestSetReps: number;
  totalVolume: number;
  totalSets: number;
};

// Epley e1RM estimate. Must mirror the Swift client formula in
// LiftIQ/LiftIQ/Utilities/Epley.swift exactly so on-device and server-side
// estimated1RM values agree: reps <= 0 and reps == 1 both return the weight
// unchanged; only reps >= 2 apply the (1 + reps/30) multiplier.
// Exported for unit tests.
export function epley(weightKg: number, reps: number): number {
  if (reps <= 1) return weightKg;
  return weightKg * (1 + reps / 30.0);
}

// Pure per-session record computation. Groups exerciseLogs by exerciseId so
// two logs of the same exercise in one session aggregate into a single record:
// bestSet is the max across all of that exercise's working sets by estimated
// 1RM (Epley — mirrors the pre-refactor metric), totalVolume/totalSets sum
// across the logs. Record IDs are deterministic (`${sessionId}_${exerciseId}`)
// so re-running the trigger for the same session overwrites rather than
// duplicates. Exported for unit tests.
export function computeRecordsForSession(
  session: SessionData,
  sessionId: string,
): ProgressRecordDoc[] {
  const exerciseLogs = session.exerciseLogs ?? [];

  // Group working sets (and a display name) by exerciseId, preserving the
  // order in which each exercise first appears.
  const byExercise = new Map<
    string,
    { exerciseName: string; sets: { weightKg: number; reps: number }[] }
  >();

  for (const log of exerciseLogs) {
    const exerciseId = log.exerciseId;
    if (typeof exerciseId !== "string" || exerciseId.length === 0) continue;

    const workingSets = (log.sets ?? []).filter(
      (s): s is { setType: string; weightKg: number; reps: number } =>
        s.setType === "working" &&
        typeof s.weightKg === "number" &&
        typeof s.reps === "number" &&
        s.weightKg > 0 &&
        s.reps > 0,
    );

    let entry = byExercise.get(exerciseId);
    if (!entry) {
      entry = { exerciseName: log.exerciseName ?? "", sets: [] };
      byExercise.set(exerciseId, entry);
    }
    if (!entry.exerciseName && log.exerciseName) {
      entry.exerciseName = log.exerciseName;
    }
    entry.sets.push(
      ...workingSets.map((s) => ({ weightKg: s.weightKg, reps: s.reps })),
    );
  }

  const records: ProgressRecordDoc[] = [];
  for (const [exerciseId, entry] of byExercise) {
    if (entry.sets.length === 0) continue;

    let bestSet = entry.sets[0];
    for (const set of entry.sets) {
      if (epley(set.weightKg, set.reps) > epley(bestSet.weightKg, bestSet.reps)) {
        bestSet = set;
      }
    }

    const totalVolume = entry.sets.reduce(
      (sum, s) => sum + s.weightKg * s.reps,
      0,
    );

    records.push({
      id: `${sessionId}_${exerciseId}`,
      exerciseId,
      exerciseName: entry.exerciseName,
      sessionId,
      date: session.startedAt,
      estimated1RM: epley(bestSet.weightKg, bestSet.reps),
      bestSetWeight: bestSet.weightKg,
      bestSetReps: bestSet.reps,
      totalVolume,
      totalSets: entry.sets.length,
    });
  }

  return records;
}

// Record IDs the previous snapshot could have produced that the new record
// set no longer does — an edit to a completed session can drop an exercise
// entirely or leave it with no valid working sets. Exported for unit tests.
export function staleProgressRecordIds(
  before: SessionData | undefined,
  newRecords: ProgressRecordDoc[],
  sessionId: string,
): string[] {
  if (!before) return [];
  const newIds = new Set(newRecords.map((r) => r.id));
  return progressRecordIdsForSession(before, sessionId).filter(
    (id) => !newIds.has(id),
  );
}

// Deterministic doc IDs for a session's progress records, derived from a
// session snapshot. Used to clean up when a session document is deleted —
// records written before the `sessionId` field existed are still covered.
export function progressRecordIdsForSession(
  session: SessionData,
  sessionId: string,
): string[] {
  const ids = new Set<string>();
  for (const log of session.exerciseLogs ?? []) {
    if (typeof log.exerciseId === "string" && log.exerciseId.length > 0) {
      ids.add(`${sessionId}_${log.exerciseId}`);
    }
  }
  return [...ids];
}

export const computeProgressRecords = onDocumentWritten(
  "users/{userId}/workoutSessions/{sessionId}",
  async (event) => {
    const beforeData = event.data?.before?.data() as SessionData | undefined;
    const afterData = event.data?.after?.data() as
      | (SessionData & { status?: string })
      | undefined;

    const userId = event.params.userId;
    const sessionId = event.params.sessionId;
    const db = admin.firestore();
    const recordCollection = db
      .collection("users")
      .doc(userId)
      .collection("progressRecords");

    // Session deleted: remove its progress records. Records may predate the
    // `sessionId` field, so derive the deterministic doc IDs from the
    // before-snapshot's exerciseLogs instead of querying by sessionId.
    if (!afterData) {
      if (!beforeData) return;
      const ids = progressRecordIdsForSession(beforeData, sessionId);
      if (ids.length === 0) return;
      const batch = db.batch();
      for (const id of ids) {
        batch.delete(recordCollection.doc(id));
      }
      await batch.commit();
      return;
    }

    // Recompute on every write while the session is completed — not just the
    // not-completed → completed transition — so edits to a completed session
    // keep records in sync. Deterministic doc IDs make re-runs idempotent.
    if (afterData.status !== "completed") return;

    const records = computeRecordsForSession(afterData, sessionId);
    // Edits to a completed session can remove an exercise (or strip its valid
    // working sets); delete the records the previous snapshot produced that
    // this write no longer does. Deleting a missing doc is a no-op.
    const staleIds = staleProgressRecordIds(beforeData, records, sessionId);
    if (records.length === 0 && staleIds.length === 0) return;

    const batch = db.batch();
    for (const record of records) {
      batch.set(recordCollection.doc(record.id), { ...record, userId });
    }
    for (const id of staleIds) {
      batch.delete(recordCollection.doc(id));
    }
    await batch.commit();
  }
);
