import { getFirestore } from "firebase-admin/firestore";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";

import { ChannelProfileSchema, ContactsSchema } from "@cohyve/shared-types";

import {
  GEMINI_API_KEY,
  MODEL_CHEAP,
  MODEL_DEEP,
  callGemini,
} from "../lib/gemini.js";
import { buildOutreachPrompt, OutreachSchema } from "../lib/prompts.js";
import { assertAndIncrement } from "../lib/quota.js";

const InputSchema = z.object({
  fromKey: z.string(),
  toKey: z.string(),
  angle: z.string().max(200).optional(),
});

// Output schema with contact information and delivery options
const OutreachWithContactsSchema = z.object({
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

export const draftOutreach = onCall(
  {
    region: "us-central1",
    enforceAppCheck: false,
    cors: true,
    secrets: [GEMINI_API_KEY],
    timeoutSeconds: 30,
  },
  async (req) => {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required.");

    const parsed = InputSchema.safeParse(req.data);
    if (!parsed.success)
      throw new HttpsError("invalid-argument", parsed.error.message);
    const { fromKey, toKey, angle } = parsed.data;

    await assertAndIncrement(uid, "outreach");

    const db = getFirestore();
    const [fromSnap, toSnap] = await Promise.all([
      db.doc(`channels/${fromKey}`).get(),
      db.doc(`channels/${toKey}`).get(),
    ]);

    if (!fromSnap.exists || !toSnap.exists) {
      throw new HttpsError(
        "not-found",
        "Channel(s) not found in cache. Analyze them first.",
      );
    }

    const from = ChannelProfileSchema.parse(fromSnap.data());
    const to = ChannelProfileSchema.parse(toSnap.data());

    // Extract contact information from target channel.
    // YouTube's brandingSettings.channel.keywords is a space/quote-delimited
    // string (older API responses) but may be an array — handle both safely.
    const rawKeywords = (to.raw as any)?.brandingSettings?.channel?.keywords;
    const keywordsText = Array.isArray(rawKeywords)
      ? rawKeywords.join(" ")
      : typeof rawKeywords === "string"
        ? rawKeywords
        : undefined;
    const textForContactExtraction = [
      to.description,
      (to.raw as any)?.snippet?.description,
      keywordsText,
      to.topics.join(" "),
    ]
      .filter((s): s is string => !!s)
      .join(" ");

    // Generate outreach message with AI
    const result = await callGemini(
      buildOutreachPrompt(from, to, angle ?? "a short-form content swap"),
      OutreachSchema,
      { model: MODEL_CHEAP, fallbackModel: MODEL_DEEP },
    );

    // Parse contacts from the text
    const contacts = extractContacts(textForContactExtraction);

    return {
      ...result,
      contacts: Object.keys(contacts).length > 0 ? contacts : undefined,
      preferredMethod: getPreferredContactMethod(
        contacts,
        to.ref.platform,
      ),
    };
  },
);

// ---------------------------------------------------------------------
// Contact extraction helpers (duplicated from lib/contacts.ts for
// standalone callable use)
// ---------------------------------------------------------------------

const EMAIL_RE = /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/gi;
const URL_RE = /https?:\/\/[^\s)>\]"']+/gi;

function isJunkEmail(email: string): boolean {
  const e = email.toLowerCase();
  return (
    e.includes("noreply") ||
    e.includes("no-reply") ||
    e.endsWith("example.com") ||
    e.endsWith(".png") ||
    e.endsWith(".jpg")
  );
}

function stripTrailingPunctuation(url: string): string {
  return url.replace(/[.,;:!?)]+$/, "");
}

function extractContacts(text: string): Contacts {
  const contacts: Contacts = {};
  if (!text) return contacts;

  // --- Email: prefer one near a "business/contact/collab" cue, else first. ---
  const emails = [...text.matchAll(EMAIL_RE)]
    .map((m) => m[0])
    .filter((e) => !isJunkEmail(e));
  if (emails.length > 0) {
    const lower = text.toLowerCase();
    const cued = emails.find((e) => {
      const idx = lower.indexOf(e.toLowerCase());
      const window = lower.slice(Math.max(0, idx - 40), idx);
      return /business|contact|inquir|collab|partnership|booking|sponsor|work with/.test(
        window,
      );
    });
    contacts.email = cued ?? emails[0];
  }

  // --- URLs → classify by host. ---
  const urls = [...text.matchAll(URL_RE)].map((m) =>
    stripTrailingPunctuation(m[0]),
  );
  const others: string[] = [];
  for (const url of urls) {
    const host = url.toLowerCase();
    if (host.includes("instagram.com")) {
      contacts.instagram ??= url;
    } else if (host.includes("tiktok.com")) {
      contacts.tiktok ??= url;
    } else if (
      host.includes("twitter.com") ||
      /(?:^|\/\/)(?:www\.)?x\.com\//i.test(url)
    ) {
      contacts.twitter ??= url;
    } else if (
      host.includes("discord.gg") ||
      host.includes("discord.com/invite")
    ) {
      contacts.discord ??= url;
    } else if (host.includes("youtube.com") || host.includes("youtu.be")) {
      // skip self-references
    } else if (!contacts.website) {
      contacts.website = url;
    } else if (others.length < 8 && !others.includes(url)) {
      others.push(url);
    }
  }

  // --- Bare handles like "IG: @handle" when no full URL was present. ---
  if (!contacts.instagram) {
    const m = text.match(
      /(?:instagram|insta|ig)\s*[:@-]*\s*@?([a-z0-9._]{2,30})/i,
    );
    if (m?.[1]) contacts.instagram = `https://instagram.com/${m[1]}`;
  }
  if (!contacts.tiktok) {
    const m = text.match(/tiktok\s*[:@-]*\s*@?([a-z0-9._]{2,30})/i);
    if (m?.[1]) contacts.tiktok = `https://tiktok.com/@${m[1]}`;
  }
  if (!contacts.twitter) {
    const m = text.match(/(?:twitter|x)\s*[:@-]*\s*@([a-z0-9_]{2,20})/i);
    if (m?.[1]) contacts.twitter = `https://twitter.com/${m[1]}`;
  }

  if (others.length > 0) contacts.other = others;
  return contacts;
}

interface Contacts {
  email?: string;
  instagram?: string;
  tiktok?: string;
  twitter?: string;
  discord?: string;
  website?: string;
  other?: string[];
}

function getPreferredContactMethod(
  contacts: Contacts,
  platform: string,
): {
  method: string;
  destination?: string;
} | null {
  // Priority order based on platform
  const platformMethods: Record<
    string,
    Array<{ method: string; condition?: () => boolean }>
  > = {
    youtube: [
      { method: "email", condition: () => !!contacts.email },
      { method: "website", condition: () => !!contacts.website },
      { method: "instagram_dm", condition: () => !!contacts.instagram },
      { method: "tiktok_dm", condition: () => !!contacts.tiktok },
      { method: "twitter_dm", condition: () => !!contacts.twitter },
    ],
    instagram: [
      { method: "instagram_dm", condition: () => !!contacts.instagram },
      { method: "email", condition: () => !!contacts.email },
      { method: "tiktok_dm", condition: () => !!contacts.tiktok },
    ],
    tiktok: [
      { method: "tiktok_dm", condition: () => !!contacts.tiktok },
      { method: "email", condition: () => !!contacts.email },
      { method: "instagram_dm", condition: () => !!contacts.instagram },
    ],
  };

  const methods = platformMethods[platform] ?? platformMethods["youtube"];

  for (const { method, condition } of methods!) {
    if (!condition || condition()) {
      return {
        method,
        destination: method.split("_")[0] === "other" ? undefined : (contacts[method.split("_")[0] as keyof Contacts] as string | undefined),
      };
    }
  }

  return null;
}
