import { getFirestore } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";

import { ChannelProfileSchema } from "@tandem/shared-types";

import { GEMINI_API_KEY, MODEL_CHEAP, MODEL_DEEP, callGemini } from "../lib/gemini.js";
import { buildOutreachPrompt, OutreachSchema } from "../lib/prompts.js";
import { assertAndIncrement } from "../lib/quota.js";

const InputSchema = z.object({
  fromKey: z.string(),
  toKey: z.string(),
  angle: z.string().max(200).optional(),
});

export const draftOutreach = onCall(
  {
    region: "us-central1",
    enforceAppCheck: false,
    cors: true,
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 30,
  },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const parsed = InputSchema.safeParse(req.data);
    if (!parsed.success) throw new HttpsError("invalid-argument", parsed.error.message);
    const { fromKey, toKey, angle } = parsed.data;

    await assertAndIncrement(uid, "outreach");

    const db = getFirestore();
    const [fromSnap, toSnap] = await Promise.all([
      db.doc(`channels/${fromKey}`).get(),
      db.doc(`channels/${toKey}`).get(),
    ]);

    if (!fromSnap.exists || !toSnap.exists) {
      throw new HttpsError("not-found", "Channel(s) not found in cache. Analyze them first.");
    }

    const from = ChannelProfileSchema.parse(fromSnap.data());
    const to = ChannelProfileSchema.parse(toSnap.data());

    const result = await callGemini(
      buildOutreachPrompt(from, to, angle ?? "a short-form content swap"),
      OutreachSchema,
      { model: MODEL_CHEAP, fallbackModel: MODEL_DEEP },
    );
    return result;
  },
);
