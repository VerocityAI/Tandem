/**
 * Daily per-user quota guard.
 *
 * Stored at `users/{uid}/usage/{YYYY-MM-DD}` with a counter per action type.
 * `assertAndIncrement` runs in a transaction: it throws `resource-exhausted`
 * when the daily limit is hit, otherwise increments the counter.
 */

import { getFirestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

export type QuotaType = "analyses" | "reranks" | "outreach";

const DAILY_LIMITS: Record<QuotaType, number> = {
  analyses: 50,
  reranks: 100,
  outreach: 50,
};

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

export async function assertAndIncrement(uid: string, type: QuotaType): Promise<void> {
  const db = getFirestore();
  const ref = db.doc(`users/${uid}/usage/${today()}`);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = (snap.data()?.[type] as number | undefined) ?? 0;
    if (current >= DAILY_LIMITS[type]) {
      throw new HttpsError(
        "resource-exhausted",
        `Daily ${type} limit reached. Please try again tomorrow.`,
      );
    }
    tx.set(
      ref,
      { [type]: current + 1, updatedAt: new Date().toISOString() },
      { merge: true },
    );
  });
}
