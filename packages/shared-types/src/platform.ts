import { z } from "zod";

/**
 * Supported social platforms. Use string union (not int enum) for readable
 * Firestore docs and stable analytics events. Add new platforms here +
 * implement a server adapter in `functions/src/adapters/<platform>/`.
 */
export const PlatformSchema = z.enum(["youtube", "instagram", "tiktok"]);
export type Platform = z.infer<typeof PlatformSchema>;

/** Stable cross-system key. `channelKey = "<platform>_<externalId>"`. */
export const channelKey = (platform: Platform, externalId: string): string =>
  `${platform}_${externalId}`;

export const ChannelRefSchema = z.object({
  platform: PlatformSchema,
  externalId: z.string().min(1),
  handle: z.string().optional(),
  url: z.string().url().optional(),
});
export type ChannelRef = z.infer<typeof ChannelRefSchema>;

/** A platform post (YouTube video, IG post/reel, TikTok video). */
export const PostSchema = z.object({
  id: z.string(),
  title: z.string().optional(),
  description: z.string().optional(),
  publishedAt: z.string().optional(),
  thumbnailUrl: z.string().url().optional(),
  views: z.number().int().nonnegative().optional(),
  likes: z.number().int().nonnegative().optional(),
  comments: z.number().int().nonnegative().optional(),
  tags: z.array(z.string()).optional(),
  /** BCP-47 / ISO 639-1 language of the post's audio or metadata, when known. */
  language: z.string().optional(),
});
export type Post = z.infer<typeof PostSchema>;

export const CommentSchema = z.object({
  id: z.string(),
  postId: z.string(),
  author: z.string().optional(),
  text: z.string(),
  likeCount: z.number().int().nonnegative().optional(),
});
export type Comment = z.infer<typeof CommentSchema>;

/** Niches kept flexible — strings so platforms can add new ones without a migration. */
export const NicheSchema = z.string();
export const RegionSchema = z.string();

export const ConfidenceSchema = z.enum(["Low", "Medium", "High", "Demo"]);
export type Confidence = z.infer<typeof ConfidenceSchema>;

/** Cross-platform format compatibility groups — used by the scorer. */
export const FormatSchema = z.enum([
  "Shorts swap",
  "Long-form guest",
  "Live stream",
  "Series collab",
  "Giveaway",
  "Reels swap", // IG-leaning analogue to Shorts swap
  "TikTok swap",
]);
export type Format = z.infer<typeof FormatSchema>;

/** Public contact points parsed from a creator's descriptions. */
export const ContactsSchema = z.object({
  email: z.string().optional(),
  instagram: z.string().optional(),
  tiktok: z.string().optional(),
  twitter: z.string().optional(),
  discord: z.string().optional(),
  website: z.string().optional(),
  other: z.array(z.string()).max(8).optional(),
});
export type Contacts = z.infer<typeof ContactsSchema>;

/**
 * The unified, platform-agnostic profile that downstream code (UI, scorer, prompts) consumes.
 * Raw platform-specific data is stashed in `raw` for debugging only.
 */
export const ChannelProfileSchema = z.object({
  ref: ChannelRefSchema,
  name: z.string(),
  description: z.string(),
  /** Channel avatar/thumbnail URL from the platform (for display). */
  thumbnailUrl: z.string().url().optional(),
  followers: z.number().int().nonnegative(),
  views: z.number().int().nonnegative().optional(),
  posts: z.number().int().nonnegative().optional(),
  engagementPct: z.number().nonnegative().optional(),
  /** Mean views across recent posts — the real reach proxy (subs can be stale/vanity). */
  avgViews: z.number().int().nonnegative().optional(),
  /** Median views across recent posts — robust to viral outliers. */
  medianViews: z.number().int().nonnegative().optional(),
  /** Upload cadence: posts per 30 days over the recent window. */
  uploadsPerMonth: z.number().nonnegative().optional(),
  /** ISO timestamp of the most recent upload (activity/recency signal). */
  lastUploadAt: z.string().optional(),
  /** Primary content language (ISO 639-1, e.g. "en") — key for audience transfer. */
  language: z.string().optional(),
  /** Cached semantic embedding of the profile text, for complementarity scoring. */
  embedding: z.array(z.number()).optional(),
  region: RegionSchema,
  niche: NicheSchema,
  subNiche: z.string().optional(),
  format: FormatSchema,
  topics: z.array(z.string()).max(20),
  toneTags: z.array(z.string()).max(10).optional(),
  contentPillars: z.array(z.string()).max(10).optional(),
  audiencePersona: z.string().max(500).optional(),
  brandSafetyNotes: z.string().max(500).optional(),
  idealCollaboratorProfile: z.string().max(500).optional(),
  redFlags: z.array(z.string()).max(10).optional(),
  /** Public contact info parsed from the channel/video descriptions. */
  contacts: ContactsSchema.optional(),
  confidence: ConfidenceSchema,
  sourceSnapshotAt: z.string(), // ISO timestamp
  // Optional raw payload, opaque to the rest of the system.
  raw: z.unknown().optional(),
});
export type ChannelProfile = z.infer<typeof ChannelProfileSchema>;

/** Search input used by `searchCandidates` (kept simple in v1). */
export const SearchQuerySchema = z.object({
  text: z.string().optional(),
  niche: z.string().optional(),
  region: z.string().optional(),
  minFollowers: z.number().int().nonnegative().optional(),
  maxFollowers: z.number().int().nonnegative().optional(),
  limit: z.number().int().min(1).max(50).default(10),
});
export type SearchQuery = z.infer<typeof SearchQuerySchema>;

/**
 * Implementations live in `functions/src/adapters/<platform>/`.
 * The IG and TikTok adapters in v1 ship as STUBS that implement `parseInput`
 * (so paste-detection works) but throw `NotImplementedError` from any network method.
 */
export interface PlatformAdapter {
  readonly platform: Platform;

  /** Pure, no network. Returns a ChannelRef if `text` looks like a URL/handle on this platform. */
  parseInput(text: string): ChannelRef | null;

  /** Fetches and returns a unified profile (no AI enrichment — that runs after, centrally). */
  fetchProfile(ref: ChannelRef): Promise<ChannelProfile>;

  fetchRecentPosts(ref: ChannelRef, limit: number): Promise<Post[]>;

  fetchTopComments(ref: ChannelRef, postIds: string[]): Promise<Comment[]>;

  searchCandidates(query: SearchQuery): Promise<ChannelRef[]>;
}

/** Thrown by stub adapters in v1; surfaced as a typed Functions error. */
export class NotImplementedError extends Error {
  readonly code = "not-implemented" as const;
  constructor(platform: Platform, op: string) {
    super(`${platform} adapter does not implement ${op} yet`);
    this.name = "NotImplementedError";
  }
}

export interface PlatformRegistry {
  get(p: Platform): PlatformAdapter;
  all(): PlatformAdapter[];
  /** Try every adapter's parseInput, return the first match. Pure, no network. */
  detect(text: string): ChannelRef | null;
}

// ----------------- AI rerank wire types -----------------

export const AiMatchSchema = z.object({
  channelKey: z.string(),
  aiScore: z.number().min(0).max(100),
  rationale: z.string().max(600),
  suggestedCollab: z.string().max(300),
  risks: z.array(z.string()).max(5).default([]),
});
export type AiMatch = z.infer<typeof AiMatchSchema>;

export const RerankResponseSchema = z.object({
  matches: z.array(AiMatchSchema).max(12),
});
export type RerankResponse = z.infer<typeof RerankResponseSchema>;
