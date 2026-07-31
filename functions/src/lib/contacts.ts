/**
 * Extract public contact points (email, socials, website) from a creator's
 * free text — channel description + recent video descriptions.
 *
 * YouTube does not expose creator emails via the API, but creators very often
 * list contact info in their descriptions. Parsing that (ToS-safe, since it's
 * data the API already returns) turns "go dig through their About page" into
 * one-tap contact buttons.
 */

import type { Contacts } from "@cohyve/shared-types";

const EMAIL_RE = /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/gi;
const URL_RE = /https?:\/\/[^\s)>\]"']+/gi;

/** Emails we never want to surface as a contact. */
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

/** Parse contacts from a blob of description text. */
export function extractContacts(text: string): Contacts {
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
  const urls = [...text.matchAll(URL_RE)].map((m) => stripTrailingPunctuation(m[0]));
  const others: string[] = [];
  for (const url of urls) {
    const host = url.toLowerCase();
    if (host.includes("instagram.com")) {
      contacts.instagram ??= url;
    } else if (host.includes("tiktok.com")) {
      contacts.tiktok ??= url;
    } else if (host.includes("twitter.com") || /(?:^|\/\/)(?:www\.)?x\.com\//i.test(url)) {
      contacts.twitter ??= url;
    } else if (host.includes("discord.gg") || host.includes("discord.com/invite")) {
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
    const m = text.match(/(?:instagram|insta|ig)\s*[:@-]*\s*@?([a-z0-9._]{2,30})/i);
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

/** True when at least one contact point was found. */
export function hasContacts(c: Contacts | undefined): boolean {
  if (!c) return false;
  return Boolean(
    c.email || c.instagram || c.tiktok || c.twitter || c.discord || c.website ||
      (c.other && c.other.length > 0),
  );
}
