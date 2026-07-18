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
import { GEMINI_API_KEY, MODEL_CHEAP, MODEL_DEEP, callGemini } from "../lib/gemini.js";
import { embedText, profileEmbeddingText } from "../lib/embeddings.js";
import { AiProfileSchema, buildProfilePrompt } from "../lib/prompts.js";
import { assertAndIncrement } from "../lib/quota.js";
import { computeActivitySignals, computePrimaryLanguage } from "../lib/signals.js";

const InputSchema = z.object({
  ref: ChannelRefSchema,
  ownership: z.enum(["self", "watching"]).default("watching"),
  /** Force a fresh (paid) re-analysis even if a recent cached one exists. */
  force: z.boolean().default(false),
});

/** Reuse a cached analysis within this window to avoid repeat AI cost. */
const ANALYSIS_TTL_MS = 14 * 24 * 60 * 60 * 1000; // 14 days

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
    const { ref, ownership, force } = parsed.data;

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

    const db = getFirestore();
    const resolvedKey = channelKey(baseProfile.ref.platform, baseProfile.ref.externalId);
    const channelDocRef = db.doc(`channels/${resolvedKey}`);

    // --- Cost guard: reuse a recent, complete analysis (no AI, no quota) ---
    if (!force) {
      const existing = await channelDocRef.get();
      if (existing.exists) {
        const data = existing.data() ?? {};
        const stamp = Date.parse((data.updatedAt ?? data.sourceSnapshotAt ?? "") as string);
        const fresh = !Number.isNaN(stamp) && Date.now() - stamp < ANALYSIS_TTL_MS;
        const complete =
          data.confidence &&
          data.confidence !== "Low" &&
          Array.isArray(data.embedding) &&
          data.embedding.length > 0;
        if (fresh && complete) {
          await db.doc(`users/${uid}/connectedChannels/${resolvedKey}`).set(
            {
              channelKey: resolvedKey,
              platform: baseProfile.ref.platform,
              ownership,
              name: data.name ?? baseProfile.name,
              niche: data.niche ?? baseProfile.niche,
              followers: data.followers ?? baseProfile.followers,
              thumbnailUrl: (data.thumbnailUrl as string | undefined) ?? baseProfile.thumbnailUrl ?? null,
              addedAt: new Date().toISOString(),
              lastAnalyzedAt: (data.sourceSnapshotAt ?? data.updatedAt) as string,
            },
            { merge: true },
          );
          return { channelKey: resolvedKey, profile: data, cached: true };
        }
      }
    }

    // Fresh analysis path — this is the paid work, so charge quota now.
    await assertAndIncrement(uid, "analyses");

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
      aiProfile = await callGemini(buildProfilePrompt(baseProfile, posts, comments), AiProfileSchema, {
        model: MODEL_CHEAP,
        fallbackModel: MODEL_DEEP,
      });
    } catch (e) {
      // If Gemini fails, fall through with heuristic profile.
      console.warn("Gemini profile call failed, using heuristic profile:", e);
    }

    // Deterministic reach/engagement/cadence/recency + primary language from posts.
    const activity = computeActivitySignals(posts);
    const region = aiProfile?.region ?? baseProfile.region;
    const language = computePrimaryLanguage(
      posts,
      `${baseProfile.name} ${baseProfile.description}`,
      region,
    );

    const merged: ChannelProfile = {
      ...baseProfile,
      niche: aiProfile?.niche ?? baseProfile.niche,
      subNiche: aiProfile?.subNiche ?? baseProfile.subNiche,
      region,
      format: aiProfile?.format ?? baseProfile.format,
      topics: aiProfile?.topics ?? baseProfile.topics,
      toneTags: aiProfile?.toneTags ?? baseProfile.toneTags,
      contentPillars: aiProfile?.contentPillars ?? baseProfile.contentPillars,
      audiencePersona: aiProfile?.audiencePersona,
      brandSafetyNotes: aiProfile?.brandSafetyNotes,
      idealCollaboratorProfile: aiProfile?.idealCollaboratorProfile,
      redFlags: aiProfile?.redFlags,
      avgViews: activity.avgViews ?? baseProfile.avgViews,
      medianViews: activity.medianViews ?? baseProfile.medianViews,
      engagementPct: activity.engagementPct ?? baseProfile.engagementPct,
      uploadsPerMonth: activity.uploadsPerMonth ?? baseProfile.uploadsPerMonth,
      lastUploadAt: activity.lastUploadAt ?? baseProfile.lastUploadAt,
      language: language ?? baseProfile.language,
      confidence: aiProfile ? (aiProfile.confidence ?? baseProfile.confidence) : "Low",
      sourceSnapshotAt: new Date().toISOString(),
    };

    // Semantic embedding for complementarity matching (best-effort, cached).
    try {
      const embedding = await embedText(profileEmbeddingText(merged));
      if (embedding.length > 0) merged.embedding = embedding;
    } catch (e) {
      console.warn("Embedding failed, complementarity will fall back to heuristics:", e);
    }

    const key = channelKey(merged.ref.platform, merged.ref.externalId);

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
        name: merged.name,
        niche: merged.niche,
        followers: merged.followers,
        thumbnailUrl: merged.thumbnailUrl ?? null,
        addedAt: new Date().toISOString(),
        lastAnalyzedAt: merged.sourceSnapshotAt,
      },
      { merge: true },
    );
    await batch.commit();

    return { channelKey: key, profile: merged };
  },
);
