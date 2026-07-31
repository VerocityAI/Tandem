/**
 * Deterministic activity/reach signals derived from a channel's recent posts.
 *
 * These turn already-fetched post statistics (views/likes/comments/publishedAt)
 * into the reach, engagement, cadence, recency, and language signals the
 * collaboration scorer needs. No network calls, no AI.
 */

import type { Post } from "@cohyve/shared-types";

import { inferLanguage } from "./inference.js";

export interface ActivitySignals {
  avgViews?: number;
  medianViews?: number;
  /** (avgLikes + avgComments) / avgViews * 100, clamped. */
  engagementPct?: number;
  /** Posts per 30 days across the observed window. */
  uploadsPerMonth?: number;
  /** ISO timestamp of the most recent post. */
  lastUploadAt?: string;
}

function median(nums: number[]): number {
  if (nums.length === 0) return 0;
  const sorted = [...nums].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 0) {
    return Math.round(((sorted[mid - 1] ?? 0) + (sorted[mid] ?? 0)) / 2);
  }
  return sorted[mid] ?? 0;
}

function mean(nums: number[]): number {
  if (nums.length === 0) return 0;
  return Math.round(nums.reduce((s, n) => s + n, 0) / nums.length);
}

/**
 * Compute reach/engagement/cadence/recency from recent posts.
 * Fields are left undefined when the underlying data is unavailable so the
 * scorer can fall back to neutral defaults.
 */
export function computeActivitySignals(posts: Post[]): ActivitySignals {
  if (posts.length === 0) return {};

  const viewCounts = posts.map((p) => p.views ?? 0).filter((v) => v > 0);
  const likeCounts = posts.map((p) => p.likes ?? 0);
  const commentCounts = posts.map((p) => p.comments ?? 0);

  const avgViews = viewCounts.length > 0 ? mean(viewCounts) : undefined;
  const medianViews = viewCounts.length > 0 ? median(viewCounts) : undefined;

  let engagementPct: number | undefined;
  if (avgViews && avgViews > 0) {
    const avgLikes = mean(likeCounts);
    const avgComments = mean(commentCounts);
    const raw = ((avgLikes + avgComments) / avgViews) * 100;
    engagementPct = Math.max(0, Math.min(100, Math.round(raw * 10) / 10));
  }

  // Cadence + recency from publish timestamps.
  const dates = posts
    .map((p) => (p.publishedAt ? Date.parse(p.publishedAt) : NaN))
    .filter((t) => !Number.isNaN(t))
    .sort((a, b) => b - a);

  let uploadsPerMonth: number | undefined;
  let lastUploadAt: string | undefined;
  const newest = dates[0];
  const oldest = dates[dates.length - 1];
  if (newest !== undefined) {
    lastUploadAt = new Date(newest).toISOString();
    if (oldest !== undefined && dates.length >= 2) {
      const spanDays = (newest - oldest) / (1000 * 60 * 60 * 24);
      if (spanDays > 0) {
        uploadsPerMonth = Math.round(((dates.length - 1) / spanDays) * 30 * 10) / 10;
      }
    }
  }

  return { avgViews, medianViews, engagementPct, uploadsPerMonth, lastUploadAt };
}

/**
 * Determine the channel's primary language from recent posts' audio-language
 * metadata (majority vote), falling back to a text/region heuristic.
 * Returns an ISO 639-1 code (e.g. "en").
 */
export function computePrimaryLanguage(
  posts: Post[],
  fallbackText: string,
  region?: string,
): string {
  const counts = new Map<string, number>();
  for (const p of posts) {
    const lang = p.language?.trim().toLowerCase();
    if (!lang) continue;
    // Normalise BCP-47 (e.g. "en-US") to the base language subtag.
    const base = lang.split("-")[0];
    if (base) counts.set(base, (counts.get(base) ?? 0) + 1);
  }

  let best: string | undefined;
  let bestCount = 0;
  for (const [lang, count] of counts) {
    if (count > bestCount) {
      best = lang;
      bestCount = count;
    }
  }

  return best ?? inferLanguage(fallbackText, region);
}
