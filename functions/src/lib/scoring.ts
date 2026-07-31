/**
 * Rule-based collaboration scorer (YouTube-first).
 *
 * Philosophy — a great collaborator:
 *   1. Reaches a NEW but ADJACENT audience (relevant enough to transfer, but
 *      NOT an identical audience you already share — that adds no reach).
 *   2. Is of comparable-or-slightly-larger standing, so the swap is balanced
 *      and realistically landable (see `passesRealismGate`).
 *   3. Has genuine reach (avg views, not just vanity subscriber counts).
 *   4. Speaks the same language (audience transfer only works within a language).
 *   5. Is active, engaged, and brand-safe.
 *
 * The two "sweet-spot" dimensions (Complementarity, Audience Size) use an
 * inverted-U: too little AND too much both score low; the middle wins.
 *
 * The output `breakdown` (label, weight, value[0..100]) is consumed verbatim
 * by the mobile UI.
 */

import type { ChannelProfile, Format } from "@cohyve/shared-types";

export type AudienceTier = "micro" | "mid" | "large" | "mega";

/** Bucket a follower count into a tier. */
export function audienceTier(followers: number): AudienceTier {
  if (followers < 100_000) return "micro";
  if (followers < 500_000) return "mid";
  if (followers < 1_000_000) return "large";
  return "mega";
}

/**
 * Symmetric adjacency graph between niches. Collaborations across adjacent
 * niches expose each creator to a related-but-new audience.
 */
export const ADJACENT_NICHES: Record<string, string[]> = {
  Tech: ["Gaming", "Education", "Finance"],
  Gaming: ["Tech", "Music", "Education", "Entertainment"],
  Education: ["Tech", "Finance", "Gaming", "Business"],
  Finance: ["Tech", "Education", "Business"],
  Business: ["Finance", "Education"],
  Food: ["Travel", "Fitness", "Lifestyle"],
  Travel: ["Food", "Lifestyle", "Adventure"],
  Fitness: ["Food", "Health", "Lifestyle"],
  Health: ["Fitness", "Food", "Lifestyle"],
  Beauty: ["Fashion", "Lifestyle", "Fitness"],
  Fashion: ["Beauty", "Lifestyle"],
  Lifestyle: ["Beauty", "Travel", "Food", "Fashion", "Fitness", "Health"],
  Music: ["Gaming", "Entertainment", "Comedy"],
  Comedy: ["Entertainment", "Music"],
  Entertainment: ["Comedy", "Music", "Gaming"],
  Adventure: ["Travel"],
  Kids: [],
};

/** Format compatibility groups. Same group = highly swappable. */
const FORMAT_GROUP: Record<Format, string> = {
  "Shorts swap": "short",
  "Reels swap": "short",
  "TikTok swap": "short",
  "Long-form guest": "long",
  "Series collab": "long",
  "Live stream": "live",
  Giveaway: "promo",
};

export interface ScoreBreakdownItem {
  label: string;
  weight: number;
  value: number;
}

export interface ScoreResult {
  score: number;
  breakdown: ScoreBreakdownItem[];
  reason: string;
  mutualBenefitTag: string;
}

export interface ScoreOptions {
  /**
   * Semantic audience/content similarity in [0,1] (e.g. embedding cosine).
   * When omitted, a token/niche heuristic is used instead. Drives the
   * inverted-U Complementarity dimension.
   */
  overlapSimilarity?: number;
}

/** Realism gate configuration. */
export const REALISM = {
  /** Candidate subscribers must be within [min, max] x the source's. */
  minSubRatio: 0.2,
  maxSubRatio: 5,
  /** Drop channels with no upload in this many days (when recency is known). */
  maxInactiveDays: 365,
} as const;

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function norm(value: string | undefined): string {
  return (value ?? "").trim().toLowerCase();
}

function clamp(n: number, lo = 0, hi = 100): number {
  return Math.max(lo, Math.min(hi, n));
}

/** Gaussian bump: 1 at `peak`, decaying with `spread`. Returns 0..1. */
function bump(x: number, peak: number, spread: number): number {
  const d = (x - peak) / spread;
  return Math.exp(-0.5 * d * d);
}

function isAdjacent(sourceNiche: string, candNiche: string): boolean {
  return (ADJACENT_NICHES[sourceNiche] ?? []).map(norm).includes(norm(candNiche));
}

function tokenize(values: (string | undefined)[]): Set<string> {
  const out = new Set<string>();
  for (const v of values) {
    for (const part of norm(v).split(/[^a-z0-9]+/g)) {
      if (part.length >= 3) out.add(part);
    }
  }
  return out;
}

function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let inter = 0;
  for (const t of a) if (b.has(t)) inter += 1;
  const union = a.size + b.size - inter;
  return union === 0 ? 0 : inter / union;
}

/**
 * Heuristic audience/content similarity in [0,1] from niche + topics.
 * Used when a semantic `overlapSimilarity` is not supplied.
 */
export function heuristicSimilarity(source: ChannelProfile, candidate: ChannelProfile): number {
  const sameNiche = norm(source.niche) === norm(candidate.niche) && norm(source.niche) !== "";
  const adjacent = isAdjacent(source.niche, candidate.niche);
  const nicheSim = sameNiche ? 1 : adjacent ? 0.5 : 0.1;

  const topicSim = jaccard(
    tokenize([source.niche, source.subNiche, ...source.topics, ...(source.contentPillars ?? [])]),
    tokenize([
      candidate.niche,
      candidate.subNiche,
      ...candidate.topics,
      ...(candidate.contentPillars ?? []),
    ]),
  );

  return clamp(0.5 * nicheSim + 0.5 * topicSim, 0, 1);
}

// ---------------------------------------------------------------------------
// dimension scorers (each returns 0..100)
// ---------------------------------------------------------------------------

/** Same niche is good; adjacent is the collaboration sweet spot; unrelated is weak. */
function relevanceValue(source: ChannelProfile, candidate: ChannelProfile): number {
  if (norm(source.niche) && norm(source.niche) === norm(candidate.niche)) return 90;
  if (isAdjacent(source.niche, candidate.niche)) return 100;
  return 25;
}

/** Inverted-U on audience similarity: reward adjacent, penalise clones and irrelevance. */
function complementarityValue(similarity: number): number {
  return Math.round(clamp(100 * bump(similarity, 0.45, 0.28)));
}

/** Inverted-U on subscriber ratio (log scale): favour comparable / slightly larger. */
function sizeFitValue(sourceFollowers: number, candFollowers: number): number {
  if (sourceFollowers <= 0 || candFollowers <= 0) return 50;
  const lr = Math.log10(candFollowers / sourceFollowers);
  // Peak at ~1.5x (log10(1.5) ~= 0.176); wide enough to stay generous 1x-3x.
  return Math.round(clamp(100 * bump(lr, 0.176, 0.5)));
}

/**
 * Reach quality from avg views: rewards (a) real reach relative to subs and
 * (b) comparable reach scale to the source. Neutral when avg views unknown.
 */
function reachValue(source: ChannelProfile, candidate: ChannelProfile): number {
  const srcAvg = source.medianViews ?? source.avgViews;
  const candAvg = candidate.medianViews ?? candidate.avgViews;
  if (!candAvg || candAvg <= 0) return 50;

  // Health: avg views per subscriber (YT healthy ~0.05-0.30).
  const health = candidate.followers > 0 ? Math.min(1, candAvg / candidate.followers / 0.15) : 0.5;

  // Scale similarity to the source's reach (balanced swap).
  const scaleSim = srcAvg && srcAvg > 0 ? bump(Math.log10(candAvg / srcAvg), 0.176, 0.6) : 0.6;

  return Math.round(clamp(100 * (0.5 * health + 0.5 * scaleSim)));
}

/** Same primary language is strongly preferred; English is a soft lingua franca. */
function languageValue(sourceLang: string | undefined, candLang: string | undefined): number {
  const a = norm(sourceLang);
  const b = norm(candLang);
  if (!a || !b) return 60; // unknown -> neutral-ish
  if (a === b) return 100;
  if (a === "en" || b === "en") return 45; // partial audience via English
  return 20;
}

/** Engagement rate -> 0..100 (YT ~4-8% is excellent). Neutral when unknown. */
function engagementValue(engagementPct: number | undefined): number {
  if (engagementPct === undefined) return 50;
  return Math.round(clamp(engagementPct * 14));
}

/** Recency + cadence -> activity score. Neutral when recency unknown. */
function activityValue(candidate: ChannelProfile): number {
  if (!candidate.lastUploadAt) return 50;
  const days = (Date.now() - Date.parse(candidate.lastUploadAt)) / (1000 * 60 * 60 * 24);
  const recency = Number.isNaN(days) ? 0.5 : Math.max(0, Math.min(1, 1 - days / 365));

  const cadence = candidate.uploadsPerMonth;
  let cadenceScore = 0.6;
  if (cadence !== undefined) {
    if (cadence < 0.5) cadenceScore = 0.3;
    else if (cadence <= 12) cadenceScore = 1;
    else if (cadence <= 30) cadenceScore = 0.85;
    else cadenceScore = 0.6; // very high volume can signal spam/low-effort
  }

  return Math.round(clamp(100 * (0.6 * recency + 0.4 * cadenceScore)));
}

/** Format swappability. */
function formatValue(myFormat: Format, candFormat: Format): number {
  if (myFormat === candFormat) return 100;
  if (FORMAT_GROUP[myFormat] === FORMAT_GROUP[candFormat]) return 80;
  if (FORMAT_GROUP[myFormat] === "promo" || FORMAT_GROUP[candFormat] === "promo") return 60;
  return 35;
}

/** Brand-safety multiplier from red flags (mild, never zeroes a score). */
function brandSafetyMultiplier(candidate: ChannelProfile): number {
  const flags = candidate.redFlags?.length ?? 0;
  if (flags === 0) return 1;
  return Math.max(0.6, 1 - 0.12 * flags);
}

const WEIGHTS = {
  Relevance: 20,
  Complementarity: 18,
  "Audience Size": 18,
  Reach: 12,
  Language: 10,
  Engagement: 8,
  Activity: 8,
  Format: 6,
} as const;

type DimensionLabel = keyof typeof WEIGHTS;

function tierRank(followers: number): number {
  return { micro: 0, mid: 1, large: 2, mega: 3 }[audienceTier(followers)];
}

function mutualTag(source: ChannelProfile, candidate: ChannelProfile, relevance: number): string {
  const srcRank = tierRank(source.followers);
  const candRank = tierRank(candidate.followers);
  const reachWord =
    candRank > srcRank
      ? "Reach booster — taps a larger audience"
      : candRank < srcRank
        ? "Rising partner — high-engagement upside"
        : "Equal partner — balanced mutual exposure";
  const nicheWord =
    relevance >= 100 ? "adjacent niche" : relevance >= 90 ? "same niche" : "cross-niche";
  return `${reachWord} (${nicheWord})`;
}

// ---------------------------------------------------------------------------
// public API
// ---------------------------------------------------------------------------

/**
 * Whether a candidate is a realistic, worth-showing collaborator for the
 * source: comparable size band + still active. Applied before scoring.
 */
export function passesRealismGate(source: ChannelProfile, candidate: ChannelProfile): boolean {
  if (source.followers > 0 && candidate.followers > 0) {
    const ratio = candidate.followers / source.followers;
    if (ratio < REALISM.minSubRatio || ratio > REALISM.maxSubRatio) return false;
  }
  if (candidate.lastUploadAt) {
    const days = (Date.now() - Date.parse(candidate.lastUploadAt)) / (1000 * 60 * 60 * 24);
    if (!Number.isNaN(days) && days > REALISM.maxInactiveDays) return false;
  }
  return true;
}

/** Score a single candidate against the source creator's profile. */
export function scoreCreator(
  source: ChannelProfile,
  candidate: ChannelProfile,
  opts: ScoreOptions = {},
): ScoreResult {
  const similarity = opts.overlapSimilarity ?? heuristicSimilarity(source, candidate);
  const relevance = relevanceValue(source, candidate);

  const values: Record<DimensionLabel, number> = {
    Relevance: relevance,
    Complementarity: complementarityValue(similarity),
    "Audience Size": sizeFitValue(source.followers, candidate.followers),
    Reach: reachValue(source, candidate),
    Language: languageValue(source.language, candidate.language),
    Engagement: engagementValue(candidate.engagementPct),
    Activity: activityValue(candidate),
    Format: formatValue(source.format, candidate.format),
  };

  const breakdown: ScoreBreakdownItem[] = (Object.keys(WEIGHTS) as DimensionLabel[]).map(
    (label) => ({ label, weight: WEIGHTS[label], value: values[label] }),
  );

  const weighted = breakdown.reduce((sum, b) => sum + (b.value * b.weight) / 100, 0);
  const score = Math.round(clamp(weighted * brandSafetyMultiplier(candidate)));

  const strengths = breakdown
    .filter((b) => b.value >= 75)
    .sort((a, b) => b.value * b.weight - a.value * a.weight)
    .slice(0, 3)
    .map((b) => b.label.toLowerCase());
  const reason =
    strengths.length > 0
      ? `Strong on ${strengths.join(", ")}.`
      : "Limited overlap — explore only if the angle is compelling.";

  return {
    score,
    breakdown,
    reason,
    mutualBenefitTag: mutualTag(source, candidate, relevance),
  };
}
