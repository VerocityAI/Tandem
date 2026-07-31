/**
 * Lightweight, deterministic heuristics used when AI enrichment is unavailable
 * or as the raw base profile before Gemini refines it.
 *
 * These are intentionally conservative: they read the channel's free text
 * (title + description + keywords + topic categories) and infer a coarse
 * niche, region, format, and topic list. AI enrichment (see prompts.ts)
 * overrides these when it succeeds.
 */

import type { Format } from "@cohyve/shared-types";

function lc(text: string): string {
  return (text ?? "").toLowerCase();
}

/** niche label -> keywords that signal it. First match (by declaration order) wins. */
const NICHE_KEYWORDS: Array<[string, string[]]> = [
  ["Kids", ["nursery", "rhymes", "toddler", "preschool", "kids", "cocomelon", "lullaby", "for children"]],
  ["Gaming", ["gaming", "gameplay", "playthrough", "esports", "minecraft", "fortnite", "speedrun", "twitch"]],
  ["Tech", ["tech", "technology", "gadget", "smartphone", "unboxing", "review", "software", "hardware", "ai", "artificial intelligence", "coding", "developer"]],
  ["Finance", ["finance", "investing", "stocks", "crypto", "trading", "money", "personal finance", "wealth", "budget"]],
  ["Education", ["education", "tutorial", "course", "learn", "study", "explainer", "lecture", "how to"]],
  ["Fitness", ["fitness", "workout", "gym", "bodybuilding", "training", "exercise", "calisthenics"]],
  ["Health", ["health", "wellness", "nutrition", "mental health", "meditation", "diet"]],
  ["Beauty", ["beauty", "makeup", "skincare", "cosmetics", "grwm"]],
  ["Fashion", ["fashion", "outfit", "style", "ootd", "haul", "streetwear"]],
  ["Food", ["food", "cooking", "recipe", "chef", "baking", "kitchen", "restaurant", "foodie", "mukbang"]],
  ["Travel", ["travel", "travels", "vlog", "adventure", "wanderlust", "destination", "backpacking", "tourism", "tourist", "walking tour", "city walk", "city walking", "urban exploration", "sightseeing", "landmark", "walking tours"]],
  ["Music", ["music", "song", "cover", "guitar", "piano", "producer", "beats", "singer", "band"]],
  ["Comedy", ["comedy", "funny", "sketch", "prank", "humor", "standup", "satire"]],
  ["Entertainment", ["entertainment", "reaction", "celebrity", "movies", "film review", "tv show"]],
  ["Business", ["business", "entrepreneur", "startup", "marketing", "saas", "ecommerce"]],
  ["Lifestyle", ["lifestyle", "daily vlog", "routine", "minimalism", "productivity", "home"]],
];

/** Escape a keyword for safe embedding in a RegExp. */
function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Whole-word (plural-tolerant) keyword test. Prevents substring false positives
 * like the keyword "ai" matching "tr[ai]ls" or "review" matching "preview".
 */
function hasKeyword(text: string, keyword: string): boolean {
  return new RegExp(`\\b${escapeRe(keyword)}(?:s|es)?\\b`, "i").test(text);
}

/** Infer a coarse niche label from free text. Defaults to "Lifestyle". */
export function inferNiche(text: string): string {
  const t = lc(text);
  for (const [niche, keywords] of NICHE_KEYWORDS) {
    if (keywords.some((k) => hasKeyword(t, k))) return niche;
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

/** Region label -> default ISO 639-1 language, used as a coarse fallback. */
const REGION_LANGUAGE: Record<string, string> = {
  India: "hi",
  UAE: "ar",
  "Saudi Arabia": "ar",
  Philippines: "en",
  UK: "en",
  US: "en",
  Canada: "en",
  Australia: "en",
  Global: "en",
};

/**
 * Coarse language guess from free text + region. Detects non-Latin scripts
 * (Arabic, Devanagari, CJK, Cyrillic) directly; otherwise falls back to the
 * region default, then English. Real signal comes from video audio-language
 * metadata (see computePrimaryLanguage); this is only a last resort.
 */
export function inferLanguage(text: string, region?: string): string {
  const t = text ?? "";
  if (/[\u0600-\u06ff]/.test(t)) return "ar"; // Arabic
  if (/[\u0900-\u097f]/.test(t)) return "hi"; // Devanagari
  if (/[\u3040-\u30ff\u4e00-\u9fff]/.test(t)) return "ja"; // Kana/Han (JP-leaning)
  if (/[\uac00-\ud7af]/.test(t)) return "ko"; // Hangul
  if (/[\u0400-\u04ff]/.test(t)) return "ru"; // Cyrillic
  if (region && REGION_LANGUAGE[region]) return REGION_LANGUAGE[region];
  return "en";
}

/** Infer a collaboration format from free text + niche. */
export function inferFormat(text: string, niche: string): Format {
  const t = lc(text);
  const has = (k: string): boolean => hasKeyword(t, k);
  if (has("tiktok")) return "TikTok swap";
  if (has("reel") || has("instagram")) return "Reels swap";
  if (has("short")) return "Shorts swap";
  if (has("giveaway") || has("contest")) return "Giveaway";
  if (has("live") || has("livestream") || has("stream")) return "Live stream";
  if (has("series") || has("collab")) return "Series collab";
  if (has("podcast") || has("interview") || has("guest")) {
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
