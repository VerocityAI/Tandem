/**
 * Rule-based collaboration scorer.
 *
 * Philosophy (the "why creators collaborate" model):
 *   Creators collaborate to (1) reach NEW but ADJACENT audiences, (2) swap
 *   complementary content, and (3) partner with someone of comparable standing
 *   so the exchange is mutually valuable. So the scorer rewards:
 *     - same OR adjacent niche (not random unrelated niches)
 *     - audience parity (similar tier / follower band)
 *     - meaningful topic overlap (shared relevance) without demanding clones
 *     - compatible / complementary collaboration formats
 *     - same or nearby region (logistics + audience relevance)
 *     - healthy engagement and reach (a partner worth collaborating with)
 *
 * The output `breakdown` is consumed verbatim by the mobile UI
 * (label, weight, value[0..100]).
 */

import type { ChannelProfile, Format, Platform } from "@tandem/shared-types";

export type AudienceTier = "micro" | "mid" | "large" | "mega";

/**
 * Bucket a follower count into a tier.
 *   micro: < 100k, mid: < 500k, large: < 1M, mega: >= 1M
 */
export function audienceTier(followers: number): AudienceTier {
  if (followers < 100_000) return "micro";
  if (followers < 500_000) return "mid";
  if (followers < 1_000_000) return "large";
  return "mega";
}

const TIER_RANK: Record<AudienceTier, number> = {
  micro: 0,
  mid: 1,
  large: 2,
  mega: 3,
};

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

export interface ScoreInputs {
  myNiche: string;
  myTier: AudienceTier;
  myFollowers?: number;
  myRegion: string;
  myFormat: Format;
  myTopics: string[];
  myPlatform: Platform;
  myViews?: number;
}

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

function norm(value: string | undefined): string {
  return (value ?? "").trim().toLowerCase();
}

function nicheValue(myNiche: string, candNiche: string): number {
  const mine = norm(myNiche);
  const theirs = norm(candNiche);
  if (mine && theirs && mine === theirs) return 100;
  const adjacents = (ADJACENT_NICHES[myNiche] ?? []).map(norm);
  if (adjacents.includes(theirs)) return 80;
  return 25;
}

function audienceValue(myTier: AudienceTier, candFollowers: number): number {
  const dist = Math.abs(TIER_RANK[myTier] - TIER_RANK[audienceTier(candFollowers)]);
  switch (dist) {
    case 0:
      return 100;
    case 1:
      return 65;
    case 2:
      return 35;
    default:
      return 15;
  }
}

function topicValue(myTopics: string[], candTopics: string[]): number {
  const a = new Set(myTopics.map(norm).filter(Boolean));
  const b = new Set(candTopics.map(norm).filter(Boolean));
  if (a.size === 0 || b.size === 0) return 40;
  let overlap = 0;
  for (const t of a) if (b.has(t)) overlap += 1;
  return Math.min(100, Math.round((100 * overlap) / Math.min(a.size, b.size)));
}

function regionValue(myRegion: string, candRegion: string): number {
  const mine = norm(myRegion);
  const theirs = norm(candRegion);
  if (mine && theirs && mine === theirs) return 100;
  if (mine === "global" || theirs === "global") return 70;
  return 30;
}

function formatValue(myFormat: Format, candFormat: Format): number {
  if (myFormat === candFormat) return 100;
  if (FORMAT_GROUP[myFormat] === FORMAT_GROUP[candFormat]) return 80;
  // Giveaways pair with anything; otherwise loosely complementary.
  if (FORMAT_GROUP[myFormat] === "promo" || FORMAT_GROUP[candFormat] === "promo") return 60;
  return 35;
}

function growthValue(myFollowers: number | undefined, candFollowers: number): number {
  if (!myFollowers || myFollowers <= 0 || candFollowers <= 0) return 50;
  const ratio = candFollowers / myFollowers;
  // Equal -> 50; larger partner (more reach to gain) trends up; smaller trends down.
  const v = 50 + 25 * Math.log10(ratio);
  return Math.max(0, Math.min(100, Math.round(v)));
}

function engagementValue(engagementPct: number | undefined): number {
  if (engagementPct === undefined) return 50;
  return Math.max(0, Math.min(100, Math.round(engagementPct * 10)));
}

function platformValue(myPlatform: Platform, candPlatform: Platform): number {
  return myPlatform === candPlatform ? 100 : 70;
}

const WEIGHTS = {
  Niche: 20,
  "Audience Fit": 20,
  Topics: 20,
  Region: 10,
  Format: 10,
  Growth: 10,
  Engagement: 5,
  Platform: 5,
} as const;

function mutualTag(myTier: AudienceTier, candFollowers: number, nicheVal: number): string {
  const myRank = TIER_RANK[myTier];
  const candRank = TIER_RANK[audienceTier(candFollowers)];
  const reachWord =
    candRank > myRank
      ? "Reach booster — taps a larger audience"
      : candRank < myRank
        ? "Rising partner — high-engagement upside"
        : "Equal partner — balanced mutual exposure";
  const nicheWord =
    nicheVal >= 100 ? "same niche" : nicheVal >= 80 ? "adjacent niche" : "cross-niche";
  return `${reachWord} (${nicheWord})`;
}

/** Score a single candidate against the source creator's inputs. */
export function scoreCreator(inputs: ScoreInputs, candidate: ChannelProfile): ScoreResult {
  const values: Record<keyof typeof WEIGHTS, number> = {
    Niche: nicheValue(inputs.myNiche, candidate.niche),
    "Audience Fit": audienceValue(inputs.myTier, candidate.followers),
    Topics: topicValue(inputs.myTopics, candidate.topics),
    Region: regionValue(inputs.myRegion, candidate.region),
    Format: formatValue(inputs.myFormat, candidate.format),
    Growth: growthValue(inputs.myFollowers, candidate.followers),
    Engagement: engagementValue(candidate.engagementPct),
    Platform: platformValue(inputs.myPlatform, candidate.ref.platform),
  };

  const breakdown: ScoreBreakdownItem[] = (
    Object.keys(WEIGHTS) as Array<keyof typeof WEIGHTS>
  ).map((label) => ({
    label,
    weight: WEIGHTS[label],
    value: values[label],
  }));

  const weighted = breakdown.reduce((sum, b) => sum + (b.value * b.weight) / 100, 0);
  const score = Math.max(0, Math.min(100, Math.round(weighted)));

  // Build a short human reason from the strongest dimensions.
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
    mutualBenefitTag: mutualTag(inputs.myTier, candidate.followers, values.Niche),
  };
}
