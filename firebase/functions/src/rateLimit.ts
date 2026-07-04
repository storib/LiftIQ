import { HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const DAY_MS = 24 * 60 * 60 * 1000;

// Counts aiUsageLogs entries for this user + function over the trailing 24
// hours and rejects the request when the cap is reached. Every AI function
// writes an aiUsageLogs entry per invocation (success or failure), so the
// log doubles as the rate-limit ledger — no extra counter collection needed.
export async function assertWithinDailyQuota(
  db: admin.firestore.Firestore,
  userId: string,
  functionName: string,
  maxPerDay: number,
): Promise<void> {
  const since = admin.firestore.Timestamp.fromMillis(Date.now() - DAY_MS);
  const snapshot = await db
    .collection("aiUsageLogs")
    .where("userId", "==", userId)
    .where("function", "==", functionName)
    .where("createdAt", ">=", since)
    .count()
    .get();

  if (snapshot.data().count >= maxPerDay) {
    throw new HttpsError(
      "resource-exhausted",
      `Daily limit of ${maxPerDay} requests reached for this feature. Try again later.`,
    );
  }
}
