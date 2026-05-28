import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";

/**
 * Store-required: lets the user delete their account and all associated data.
 * Deletes:
 *   - users/{uid} document
 *   - users/{uid}/** subcollections (connectedChannels, shortlists, outreach, usage)
 *   - Firebase Auth user record
 *
 * Does NOT delete shared `channels/**` docs (they're useful to other users).
 */
export const deleteAccount = onCall(
  { region: "us-central1", enforceAppCheck: false, cors: true, timeoutSeconds: 60 },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const db = getFirestore();
    const userRef = db.doc(`users/${uid}`);

    // Recursively delete subcollections. Firestore Admin supports recursiveDelete via REST/SDK.
    await db.recursiveDelete(userRef);

    // Revoke + delete the Auth user.
    try {
      await getAuth().deleteUser(uid);
    } catch (e) {
      console.warn("Auth delete failed:", e);
    }

    return { ok: true };
  },
);
