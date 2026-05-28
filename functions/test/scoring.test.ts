import { describe, it, expect } from "vitest";

import type { ChannelProfile } from "@tandem/shared-types";
import { ADJACENT_NICHES, audienceTier, scoreCreator } from "../src/lib/scoring.js";

function fake(p: Partial<ChannelProfile> = {}): ChannelProfile {
  return {
    ref: { platform: "youtube", externalId: "UCxxx", handle: "@x" },
    name: "x",
    description: "",
    followers: 200_000,
    region: "UAE",
    niche: "Food",
    format: "Shorts swap",
    topics: ["shorts", "reviews"],
    confidence: "High",
    sourceSnapshotAt: "2026-05-26T00:00:00Z",
    engagementPct: 5,
    ...p,
  };
}

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

  it("same niche + region + format scores higher than mismatched", () => {
    const inputs = {
      myNiche: "Food",
      myTier: "mid" as const,
      myRegion: "UAE",
      myFormat: "Shorts swap" as const,
      myTopics: ["shorts", "reviews"],
      myPlatform: "youtube" as const,
    };
    const same = scoreCreator(inputs, fake());
    const off = scoreCreator(
      inputs,
      fake({ niche: "Finance", region: "US", format: "Long-form guest", topics: ["education"] }),
    );
    expect(same.score).toBeGreaterThan(off.score);
    expect(same.score).toBeGreaterThanOrEqual(75);
  });

  it("cross-platform short-form gets partial format credit", () => {
    const inputs = {
      myNiche: "Food",
      myTier: "mid" as const,
      myRegion: "UAE",
      myFormat: "Shorts swap" as const,
      myTopics: ["shorts"],
      myPlatform: "youtube" as const,
    };
    const igReels = scoreCreator(
      inputs,
      fake({ ref: { platform: "instagram", externalId: "foo" }, format: "Reels swap" }),
    );
    const igLive = scoreCreator(
      inputs,
      fake({ ref: { platform: "instagram", externalId: "foo" }, format: "Live stream" }),
    );
    expect(igReels.score).toBeGreaterThan(igLive.score);
  });

  it("caps score at 100", () => {
    const inputs = {
      myNiche: "Food",
      myTier: "mid" as const,
      myRegion: "UAE",
      myFormat: "Shorts swap" as const,
      myTopics: ["shorts", "reviews"],
      myPlatform: "youtube" as const,
    };
    const score = scoreCreator(inputs, fake({ engagementPct: 100 }));
    expect(score.score).toBeLessThanOrEqual(100);
  });
});
