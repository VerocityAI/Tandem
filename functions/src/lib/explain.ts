/**
 * Human-readable "why this is a good collaborator" explanation.
 *
 * Composes a few plain-English sentences from the same signals the scorer uses
 * (niche relationship, audience-size parity, language, reach/engagement/
 * activity). Deterministic and always available — the AI rationale, when
 * present, is shown as an additional insight on top of this.
 */

import type { ChannelProfile } from "@cohyve/shared-types";

import { ADJACENT_NICHES } from "./scoring.js";

function norm(v?: string): string {
  return (v ?? "").trim().toLowerCase();
}

function fmt(n: number): string {
  if (n >= 1e9) return `${(n / 1e9).toFixed(1)}B`;
  if (n >= 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (n >= 1e3) return `${(n / 1e3).toFixed(1)}K`;
  return String(Math.round(n));
}

function isAdjacent(a: string, b: string): boolean {
  return (ADJACENT_NICHES[a] ?? []).map(norm).includes(norm(b));
}

/** Build a 2-4 sentence explanation of why `candidate` suits `source`. */
export function explainMatch(source: ChannelProfile, candidate: ChannelProfile): string {
  const name = candidate.name?.trim() || "This creator";
  const out: string[] = [];

  // 1. Audience / niche relationship.
  const sameNiche = norm(source.niche) !== "" && norm(source.niche) === norm(candidate.niche);
  const adjacent = isAdjacent(source.niche, candidate.niche);
  if (adjacent) {
    out.push(
      `${name} sits in the adjacent ${candidate.niche} niche, so a collaboration puts you in front of a related but largely new audience — the sweet spot for growth.`,
    );
  } else if (sameNiche) {
    out.push(
      `${name} creates in your ${candidate.niche} space, so their viewers already care about your topics and a content swap feels natural.`,
    );
  } else {
    out.push(
      `${name} covers ${candidate.niche} — a different lane, but the right cross-over angle could open up a fresh audience for both of you.`,
    );
  }

  // 2. Audience-size parity / direction.
  if (source.followers > 0 && candidate.followers > 0) {
    const ratio = candidate.followers / source.followers;
    if (ratio >= 0.5 && ratio <= 2) {
      out.push(
        `At ${fmt(candidate.followers)} subscribers they're a comparable size to you (${fmt(source.followers)}), so the exchange is balanced and realistic to land.`,
      );
    } else if (ratio > 2) {
      out.push(
        `With ${fmt(candidate.followers)} subscribers they're a step up from your ${fmt(source.followers)} — a strong reach booster, though you'll want a compelling hook to land it.`,
      );
    } else {
      out.push(
        `At ${fmt(candidate.followers)} subscribers they're a smaller, rising partner next to your ${fmt(source.followers)} — creators at this stage are often the most responsive to collab requests.`,
      );
    }
  }

  // 3. Language compatibility.
  if (norm(source.language) !== "" && norm(source.language) === norm(candidate.language)) {
    out.push(
      `You both publish in ${(source.language ?? "").toUpperCase()}, so the audiences carry over cleanly.`,
    );
  }

  // 4. Reach / engagement / activity highlights (pick the strongest few).
  const highlights: string[] = [];
  const candReach = candidate.medianViews ?? candidate.avgViews;
  if (candReach && candReach > 0) highlights.push(`averages ${fmt(candReach)} views per video`);
  if (candidate.engagementPct && candidate.engagementPct >= 3) {
    highlights.push(`a healthy ${candidate.engagementPct.toFixed(1)}% engagement rate`);
  }
  if (candidate.lastUploadAt) {
    const days = (Date.now() - Date.parse(candidate.lastUploadAt)) / (1000 * 60 * 60 * 24);
    if (!Number.isNaN(days) && days <= 30) {
      highlights.push(`is actively posting (last upload ${days < 1 ? "today" : `${Math.round(days)}d ago`})`);
    }
  }
  if (highlights.length > 0) {
    out.push(`They also ${highlights.slice(0, 2).join(" and ")}, a sign of an engaged audience worth partnering with.`);
  }

  return out.join(" ");
}
