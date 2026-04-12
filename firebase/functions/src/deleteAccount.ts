import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

if (!admin.apps.length) admin.initializeApp();

export const deleteAccount = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const userId = request.auth.uid;
  const db = admin.firestore();
  const userRef = db.collection("users").doc(userId);

  try {
    await db.recursiveDelete(userRef);
    await admin.auth().deleteUser(userId);
  } catch (error: any) {
    throw new HttpsError(
      "internal",
      error.message || "Account deletion failed"
    );
  }

  return { deleted: true };
});
