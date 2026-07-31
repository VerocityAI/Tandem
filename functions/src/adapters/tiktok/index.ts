/**
 * TikTok adapter — STUB.
 *
 * v1 ships `parseInput` only. v2 will use the TikTok Display API
 * (developer account + scope approval required).
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

function parseTikTokInput(text: string): ChannelRef | null {
  const value = text.trim();
  if (!value) return null;

  const urlMatch = value.match(/tiktok\.com\/@([\w._]+)/i);
  if (urlMatch && urlMatch[1]) {
    const handle = urlMatch[1];
    return {
      platform: "tiktok",
      externalId: handle,
      handle: `@${handle}`,
      url: `https://www.tiktok.com/@${handle}`,
    };
  }

  // vm.tiktok.com short URL — not enough info on its own.
  return null;
}

export const tiktokAdapter: PlatformAdapter = {
  platform: "tiktok",
  parseInput: parseTikTokInput,
  async fetchProfile(_ref: ChannelRef): Promise<ChannelProfile> {
    throw new NotImplementedError("tiktok", "fetchProfile");
  },
  async fetchRecentPosts(_ref: ChannelRef, _limit: number): Promise<Post[]> {
    throw new NotImplementedError("tiktok", "fetchRecentPosts");
  },
  async fetchTopComments(_ref: ChannelRef, _postIds: string[]): Promise<Comment[]> {
    throw new NotImplementedError("tiktok", "fetchTopComments");
  },
  async searchCandidates(_query: SearchQuery): Promise<ChannelRef[]> {
    throw new NotImplementedError("tiktok", "searchCandidates");
  },
};
