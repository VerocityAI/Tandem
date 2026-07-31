/**
 * Instagram adapter — STUB.
 *
 * v1 ships `parseInput` so URL/handle detection works in the UI, but every
 * network method throws NotImplementedError. v2 will implement these against
 * the Instagram Graph API (Facebook App review required).
 */

import {
  type ChannelProfile,
  type ChannelRef,
  type Comment,
  NotImplementedError,
  type PlatformAdapter,
  type Post,
  type SearchQuery,
} from "@cohyve/shared-types";

function parseInstagramInput(text: string): ChannelRef | null {
  const value = text.trim();
  if (!value) return null;

  const urlMatch = value.match(/instagram\.com\/([\w._]+)/i);
  if (urlMatch && urlMatch[1] && urlMatch[1] !== "p" && urlMatch[1] !== "reel") {
    const handle = urlMatch[1];
    return {
      platform: "instagram",
      externalId: handle,
      handle: `@${handle}`,
      url: `https://www.instagram.com/${handle}/`,
    };
  }

  // Bare @handle (could be any platform — caller resolves order in registry).
  // We only claim it if the text *also* looks instagram-y (length, dots), or is explicit.
  const bareIg = value.match(/^@([\w._]{2,30})$/);
  if (bareIg && bareIg[1] && /\./.test(bareIg[1])) {
    // very weak signal; let YouTube adapter claim plain @handles first
    return {
      platform: "instagram",
      externalId: bareIg[1],
      handle: `@${bareIg[1]}`,
    };
  }

  return null;
}

export const instagramAdapter: PlatformAdapter = {
  platform: "instagram",
  parseInput: parseInstagramInput,
  async fetchProfile(_ref: ChannelRef): Promise<ChannelProfile> {
    throw new NotImplementedError("instagram", "fetchProfile");
  },
  async fetchRecentPosts(_ref: ChannelRef, _limit: number): Promise<Post[]> {
    throw new NotImplementedError("instagram", "fetchRecentPosts");
  },
  async fetchTopComments(_ref: ChannelRef, _postIds: string[]): Promise<Comment[]> {
    throw new NotImplementedError("instagram", "fetchTopComments");
  },
  async searchCandidates(_query: SearchQuery): Promise<ChannelRef[]> {
    throw new NotImplementedError("instagram", "searchCandidates");
  },
};
