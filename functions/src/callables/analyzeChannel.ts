import { getFirestore } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";

import {
  channelKey,
  ChannelRefSchema,
  type ChannelProfile,
} from "@tandem/shared-types";

import { platformRegistry } from "../adapters/registry.js";
import { YOUTUBE_API_KEY } from "../adapters/youtube/index.js";
import { GEMINI_API_KEY, callGemini } from "../lib/gemini.js";
import { AiProfileSchema, buildProfilePrompt } from "../lib/prompts.js";
import { assertAndIncrement } from "../lib/quota.js";

const InputSchema = z.object({
  ref: ChannelRefSchema,
  ownership: z.enum(["self", "watching"]).default("watching"),
});

export const analyzeChannel = onCall(
  {
    region: "us-central1",
    enforceAppCheck: false,
    cors: true,
    secrets: [YOUTUBE_API_KEY, GEMINI_API_KEY],
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const parsed = InputSchema.safeParse(req.data);
    if (!parsed.success) throw new HttpsError("invalid-argument", parsed.error.message);
    const { ref, ownership } = parsed.data;

    await assertAndIncrement(uid, "analyses");

    const adapter = platformRegistry.get(ref.platform);

    let baseProfile: ChannelProfile;
    try {
      baseProfile = await adapter.fetchProfile(ref);
    } catch (e) {
      const msg = e instanceof Error ? e.message : "Unknown error";
      // Surface NotImplemented cleanly so the UI can tell the user IG/TikTok is v2.
      throw new HttpsError(
        msg.includes("not implement") ? "unimplemented" : "internal",
        msg,
      );
    }

    // Best-effort post + comment enrichment. Failures here should NOT block the analysis.
    let posts: Awaited<ReturnType<typeof adapter.fetchRecentPosts>> = [];
    let comments: Awaited<ReturnType<typeof adapter.fetchTopComments>> = [];
    try {
      posts = await adapter.fetchRecentPosts(ref, 25);
    } catch {
      /* tolerate */
    }
    if (posts.length > 0) {
      try {
        comments = await adapter.fetchTopComments(
          ref,
          posts.slice(0, 3).map((p) => p.id),
        );
      } catch {
        /* tolerate */
      }
    }

    // AI enrichment
    let aiProfile: z.infer<typeof AiProfileSchema> | null = null;
    try {
      aiProfile = await callGemini(buildProfilePrompt(baseProfile, posts, comments), AiProfileSchema);
    } catch (e) {
      // If Gemini fails, fall through with heuristic profile.
      console.warn("Gemini profile call failed, using heuristic profile:", e);
    }

    const merged: ChannelProfile = {
      ...baseProfile,
      niche: aiProfile?.niche ?? baseProfile.niche,
      subNiche: aiProfile?.subNiche ?? baseProfile.subNiche,
      region: aiProfile?.region ?? baseProfile.region,
      format: aiProfile?.format ?? baseProfile.format,
      topics: aiProfile?.topics ?? baseProfile.topics,
      toneTags: aiProfile?.toneTags ?? baseProfile.toneTags,
      contentPillars: aiProfile?.contentPillars ?? baseProfile.contentPillars,
      audiencePersona: aiProfile?.audiencePersona,
      brandSafetyNotes: aiProfile?.brandSafetyNotes,
      idealCollaboratorProfile: aiProfile?.idealCollaboratorProfile,
      redFlags: aiProfile?.redFlags,
      confidence: aiProfile ? (aiProfile.confidence ?? baseProfile.confidence) : "Low",
      sourceSnapshotAt: new Date().toISOString(),
    };

    const key = channelKey(merged.ref.platform, merged.ref.externalId);
    const db = getFirestore();

    // Upsert shared channel cache + push analysis snapshot.
    const channelRef = db.doc(`channels/${key}`);
    const analysisRef = channelRef.collection("analyses").doc();
    const connectionRef = db.doc(`users/${uid}/connectedChannels/${key}`);

    const batch = db.batch();
    batch.set(
      channelRef,
      { ...merged, channelKey: key, updatedAt: merged.sourceSnapshotAt },
      { merge: true },
    );
    batch.set(analysisRef, {
      ...merged,
      channelKey: key,
      analyzedBy: uid,
    });
    batch.set(
      connectionRef,
      {
        channelKey: key,
        platform: merged.ref.platform,
        ownership,
        addedAt: new Date().toISOString(),
        lastAnalyzedAt: merged.sourceSnapshotAt,
      },
      { merge: true },
    );
    await batch.commit();

    return { channelKey: key, profile: merged };
  },
);
