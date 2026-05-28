/** Firestore document shapes shared between server and client. */

import { z } from "zod";
import { PlatformSchema, ChannelProfileSchema } from "./platform.js";

/** `users/{uid}` */
export const UserDocSchema = z.object({
  displayName: z.string().optional(),
  photoURL: z.string().url().optional(),
  email: z.string().email().optional(),
  createdAt: z.string(),
  lastSeenAt: z.string().optional(),
  plan: z.enum(["free", "pro"]).default("free"),
});
export type UserDoc = z.infer<typeof UserDocSchema>;

/** `users/{uid}/connectedChannels/{channelKey}` — many per user, any platform. */
export const ConnectedChannelSchema = z.object({
  channelKey: z.string(),
  platform: PlatformSchema,
  ownership: z.enum(["self", "watching"]).default("watching"),
  addedAt: z.string(),
  lastAnalyzedAt: z.string().optional(),
});
export type ConnectedChannel = z.infer<typeof ConnectedChannelSchema>;

/** `users/{uid}/shortlists/{channelKey}` */
export const ShortlistEntrySchema = z.object({
  channelKey: z.string(),
  platform: PlatformSchema,
  savedAt: z.string(),
  note: z.string().max(500).optional(),
  status: z.enum(["new", "contacted", "replied", "passed"]).default("new"),
});
export type ShortlistEntry = z.infer<typeof ShortlistEntrySchema>;

/** `users/{uid}/outreach/{outreachId}` */
export const OutreachDocSchema = z.object({
  fromChannelKey: z.string(),
  toChannelKey: z.string(),
  text: z.string(),
  createdAt: z.string(),
  status: z.enum(["draft", "sent"]).default("draft"),
});
export type OutreachDoc = z.infer<typeof OutreachDocSchema>;

/** `users/{uid}/usage/{yyyymmdd}` — daily quota counters. */
export const UsageDocSchema = z.object({
  date: z.string(), // yyyy-mm-dd
  analyses: z.number().int().nonnegative().default(0),
  reranks: z.number().int().nonnegative().default(0),
  outreach: z.number().int().nonnegative().default(0),
});
export type UsageDoc = z.infer<typeof UsageDocSchema>;

/** `channels/{channelKey}` — shared cache; clients read-only, server-written. */
export const ChannelDocSchema = ChannelProfileSchema.extend({
  channelKey: z.string(),
  updatedAt: z.string(),
});
export type ChannelDoc = z.infer<typeof ChannelDocSchema>;
