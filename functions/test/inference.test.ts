import { describe, it, expect } from "vitest";

import { inferNiche, inferFormat } from "../src/lib/inference.js";

describe("inferNiche", () => {
  it("classifies a walking-tour / travel channel as Travel (not Tech)", () => {
    // Regression: the keyword "ai" must NOT match "Tr[ai]ls".
    const text =
      "Drifter Trails Walking Tours Tourism Travel vlog City Exploration " +
      "Street walking Cultural Heritage Tours Lifestyle Tourism";
    expect(inferNiche(text)).toBe("Travel");
  });

  it("does not misclassify 'trails' or 'detail' as Tech via the 'ai' keyword", () => {
    expect(inferNiche("Nature trails and hiking details")).not.toBe("Tech");
  });

  it("still classifies genuine tech channels as Tech", () => {
    expect(inferNiche("Smartphone reviews and gadget unboxing, latest AI tools")).toBe("Tech");
  });

  it("classifies food channels as Food", () => {
    expect(inferNiche("Easy recipes and home cooking from my kitchen")).toBe("Food");
  });
});

describe("inferFormat", () => {
  it("does not treat 'delivery' as a live stream", () => {
    expect(inferFormat("fast food delivery reviews", "Food")).not.toBe("Live stream");
  });

  it("detects genuine live-stream channels", () => {
    expect(inferFormat("daily live stream gaming", "Gaming")).toBe("Live stream");
  });
});
