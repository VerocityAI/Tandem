import { getFirestore } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";

import {
  ChannelProfileSchema,
  type ChannelProfile,
  PlatformSchema,
  channelKey as makeChannelKey,
} from "@cohyve/shared-types";

import { platformRegistry } from "../adapters/registry.js";
import { YOUTUBE_API_KEY } from "../adapters/youtube/index.js";
import { GEMINI_API_KEY, MODEL_CHEAP, MODEL_DEEP, callGemini } from "../lib/gemini.js";
import { cosine, embedText, overlapFromCosine, profileEmbeddingText } from "../lib/embeddings.js";
import { explainMatch } from "../lib/explain.js";
import { buildRerankPrompt, RerankSchema, type RerankCandidate } from "../lib/prompts.js";
import { assertAndIncrement } from "../lib/quota.js";
import { ADJACENT_NICHES, passesRealismGate, scoreCreator } from "../lib/scoring.js";
import { computeActivitySignals, computePrimaryLanguage } from "../lib/signals.js";

const FiltersSchema = z.object({
  niche: z.string().optional(),
  region: z.string().optional(),
  platforms: z.array(PlatformSchema).optional(),
  minScore: z.number().min(0).max(100).default(0),
  limit: z.number().int().min(1).max(48).default(24),
  enableAiRerank: z.boolean().default(true),
  /** Force a fresh (paid) run instead of returning the cached result. */
  refresh: z.boolean().default(false),
});

/** Reuse a cached match run within this window to avoid repeat AI + search cost. */
const MATCH_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours
/** Skip the (expensive) YouTube search discovery when the cached pool already
 *  has at least this many relevant candidates. */
const MIN_POOL_TO_SKIP_DISCOVERY = 30;

/** Stable, filesystem-safe cache id derived from the filters that affect output. */
function matchCacheId(filters: {
  niche?: string;
  region?: string;
  platforms?: string[];
  minScore: number;
  limit: number;
  enableAiRerank: boolean;
}): string {
  const raw = [
    filters.niche ?? "",
    filters.region ?? "",
    (filters.platforms ?? []).join(","),
    filters.minScore,
    filters.limit,
    filters.enableAiRerank ? 1 : 0,
  ].join("|");
  return raw.replace(/[^a-zA-Z0-9]+/g, "_").slice(0, 200) || "default";
}


const InputSchema = z.object({
  profileChannelKey: z.string(),
  filters: FiltersSchema.default({}),
});

const TOP_N_FOR_AI = 12;
const YOUTUBE_SEARCH_LIMIT = 15;
const MIN_RELEVANCE_SCORE = 0.25;

/** Build diverse search queries from the source channel's profile. */
function buildSearchQueries(source: ChannelProfile): string[] {
  const queries: string[] = [];
  const niche = source.niche.trim();
  // Query 1: subNiche (most specific) or niche
  if (source.subNiche) queries.push(source.subNiche);
  else queries.push(niche);
  // Query 2: top content pillars
  if (source.contentPillars && source.contentPillars.length > 0) {
    queries.push(source.contentPillars.slice(0, 2).join(" "));
  }
  // Query 3: top topics
  if (source.topics.length >= 2) {
    queries.push(source.topics.slice(0, 3).join(" "));
  }
  // Query 4: niche + leading topic (surfaces same-lane peers, e.g. "Tech reviews")
  if (niche && source.topics.length > 0) {
    queries.push(`${niche} ${source.topics[0]}`);
  }
  // Query 5+: ADJACENT-niche queries — deliberately break the clone bias by
  // seeding partners in related-but-different lanes (the collaboration sweet spot).
  const adjacents = ADJACENT_NICHES[source.niche] ?? [];
  const leadTopic = source.topics[0];
  for (const adj of adjacents.slice(0, 2)) {
    queries.push(leadTopic ? `${adj} ${leadTopic}` : `${adj} creators`);
  }
  // Broad peer net as a fallback.
  if (niche) queries.push(`${niche} creators`);
  return [...new Set(queries.map((q) => q.trim()).filter(Boolean))].slice(0, 6);
}

function norm(value: string | undefined): string {
  return (value ?? "").trim().toLowerCase();
}

function tokenize(value: string | undefined): Set<string> {
  const out = new Set<string>();
  for (const part of norm(value).split(/[^a-z0-9]+/g)) {
    if (part.length >= 3) out.add(part);
  }
  return out;
}

function overlapCount(a: Set<string>, b: Set<string>): number {
  let count = 0;
  for (const t of a) {
    if (b.has(t)) count += 1;
  }
  return count;
}

function sourceKeywordSet(source: ChannelProfile): Set<string> {
  const all = new Set<string>();
  const add = (value: string | undefined) => {
    for (const t of tokenize(value)) all.add(t);
  };
  add(source.niche);
  add(source.subNiche);
  for (const t of source.topics) add(t);
  for (const p of source.contentPillars ?? []) add(p);
  return all;
}

function relevanceScore(source: ChannelProfile, candidate: ChannelProfile): number {
  const sourceNiche = norm(source.niche);
  const candidateNiche = norm(candidate.niche);
  const candidateSubNiche = norm(candidate.subNiche);
  const sourceSubNiche = norm(source.subNiche);
  const adjacents = (ADJACENT_NICHES[source.niche] ?? []).map(norm);

  let score = 0;
  if (sourceNiche && candidateNiche && sourceNiche === candidateNiche) score += 0.6;
  else if (candidateNiche && adjacents.includes(candidateNiche)) score += 0.4;
  if (sourceSubNiche && candidateSubNiche && sourceSubNiche === candidateSubNiche) score += 0.25;

  const sourceTopics = new Set(source.topics.map(norm).filter(Boolean));
  const candidateTopics = new Set(candidate.topics.map(norm).filter(Boolean));
  const tOverlap = overlapCount(sourceTopics, candidateTopics);
  const tBase = Math.max(1, Math.min(sourceTopics.size, candidateTopics.size));
  const topicRatio = tOverlap / tBase;
  score += 0.15 * Math.min(1, topicRatio);

  const sourceTokens = sourceKeywordSet(source);
  const candidateTokens = tokenize(`${candidate.niche} ${candidate.subNiche} ${(candidate.topics ?? []).join(" ")}`);
  const kOverlap = overlapCount(sourceTokens, candidateTokens);
  if (sourceTokens.size > 0) {
    score += 0.1 * Math.min(1, kOverlap / sourceTokens.size);
  }

  return Math.min(1, score);
}

function isRelevantCandidate(
  source: ChannelProfile,
  candidate: ChannelProfile,
  requestedNiche: string,
  opts: { discovered?: boolean } = {},
): boolean {
  const requested = norm(requestedNiche);
  const candNiche = norm(candidate.niche);
  const adjacents = (ADJACENT_NICHES[requestedNiche] ?? []).map(norm);
  const nicheOk = !requested || candNiche === requested || adjacents.includes(candNiche);

  const sourceTopics = new Set(source.topics.map(norm).filter(Boolean));
  const candidateTopics = new Set(candidate.topics.map(norm).filter(Boolean));
  const topicHit = overlapCount(sourceTopics, candidateTopics);
  const sameOrAdjacent =
    candNiche === norm(source.niche) ||
    (ADJACENT_NICHES[source.niche] ?? []).map(norm).includes(candNiche);

  // Freshly discovered candidates came from a niche-targeted YouTube search, so
  // they are topically relevant by construction. Heuristic niche labels on a
  // fresh fetch are unreliable, so don't hard-reject on niche; require only a
  // light relevance signal (adjacency, topic, or keyword overlap with source).
  if (opts.discovered) {
    if (!candidate.name.trim()) return false;
    if (sameOrAdjacent || topicHit > 0) return true;
    const kwOverlap = overlapCount(
      sourceKeywordSet(source),
      tokenize(
        `${candidate.name} ${candidate.niche} ${candidate.subNiche ?? ""} ${(candidate.topics ?? []).join(" ")}`,
      ),
    );
    return kwOverlap > 0;
  }

  // Cached pool: enforce the niche gate to keep mislabeled junk out.
  if (!nicheOk) return false;
  if (!sameOrAdjacent && topicHit === 0) return false;

  return relevanceScore(source, candidate) >= MIN_RELEVANCE_SCORE;
}

export const findMatches = onCall(
  {
    region: "us-central1",
    enforceAppCheck: false,
    cors: true,
    secrets: [GEMINI_API_KEY, YOUTUBE_API_KEY],
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const parsed = InputSchema.safeParse(req.data);
    if (!parsed.success) throw new HttpsError("invalid-argument", parsed.error.message);
    const { profileChannelKey, filters } = parsed.data;

    const db = getFirestore();

    // --- Cost guard: return a recent cached match run unless refresh requested ---
    const cacheRef = db.doc(
      `channels/${profileChannelKey}/matchCache/${matchCacheId(filters)}`,
    );
    if (!filters.refresh) {
      const cacheSnap = await cacheRef.get();
      if (cacheSnap.exists) {
        const cache = cacheSnap.data() ?? {};
        const stamp = Date.parse((cache.computedAt ?? "") as string);
        if (!Number.isNaN(stamp) && Date.now() - stamp < MATCH_TTL_MS && Array.isArray(cache.matches)) {
          return { matches: cache.matches, cached: true };
        }
      }
    }

    // Load source profile.
    const sourceSnap = await db.doc(`channels/${profileChannelKey}`).get();
    if (!sourceSnap.exists) {
      throw new HttpsError("not-found", "Source channel not found. Analyze it first.");
    }
    const source = ChannelProfileSchema.parse(sourceSnap.data());

    // --- Phase 1: Gather candidates from Firestore cache ---
    const requestedNiche = filters.niche?.trim() || source.niche;

    // Collaboration model: include the requested niche AND its adjacents so we
    // surface adjacent-audience partners, not just exact-niche clones.
    const nicheSet = [requestedNiche, ...(ADJACENT_NICHES[requestedNiche] ?? [])]
      .filter((n, i, arr) => n && arr.indexOf(n) === i)
      .slice(0, 10);

    let q: FirebaseFirestore.Query =
      nicheSet.length > 1
        ? db.collection("channels").where("niche", "in", nicheSet)
        : db.collection("channels").where("niche", "==", requestedNiche);
    if (filters.region) q = q.where("region", "==", filters.region);
    const candidatesSnap = await q.limit(200).get();

    const pool: ChannelProfile[] = candidatesSnap.docs
      .map((d) => {
        const p = ChannelProfileSchema.safeParse(d.data());
        return p.success ? p.data : null;
      })
      .filter((c): c is ChannelProfile => c !== null)
      .filter((c) => c.ref.externalId !== source.ref.externalId)
      .filter((c) => !filters.platforms || filters.platforms.includes(c.ref.platform))
      .filter((c) => isRelevantCandidate(source, c, requestedNiche));

    // --- Phase 2: YouTube search discovery ---
    const existingIds = new Set(pool.map((c) => c.ref.externalId));
    existingIds.add(source.ref.externalId);

    const adapter = platformRegistry.get("youtube");
    const discoveredProfiles: ChannelProfile[] = [];

    // Cost guard: YouTube search costs ~100 quota units/query. Skip discovery
    // entirely when the cached candidate pool is already rich enough.
    const searchQueries =
      pool.length < MIN_POOL_TO_SKIP_DISCOVERY ? buildSearchQueries(source) : [];
    for (const query of searchQueries) {
      try {
        const refs = await adapter.searchCandidates({
          text: query,
          limit: YOUTUBE_SEARCH_LIMIT,
        });
        // Fetch profiles for new candidates (parallel, best-effort)
        const newRefs = refs.filter((r) => !existingIds.has(r.externalId));
        const fetches = newRefs.slice(0, 12).map(async (ref) => {
          try {
            const profile = await adapter.fetchProfile(ref);
            const key = makeChannelKey(profile.ref.platform, profile.ref.externalId);
            // Cache in Firestore for future matches (fire-and-forget)
            db.doc(`channels/${key}`).set(
              { ...profile, channelKey: key, updatedAt: new Date().toISOString() },
              { merge: true },
            ).catch(() => {});
            existingIds.add(profile.ref.externalId);
            return profile;
          } catch {
            return null;
          }
        });
        const results = await Promise.all(fetches);
        for (const p of results) {
          if (!p) continue;
          if (!isRelevantCandidate(source, p, requestedNiche, { discovered: true })) continue;
          discoveredProfiles.push(p);
        }
      } catch {
        // Search failed — continue with other queries
      }
    }

    const allCandidates = [...pool, ...discoveredProfiles];

    // --- Phase 3: Realism gate + score all candidates ---
    const scored = allCandidates
      .filter((c) => passesRealismGate(source, c))
      .map((c) => {
        const result = scoreCreator(source, c);
        return { profile: c, ...result };
      })
      .filter((r) => r.score >= filters.minScore)
      .sort((a, b) => b.score - a.score)
      .slice(0, filters.limit);

    // --- Phase 3b: Enrich shortlist signals + semantic complementarity refine ---
    // Stage two of scoring: for the shortlist only (bounds quota), fetch recent
    // posts to compute real reach/engagement/activity/language for candidates
    // that lack them, then re-score using embedding cosine similarity so
    // adjacent-(not identical) audiences win. Candidate embeddings + signals are
    // cached back to Firestore for reuse.
    const ENRICH_LIMIT = 20;

    const enrichSignals = async (profile: ChannelProfile): Promise<ChannelProfile> => {
      if (profile.ref.platform !== "youtube") return profile;
      let p = profile;

      // Backfill the channel avatar (+ refresh core fields) when missing — many
      // channels were cached before thumbnails were captured. Cheap single call.
      if (!p.thumbnailUrl) {
        try {
          const fresh = await adapter.fetchProfile(p.ref);
          p = {
            ...p,
            thumbnailUrl: fresh.thumbnailUrl ?? p.thumbnailUrl,
            name: p.name || fresh.name,
            followers: p.followers || fresh.followers,
          };
          if (fresh.thumbnailUrl) {
            const key = makeChannelKey(p.ref.platform, p.ref.externalId);
            db.doc(`channels/${key}`)
              .set({ thumbnailUrl: fresh.thumbnailUrl }, { merge: true })
              .catch(() => {});
          }
        } catch {
          /* tolerate */
        }
      }

      if (p.avgViews !== undefined && p.lastUploadAt !== undefined) return p;
      try {
        const posts = await adapter.fetchRecentPosts(p.ref, 12);
        if (posts.length === 0) return p;
        const activity = computeActivitySignals(posts);
        const language =
          p.language ??
          computePrimaryLanguage(posts, `${p.name} ${p.description}`, p.region);
        const enriched: ChannelProfile = { ...p, ...activity, language };
        const k = makeChannelKey(p.ref.platform, p.ref.externalId);
        db.doc(`channels/${k}`)
          .set({ ...activity, language, updatedAt: new Date().toISOString() }, { merge: true })
          .catch(() => {});
        return enriched;
      } catch {
        return p;
      }
    };

    let srcEmbedding: number[] = [];
    try {
      srcEmbedding =
        source.embedding && source.embedding.length > 0
          ? source.embedding
          : await embedText(profileEmbeddingText(source));
    } catch (e) {
      console.warn("Source embedding failed, using heuristic complementarity:", e);
    }

    await Promise.all(
      scored.map(async (item, idx) => {
        if (idx < ENRICH_LIMIT) {
          item.profile = await enrichSignals(item.profile);
        }

        let emb = item.profile.embedding;
        if ((!emb || emb.length === 0) && srcEmbedding.length > 0) {
          try {
            emb = await embedText(profileEmbeddingText(item.profile));
            if (emb.length > 0) {
              const k = makeChannelKey(item.profile.ref.platform, item.profile.ref.externalId);
              db.doc(`channels/${k}`).set({ embedding: emb }, { merge: true }).catch(() => {});
            }
          } catch {
            emb = undefined;
          }
        }

        const opts =
          emb && emb.length > 0 && srcEmbedding.length > 0
            ? { overlapSimilarity: overlapFromCosine(cosine(srcEmbedding, emb)) }
            : {};
        const res = scoreCreator(source, item.profile, opts);
        item.score = res.score;
        item.breakdown = res.breakdown;
        item.reason = res.reason;
        item.mutualBenefitTag = res.mutualBenefitTag;
      }),
    );
    scored.sort((a, b) => b.score - a.score);

    // --- Phase 4: AI rerank top N ---
    if (filters.enableAiRerank && scored.length > 0) {
      await assertAndIncrement(uid, "reranks");

      const topForAi = scored.slice(0, TOP_N_FOR_AI);
      const aiCandidates: RerankCandidate[] = topForAi.map((s) => ({
        channelKey: makeChannelKey(s.profile.ref.platform, s.profile.ref.externalId),
        name: s.profile.name,
        platform: s.profile.ref.platform,
        niche: s.profile.niche,
        subNiche: s.profile.subNiche,
        region: s.profile.region,
        language: s.profile.language,
        followers: s.profile.followers,
        avgViews: s.profile.medianViews ?? s.profile.avgViews,
        engagementPct: s.profile.engagementPct,
        uploadsPerMonth: s.profile.uploadsPerMonth,
        format: s.profile.format,
        topics: s.profile.topics,
        contentPillars: s.profile.contentPillars,
        description: s.profile.description,
        ruleScore: s.score,
      }));

      try {
        const rerank = await callGemini(buildRerankPrompt(source, aiCandidates), RerankSchema, {
          model: MODEL_CHEAP,
          fallbackModel: MODEL_DEEP,
        });
        const byKey = new Map(rerank.matches.map((m) => [m.channelKey, m]));
        for (const item of topForAi) {
          const k = makeChannelKey(item.profile.ref.platform, item.profile.ref.externalId);
          const ai = byKey.get(k);
          if (ai) {
            const blended = Math.round(0.6 * ai.aiScore + 0.4 * item.score);
            (item as unknown as { aiScore: number }).aiScore = ai.aiScore;
            (item as unknown as { aiRationale: string }).aiRationale = ai.rationale;
            (item as unknown as { aiCollab: string }).aiCollab = ai.suggestedCollab;
            (item as unknown as { aiRisks: string[] }).aiRisks = ai.risks ?? [];
            (item as unknown as { blendedScore: number }).blendedScore = blended;
          }
        }
        scored.sort((a, b) => {
          const aScore = (a as unknown as { blendedScore?: number }).blendedScore ?? a.score;
          const bScore = (b as unknown as { blendedScore?: number }).blendedScore ?? b.score;
          return bScore - aScore;
        });
      } catch (e) {
        console.warn("Gemini rerank failed, returning rule-only results:", e);
      }
    }

    const matches = scored.map((s) => ({
      channelKey: makeChannelKey(s.profile.ref.platform, s.profile.ref.externalId),
      name: s.profile.name,
      platform: s.profile.ref.platform,
      thumbnailUrl: s.profile.thumbnailUrl,
      followers: s.profile.followers,
      views: s.profile.views,
      avgViews: s.profile.avgViews,
      medianViews: s.profile.medianViews,
      engagementPct: s.profile.engagementPct,
      uploadsPerMonth: s.profile.uploadsPerMonth,
      lastUploadAt: s.profile.lastUploadAt,
      language: s.profile.language,
      niche: s.profile.niche,
      subNiche: s.profile.subNiche,
      region: s.profile.region,
      format: s.profile.format,
      topics: s.profile.topics,
      score: (s as unknown as { blendedScore?: number }).blendedScore ?? s.score,
      ruleScore: s.score,
      breakdown: s.breakdown,
      reason: s.reason,
      whyMatch: explainMatch(source, s.profile),
      mutualBenefitTag: s.mutualBenefitTag,
      aiRationale: (s as unknown as { aiRationale?: string }).aiRationale,
      aiCollab: (s as unknown as { aiCollab?: string }).aiCollab,
      aiRisks: (s as unknown as { aiRisks?: string[] }).aiRisks,
    }));

    // Cache the run so repeat opens within the TTL cost nothing.
    cacheRef
      .set({ matches, computedAt: new Date().toISOString() })
      .catch(() => {});

    return { matches };
  },
);
