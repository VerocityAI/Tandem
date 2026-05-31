/**
 * Lightweight, deterministic heuristics used when AI enrichment is unavailable
 * or as the raw base profile before Gemini refines it.
 *
 * These are intentionally conservative: they read the channel's free text
 * (title + description + keywords + topic categories) and infer a coarse
 * niche, region, format, and topic list. AI enrichment (see prompts.ts)
 * overrides these when it succeeds.
 */

import type { Format } from "@tandem/shared-types";

function lc(text: string): string {
  return (text ?? "").toLowerCase();
}

/** niche label -> keywords that signal it. First match (by declaration order) wins. */
const NICHE_KEYWORDS: Array<[string, string[]]> = [
  ["Kids", ["nursery", "rhymes", "toddler", "preschool", "kids", "cocomelon", "lullaby", "for children"]],
  ["Gaming", ["gaming", "gameplay", "playthrough", "esports", "minecraft", "fortnite", "speedrun", "twitch"]],
  ["Tech", ["tech", "technology", "gadget", "smartphone", "unboxing", "review", "software", "hardware", "ai", "coding", "developer"]],
  ["Finance", ["finance", "investing", "stocks", "crypto", "trading", "money", "personal finance", "wealth", "budget"]],
  ["Education", ["education", "tutorial", "course", "learn", "study", "explainer", "lecture", "how to"]],
  ["Fitness", ["fitness", "workout", "gym", "bodybuilding", "training", "exercise", "calisthenics"]],
  ["Health", ["health", "wellness", "nutrition", "mental health", "meditation", "diet"]],
  ["Beauty", ["beauty", "makeup", "skincare", "cosmetics", "grwm"]],
  ["Fashion", ["fashion", "outfit", "style", "ootd", "haul", "streetwear"]],
  ["Food", ["food", "cooking", "recipe", "chef", "baking", "kitchen", "restaurant", "foodie", "mukbang"]],
  ["Travel", ["travel", "vlog", "adventure", "wanderlust", "destination", "backpacking", "tourism"]],
  ["Music", ["music", "song", "cover", "guitar", "piano", "producer", "beats", "singer", "band"]],
  ["Comedy", ["comedy", "funny", "sketch", "prank", "humor", "standup", "satire"]],
  ["Entertainment", ["entertainment", "reaction", "celebrity", "movies", "film review", "tv show"]],
  ["Business", ["business", "entrepreneur", "startup", "marketing", "saas", "ecommerce"]],
  ["Lifestyle", ["lifestyle", "daily vlog", "routine", "minimalism", "productivity", "home"]],
];

/** Infer a coarse niche label from free text. Defaults to "Lifestyle". */
export function inferNiche(text: string): string {
  const t = lc(text);
  for (const [niche, keywords] of NICHE_KEYWORDS) {
    if (keywords.some((k) => t.includes(k))) return niche;
  }
  return "Lifestyle";
}

/** region keyword -> canonical label. */
const REGION_KEYWORDS: Array<[string, string[]]> = [
  ["UAE", ["uae", "dubai", "abu dhabi", "emirates"]],
  ["India", ["india", "hindi", "mumbai", "delhi", "desi"]],
  ["UK", ["uk", "united kingdom", "london", "british", "england"]],
  ["US", ["usa", "united states", "america", "los angeles", "new york"]],
  ["Saudi Arabia", ["saudi", "riyadh", "jeddah", "ksa"]],
  ["Canada", ["canada", "toronto", "vancouver"]],
  ["Australia", ["australia", "sydney", "melbourne", "aussie"]],
  ["Philippines", ["philippines", "manila", "pinoy", "filipino"]],
];

/** Infer a region from free text. Defaults to "Global". */
export function inferRegion(text: string): string {
  const t = lc(text);
  for (const [region, keywords] of REGION_KEYWORDS) {
    if (keywords.some((k) => t.includes(k))) return region;
  }
  return "Global";
}

/** Infer a collaboration format from free text + niche. */
export function inferFormat(text: string, niche: string): Format {
  const t = lc(text);
  if (t.includes("tiktok")) return "TikTok swap";
  if (t.includes("reel") || t.includes("instagram")) return "Reels swap";
  if (t.includes("short")) return "Shorts swap";
  if (t.includes("giveaway") || t.includes("contest")) return "Giveaway";
  if (t.includes("live") || t.includes("stream")) return "Live stream";
  if (t.includes("series") || t.includes("collab")) return "Series collab";
  if (t.includes("podcast") || t.includes("interview") || t.includes("guest")) {
    return "Long-form guest";
  }
  // Niche defaults: short-form-heavy niches lean to Shorts; talky niches to long-form.
  if (["Comedy", "Music", "Beauty", "Fashion", "Food"].includes(niche)) return "Shorts swap";
  return "Long-form guest";
}

/** Per-niche seed topics, used when no better signal exists. */
const NICHE_TOPICS: Record<string, string[]> = {
  Tech: ["reviews", "gadgets", "tutorials", "ai"],
  Gaming: ["gameplay", "reviews", "esports", "livestream"],
  Finance: ["investing", "markets", "personal-finance", "crypto"],
  Education: ["tutorials", "explainers", "study-tips"],
  Fitness: ["workouts", "nutrition", "training"],
  Health: ["wellness", "nutrition", "mindfulness"],
  Beauty: ["makeup", "skincare", "tutorials"],
  Fashion: ["outfits", "style", "hauls"],
  Food: ["recipes", "cooking", "restaurant-reviews"],
  Travel: ["destinations", "vlogs", "guides"],
  Music: ["covers", "production", "performances"],
  Comedy: ["sketches", "reactions", "pranks"],
  Entertainment: ["reactions", "reviews", "commentary"],
  Business: ["marketing", "startups", "strategy"],
  Lifestyle: ["vlogs", "routines", "tips"],
  Kids: ["nursery-rhymes", "songs", "learning"],
};

const STOPWORDS = new Set([
  "the", "and", "for", "with", "this", "that", "from", "your", "you", "our",
  "are", "was", "all", "new", "out", "get", "have", "has", "will", "can",
  "channel", "subscribe", "video", "videos", "youtube", "official", "welcome",
  "watch", "like", "share", "more", "best", "every", "week", "day", "here",
]);

/** Derive a topic list from text, seeded by the niche's default topics. */
export function topicsForNiche(text: string, niche: string): string[] {
  const seed = NICHE_TOPICS[niche] ?? [];
  const topics = new Set<string>(seed);
  const words = lc(text)
    .split(/[^a-z0-9]+/g)
    .filter((w) => w.length >= 5 && w.length <= 18 && !STOPWORDS.has(w));
  for (const w of words) {
    if (topics.size >= 12) break;
    topics.add(w);
  }
  return [...topics].slice(0, 12);
}
