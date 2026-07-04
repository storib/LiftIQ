import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

// aiUsageLogs live in a top-level, server-only collection keyed by userId, so
// recursiveDelete on the user document does not touch them. Delete them in
// query-sized batches (500 = Firestore batch write limit) until none remain.
async function deleteAiUsageLogs(
  db: admin.firestore.Firestore,
  userId: string,
): Promise<void> {
  const BATCH_SIZE = 500;
  for (;;) {
    const snapshot = await db
      .collection("aiUsageLogs")
      .where("userId", "==", userId)
      .limit(BATCH_SIZE)
      .get();

    if (snapshot.empty) return;

    const batch = db.batch();
    for (const doc of snapshot.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();

    if (snapshot.size < BATCH_SIZE) return;
  }
}

export const deleteAccount = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const userId = request.auth.uid;
  const db = admin.firestore();
  const userRef = db.collection("users").doc(userId);

  try {
    await db.recursiveDelete(userRef);
    await deleteAiUsageLogs(db, userId);
    await admin.auth().deleteUser(userId);
  } catch (error: any) {
    throw new HttpsError(
      "internal",
      error.message || "Account deletion failed"
    );
  }

  return { deleted: true };
});
