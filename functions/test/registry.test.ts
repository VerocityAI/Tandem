import { describe, it, expect } from "vitest";

import { platformRegistry } from "../src/adapters/registry.js";
import { NotImplementedError } from "@cohyve/shared-types";

describe("PlatformRegistry", () => {
  it("detects YouTube @handle URL", () => {
    const ref = platformRegistry.detect("https://youtube.com/@MKBHD");
    expect(ref?.platform).toBe("youtube");
    expect(ref?.externalId).toBe("@MKBHD");
  });

  it("detects YouTube UC channel id", () => {
    const ref = platformRegistry.detect("https://www.youtube.com/channel/UCBJycsmduvYEL83R_U4JriQ");
    expect(ref?.platform).toBe("youtube");
    expect(ref?.externalId).toBe("UCBJycsmduvYEL83R_U4JriQ");
  });

  it("detects Instagram URL even though adapter is stubbed", () => {
    const ref = platformRegistry.detect("https://www.instagram.com/natgeo/");
    expect(ref?.platform).toBe("instagram");
    expect(ref?.externalId).toBe("natgeo");
  });

  it("detects TikTok handle URL", () => {
    const ref = platformRegistry.detect("https://www.tiktok.com/@khaby.lame");
    expect(ref?.platform).toBe("tiktok");
    expect(ref?.externalId).toBe("khaby.lame");
  });

  it("returns null for unknown text", () => {
    expect(platformRegistry.detect("not a url, not a handle")).toBeNull();
  });

  it("stub adapters throw NotImplementedError on network methods", async () => {
    const ig = platformRegistry.get("instagram");
    await expect(
      ig.fetchProfile({ platform: "instagram", externalId: "x" }),
    ).rejects.toBeInstanceOf(NotImplementedError);

    const tt = platformRegistry.get("tiktok");
    await expect(
      tt.fetchProfile({ platform: "tiktok", externalId: "x" }),
    ).rejects.toBeInstanceOf(NotImplementedError);
  });

  it("all() returns one adapter per platform", () => {
    const platforms = platformRegistry.all().map((a) => a.platform);
    expect(new Set(platforms).size).toBe(platforms.length);
    expect(platforms).toContain("youtube");
    expect(platforms).toContain("instagram");
    expect(platforms).toContain("tiktok");
  });
});
