/**
 * Gemini prompt builders + response schemas.
 *
 * Three AI tasks:
 *   1. Profile enrichment  — turn raw channel data into a collaboration-ready
 *      profile (niche, ideal collaborator, brand safety, red flags...).
 *   2. Match rerank        — re-rank rule-scored candidates by genuine
 *      collaboration value (audience growth, adjacency, complementarity).
 *   3. Outreach draft      — write a short, personalised outreach message.
 */

import { z } from "zod";

import {
  type ChannelProfile,
  type Comment,
  type Format,
  type Platform,
  type Post,
  ConfidenceSchema,
  ContactsSchema,
  FormatSchema,
  RerankResponseSchema,
} from "@cohyve/shared-types";

// ---------------------------------------------------------------------------
// 1. Profile enrichment
// ---------------------------------------------------------------------------

export const AiProfileSchema = z.object({
  niche: z.string().optional(),
  subNiche: z.string().optional(),
  region: z.string().optional(),
  format: FormatSchema.optional(),
  topics: z.array(z.string()).max(20).optional(),
  toneTags: z.array(z.string()).max(10).optional(),
  contentPillars: z.array(z.string()).max(10).optional(),
  audiencePersona: z.string().max(500).optional(),
  brandSafetyNotes: z.string().max(500).optional(),
  idealCollaboratorProfile: z.string().max(500).optional(),
  redFlags: z.array(z.string()).max(10).optional(),
  confidence: ConfidenceSchema.optional(),
});
export type AiProfile = z.infer<typeof AiProfileSchema>;

const VALID_FORMATS: Format[] = [
  "Shorts swap",
  "Long-form guest",
  "Live stream",
  "Series collab",
  "Giveaway",
  "Reels swap",
  "TikTok swap",
];

export function buildProfilePrompt(
  baseProfile: ChannelProfile,
  posts: Post[],
  comments: Comment[],
): string {
  const postLines = posts
    .slice(0, 15)
    .map((p) => `- ${p.title ?? "(untitled)"}${p.description ? `: ${p.description.slice(0, 120)}` : ""}`)
    .join("\n");
  const commentLines = comments
    .slice(0, 10)
    .map((c) => `- ${c.text.slice(0, 140)}`)
    .join("\n");

  return [
    "You are a creator-collaboration analyst. Profile this social channel so it",
    "can be matched with the best COLLABORATION partners. Base your judgement on",
    "the channel name, description, recent post titles, and audience comments —",
    "NOT on guesswork. If signal is weak, set confidence to \"Low\".",
    "",
    `Platform: ${baseProfile.ref.platform}`,
    `Name: ${baseProfile.name}`,
    `Followers: ${baseProfile.followers}`,
    `Description: ${baseProfile.description.slice(0, 600) || "(none)"}`,
    "",
    "Recent posts:",
    postLines || "(none available)",
    "",
    "Top audience comments:",
    commentLines || "(none available)",
    "",
    "Return ONLY a JSON object with these fields (omit any you cannot infer):",
    "  niche: one concise label — ALWAYS provide your single best guess (e.g. Tech,",
    "    Food, Gaming, Finance, Education, Fitness, Beauty, Fashion, Travel, Music,",
    "    Comedy, Entertainment, Business, Lifestyle, Kids)",
    "  subNiche: a more specific descriptor",
    "  region: primary audience region, or \"Global\"",
    `  format: one of ${VALID_FORMATS.map((f) => `\"${f}\"`).join(", ")}`,
    "  topics: 3-10 short topic tags",
    "  toneTags: 2-5 tone descriptors (e.g. educational, energetic)",
    "  contentPillars: 2-5 recurring content themes",
    "  audiencePersona: one sentence describing the typical viewer",
    "  idealCollaboratorProfile: one sentence on who would be a great collab partner",
    "  brandSafetyNotes: any advertiser/brand-safety concerns, or \"None noted\"",
    "  redFlags: array of concerns that would make collaboration risky (empty if none)",
    "  confidence: one of \"Low\", \"Medium\", \"High\"",
  ].join("\n");
}

// ---------------------------------------------------------------------------
// 2. Match rerank
// ---------------------------------------------------------------------------

export interface RerankCandidate {
  channelKey: string;
  name: string;
  platform: Platform;
  niche: string;
  subNiche?: string;
  region: string;
  language?: string;
  followers: number;
  avgViews?: number;
  engagementPct?: number;
  uploadsPerMonth?: number;
  format: Format;
  topics: string[];
  contentPillars?: string[];
  description: string;
  ruleScore: number;
}

export const RerankSchema = RerankResponseSchema;
export type Rerank = z.infer<typeof RerankSchema>;

export function buildRerankPrompt(
  source: ChannelProfile,
  candidates: RerankCandidate[],
): string {
  const candLines = candidates
    .map((c, i) => {
      const facts = [
        `niche=${c.niche}${c.subNiche ? `/${c.subNiche}` : ""}`,
        `region=${c.region}`,
        c.language ? `lang=${c.language}` : "",
        `subs=${c.followers}`,
        c.avgViews !== undefined ? `avgViews=${c.avgViews}` : "",
        c.engagementPct !== undefined ? `eng=${c.engagementPct}%` : "",
        c.uploadsPerMonth !== undefined ? `uploads/mo=${c.uploadsPerMonth}` : "",
        `format=${c.format}`,
        `topics=[${c.topics.slice(0, 6).join(", ")}]`,
        c.contentPillars && c.contentPillars.length > 0
          ? `pillars=[${c.contentPillars.slice(0, 4).join(", ")}]`
          : "",
        `ruleScore=${c.ruleScore}`,
      ]
        .filter(Boolean)
        .join(" | ");
      return `${i + 1}. key=${c.channelKey} | ${c.name} | ${c.platform} | ${facts}\n   desc: ${c.description.slice(0, 160)}`;
    })
    .join("\n");

  return [
    "You are matching YouTube creators for mutually beneficial COLLABORATIONS.",
    "A great collaboration:",
    "  - reaches a NEW but ADJACENT audience (relevant, but NOT an identical",
    "    audience the source already has — clones add no incremental reach);",
    "  - pairs creators of comparable-or-slightly-larger standing (realistically",
    "    landable — penalise large subscriber gaps);",
    "  - shares the same primary LANGUAGE (audience transfer needs a shared language);",
    "  - partners with an ACTIVE, engaged, brand-safe channel with real reach",
    "    (avg views matter more than vanity subscriber counts).",
    "Penalise: identical/near-duplicate audiences, unrelated niches, big size",
    "mismatches, language mismatches, inactive channels, and brand-safety risks.",
    "",
    "SOURCE creator:",
    `  Name: ${source.name}`,
    `  Niche: ${source.niche}${source.subNiche ? ` / ${source.subNiche}` : ""}`,
    `  Region: ${source.region} | Language: ${source.language ?? "unknown"} | Subs: ${source.followers} | Format: ${source.format}`,
    source.medianViews ?? source.avgViews
      ? `  Avg views: ${source.medianViews ?? source.avgViews}`
      : "",
    `  Topics: ${source.topics.join(", ")}`,
    source.idealCollaboratorProfile ? `  Ideal partner: ${source.idealCollaboratorProfile}` : "",
    "",
    "CANDIDATES:",
    candLines,
    "",
    "Score each candidate 0-100 on genuine collaboration value (NOT just",
    "similarity). Return ONLY JSON of the form:",
    '{ "matches": [ { "channelKey": "...", "aiScore": 0-100, "rationale": "2-3 sentences on why this is (or isn\'t) a strong collaborator", "suggestedCollab": "a concrete collab idea", "risks": ["..."] } ] }',
    "Include every candidate's channelKey exactly as given.",
  ]
    .filter(Boolean)
    .join("\n");
}

// ---------------------------------------------------------------------------
// 3. Outreach draft
// ---------------------------------------------------------------------------

export const OutreachSchema = z.object({
  subject: z.string().max(160),
  message: z.string().max(1500),
  talkingPoints: z.array(z.string()).max(6).default([]),
  callToAction: z.string().max(200).optional(),
});
export type Outreach = z.infer<typeof OutreachSchema>;

// Extended outreach with contact information and delivery options
export const OutreachWithContactsSchema = z.object({
  subject: z.string().max(160),
  message: z.string().max(1500),
  talkingPoints: z.array(z.string()).max(6).default([]),
  callToAction: z.string().max(200).optional(),
  contacts: ContactsSchema.optional(),
  preferredMethod: z
    .object({
      method: z.string(),
      destination: z.string().optional(),
    })
    .optional(),
});
export type OutreachWithContacts = z.infer<typeof OutreachWithContactsSchema>;

export function buildOutreachPrompt(
  from: ChannelProfile,
  to: ChannelProfile,
  angle: string,
): string {
  return [
    "Write a short, warm, specific collaboration outreach message from one",
    "creator to another. Keep it under 120 words, no fluff, no emoji spam.",
    "Reference something concrete about the recipient's content.",
    "",
    `FROM: ${from.name} (${from.ref.platform}, ${from.niche}, ${from.followers} followers)`,
    `TO: ${to.name} (${to.ref.platform}, ${to.niche}, ${to.followers} followers)`,
    `TO description: ${to.description.slice(0, 300)}`,
    `Collaboration angle: ${angle}`,
    "",
    "Return ONLY JSON:",
    '{ "subject": "...", "message": "...", "talkingPoints": ["...", "..."], "callToAction": "...", "contacts": { ... }, "preferredMethod": { "method": "...", "destination": "..." } }',
  ].join("\n");
}
