import { describe, it, expect } from "vitest";

import { extractContacts, hasContacts } from "../src/lib/contacts.js";

describe("extractContacts", () => {
  it("extracts a business email near a cue over other emails", () => {
    const text =
      "Subscribe! Support: fan@gmail.com\nFor business inquiries: hello@agency.com";
    const c = extractContacts(text);
    expect(c.email).toBe("hello@agency.com");
  });

  it("classifies social + website URLs", () => {
    const text =
      "Follow me https://instagram.com/mychannel and https://www.tiktok.com/@mychannel " +
      "Join https://discord.gg/abcd My site https://mysite.com " +
      "Subscribe https://youtube.com/@mychannel";
    const c = extractContacts(text);
    expect(c.instagram).toContain("instagram.com/mychannel");
    expect(c.tiktok).toContain("tiktok.com/@mychannel");
    expect(c.discord).toContain("discord.gg/abcd");
    expect(c.website).toBe("https://mysite.com");
    // youtube self-links are ignored
    expect(JSON.stringify(c)).not.toContain("youtube.com");
  });

  it("ignores noreply emails", () => {
    const c = extractContacts("noreply@youtube.com only");
    expect(c.email).toBeUndefined();
  });

  it("parses bare IG handle when no URL present", () => {
    const c = extractContacts("IG: @traveldude for more");
    expect(c.instagram).toBe("https://instagram.com/traveldude");
  });

  it("hasContacts reflects emptiness", () => {
    expect(hasContacts(extractContacts("nothing here"))).toBe(false);
    expect(hasContacts(extractContacts("me@x.com"))).toBe(true);
  });
});
