import { describe, it, expect } from "vitest";

import type { ChannelProfile } from "@tandem/shared-types";
import {
  ADJACENT_NICHES,
  audienceTier,
  passesRealismGate,
  scoreCreator,
} from "../src/lib/scoring.js";

function daysAgo(n: number): string {
  return new Date(Date.now() - n * 24 * 60 * 60 * 1000).toISOString();
}

function fake(p: Partial<ChannelProfile> = {}): ChannelProfile {
  return {
    ref: { platform: "youtube", externalId: "UCxxx", handle: "@x" },
    name: "x",
    description: "",
    followers: 200_000,
    region: "UAE",
    niche: "Tech",
    format: "Long-form guest",
    topics: ["reviews", "gadgets", "smartphones"],
    language: "en",
    confidence: "High",
    sourceSnapshotAt: "2026-05-26T00:00:00Z",
    engagementPct: 5,
    lastUploadAt: daysAgo(10),
    ...p,
  };
}

const source = fake();

describe("scoring", () => {
  it("audienceTier buckets correctly", () => {
    expect(audienceTier(50_000)).toBe("micro");
    expect(audienceTier(250_000)).toBe("mid");
    expect(audienceTier(750_000)).toBe("large");
    expect(audienceTier(2_000_000)).toBe("mega");
  });

  it("adjacent niches map is symmetric for food/travel", () => {
    expect(ADJACENT_NICHES.Food).toContain("Travel");
    expect(ADJACENT_NICHES.Travel).toContain("Food");
  });

  it("rewards an adjacent partner over an identical clone (complementarity)", () => {
    const clone = scoreCreator(source, fake()); // same niche + same topics = clone
    const adjacent = scoreCreator(
      source,
      fake({ niche: "Gaming", topics: ["gaming", "gadgets", "esports"] }),
    );
    expect(adjacent.score).toBeGreaterThan(clone.score);
  });

  it("penalises an unrelated niche with no overlap", () => {
    const adjacent = scoreCreator(
      source,
      fake({ niche: "Gaming", topics: ["gaming", "gadgets"] }),
    );
    const unrelated = scoreCreator(
      source,
      fake({ niche: "Kids", topics: ["nursery", "rhymes"] }),
    );
    expect(unrelated.score).toBeLessThan(adjacent.score);
  });

  it("favours comparable size over a near-edge size gap", () => {
    const comparable = scoreCreator(source, fake({ followers: 300_000 }));
    const edge = scoreCreator(source, fake({ followers: 950_000 })); // ~4.75x, still in-band
    expect(comparable.score).toBeGreaterThan(edge.score);
  });

  it("prefers same-language partners", () => {
    const sameLang = scoreCreator(source, fake({ niche: "Gaming", language: "en" }));
    const crossLang = scoreCreator(source, fake({ niche: "Gaming", language: "ar" }));
    expect(sameLang.score).toBeGreaterThan(crossLang.score);
  });

  it("realism gate rejects out-of-band size and inactive channels", () => {
    expect(passesRealismGate(source, fake({ followers: 3_000_000 }))).toBe(false); // 15x
    expect(passesRealismGate(source, fake({ followers: 5_000 }))).toBe(false); // 0.025x
    expect(passesRealismGate(source, fake({ followers: 400_000 }))).toBe(true); // 2x
    expect(passesRealismGate(source, fake({ lastUploadAt: daysAgo(800) }))).toBe(false);
    expect(passesRealismGate(source, fake({ lastUploadAt: daysAgo(30) }))).toBe(true);
  });

  it("respects a supplied semantic similarity for complementarity", () => {
    const clone = scoreCreator(source, fake({ niche: "Gaming" }), { overlapSimilarity: 0.98 });
    const adjacent = scoreCreator(source, fake({ niche: "Gaming" }), { overlapSimilarity: 0.4 });
    expect(adjacent.score).toBeGreaterThan(clone.score);
  });

  it("caps score at 100", () => {
    const s = scoreCreator(
      source,
      fake({ niche: "Gaming", engagementPct: 100, avgViews: 500_000, medianViews: 500_000 }),
    );
    expect(s.score).toBeLessThanOrEqual(100);
  });
});
