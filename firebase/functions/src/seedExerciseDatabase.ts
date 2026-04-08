import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import exercises from "./data/exercises.json";

if (!admin.apps.length) admin.initializeApp();

export const seedExerciseDatabase = onRequest(async (req, res) => {
  // Simple auth check — in production, use a proper admin auth mechanism
  const adminKey = req.headers["x-admin-key"];
  if (adminKey !== process.env.ADMIN_SEED_KEY) {
    res.status(403).json({ error: "Unauthorized" });
    return;
  }

  const db = admin.firestore();
  const batch = db.batch();

  let count = 0;
  for (const exercise of exercises as any[]) {
    const ref = db.collection("exercises").doc(exercise.id);
    batch.set(ref, exercise);
    count++;

    // Firestore batches are limited to 500 operations
    if (count % 450 === 0) {
      await batch.commit();
    }
  }

  await batch.commit();

  res.json({
    success: true,
    exercisesSeeded: count,
    timestamp: new Date().toISOString(),
  });
});
