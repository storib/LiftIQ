import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

// Top-level collections keyed by userId (aiUsageLogs, betaEvents) sit outside
// /users/{uid}, so recursiveDelete on the user document does not touch them.
// Delete them in query-sized batches (500 = Firestore batch write limit)
// until none remain. Add any new user-keyed top-level collection to
// USER_KEYED_COLLECTIONS.
const USER_KEYED_COLLECTIONS = ["aiUsageLogs", "betaEvents"] as const;

export async function deleteUserKeyedCollection(
  db: admin.firestore.Firestore,
  collection: string,
  userId: string,
): Promise<void> {
  const BATCH_SIZE = 500;
  for (;;) {
    const snapshot = await db
      .collection(collection)
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
    for (const collection of USER_KEYED_COLLECTIONS) {
      await deleteUserKeyedCollection(db, collection, userId);
    }
    await admin.auth().deleteUser(userId);
  } catch (error: any) {
    throw new HttpsError(
      "internal",
      error.message || "Account deletion failed"
    );
  }

  return { deleted: true };
});
