import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as admin from "firebase-admin";
import { timingSafeEqual } from "crypto";
import exercises from "./data/exercises.json";

if (!admin.apps.length) admin.initializeApp();

const adminSeedKey = defineSecret("ADMIN_SEED_KEY");

function matchesAdminKey(provided: string | undefined, expected: string): boolean {
  if (!provided || !expected) return false;
  const providedBuffer = Buffer.from(provided);
  const expectedBuffer = Buffer.from(expected);
  return providedBuffer.length === expectedBuffer.length &&
    timingSafeEqual(providedBuffer, expectedBuffer);
}

export const seedExerciseDatabase = onRequest(
  { secrets: [adminSeedKey] },
  async (req, res) => {
    if (req.method !== "POST") {
      res.set("Allow", "POST");
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    if (!matchesAdminKey(req.get("x-admin-key"), adminSeedKey.value())) {
      res.status(403).json({ error: "Unauthorized" });
      return;
    }

    const db = admin.firestore();
    let batch = db.batch();
    let pendingWrites = 0;
    let count = 0;

    for (const exercise of exercises as any[]) {
      const ref = db.collection("exercises").doc(exercise.id);
      batch.set(ref, exercise);
      pendingWrites++;
      count++;

      // Firestore batches are limited to 500 operations
      if (pendingWrites === 450) {
        await batch.commit();
        batch = db.batch();
        pendingWrites = 0;
      }
    }

    if (pendingWrites > 0) {
      await batch.commit();
    }

    res.json({
      success: true,
      exercisesSeeded: count,
      timestamp: new Date().toISOString(),
    });
  }
);
