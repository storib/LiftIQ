import { onDocumentWritten } from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

export const computeProgressRecords = onDocumentWritten(
  "users/{userId}/workoutSessions/{sessionId}",
  async (event) => {
    const beforeData = event.data?.before?.data();
    const afterData = event.data?.after?.data();

    // Only run when status transitions to "completed"
    if (!afterData || afterData.status !== "completed") return;
    if (beforeData?.status === "completed") return;

    const userId = event.params.userId;
    const sessionId = event.params.sessionId;
    const db = admin.firestore();
    const exerciseLogs: any[] = afterData.exerciseLogs || [];

    const batch = db.batch();

    for (const log of exerciseLogs) {
      const workingSets = (log.sets || []).filter(
        (s: any) => s.setType === "working" && s.weightKg > 0 && s.reps > 0
      );

      if (workingSets.length === 0) continue;

      // Find best set by estimated 1RM (Epley formula)
      let bestSet = workingSets[0];
      for (const set of workingSets) {
        const e1rm = set.weightKg * (1 + set.reps / 30.0);
        const bestE1rm = bestSet.weightKg * (1 + bestSet.reps / 30.0);
        if (e1rm > bestE1rm) bestSet = set;
      }

      const totalVolume = workingSets.reduce(
        (sum: number, s: any) => sum + s.weightKg * s.reps,
        0
      );

      const recordId = `${sessionId}_${log.exerciseId}`;
      const progressRecord = {
        id: recordId,
        userId,
        exerciseId: log.exerciseId,
        date: afterData.startedAt,
        estimated1RM: bestSet.weightKg * (1 + bestSet.reps / 30.0),
        bestSetWeight: bestSet.weightKg,
        bestSetReps: bestSet.reps,
        totalVolume,
        totalSets: workingSets.length,
      };

      const ref = db
        .collection("users")
        .doc(userId)
        .collection("progressRecords")
        .doc(recordId);

      batch.set(ref, progressRecord);
    }

    await batch.commit();
  }
);
