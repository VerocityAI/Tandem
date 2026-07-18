/**
 * YouTube adapter — full implementation.
 *
 * Ported from the original prototype (docs/prototype.html):
 *   - cleanChannelName
 *   - channelLookupParams
 *   - fetchChannelProfile (broadened to request brandingSettings, topicDetails, contentDetails)
 *   - new: fetchRecentPosts (uploads playlist), fetchTopComments
 *
 * Requires secret YOUTUBE_API_KEY.
 */

import { defineSecret } from "firebase-functions/params";
import {
  type ChannelProfile,
  type ChannelRef,
  type Comment,
  type PlatformAdapter,
  type Post,
  type SearchQuery,
  channelKey,
} from "@tandem/shared-types";

import { inferFormat, inferLanguage, inferNiche, inferRegion, topicsForNiche } from "../../lib/inference.js";
import { fetchJsonWithTimeout } from "../../lib/http.js";

export const YOUTUBE_API_KEY = defineSecret("YOUTUBE_API_KEY");

const API_BASE = "https://www.googleapis.com/youtube/v3";

function parseYouTubeInput(text: string): ChannelRef | null {
  const value = text.trim();
  if (!value) return null;

  // Don't claim URLs that clearly belong to other platforms.
  if (/(?:tiktok\.com|instagram\.com)/i.test(value)) return null;

  // Direct UC channel id
  const idMatch = value.match(/(?:^|\/)(UC[\w-]{20,})(?:[/?#]|$)/);
  if (idMatch && idMatch[1]) {
    return { platform: "youtube", externalId: idMatch[1], url: value };
  }

  // @handle
  const handleMatch = value.match(/(?:youtube\.com\/)?@([\w.-]+)/);
  if (handleMatch && handleMatch[1]) {
    return {
      platform: "youtube",
      externalId: `@${handleMatch[1]}`,
      handle: `@${handleMatch[1]}`,
      url: `https://www.youtube.com/@${handleMatch[1]}`,
    };
  }

  // youtube.com/c/<name> or /user/<name>
  const legacy = value.match(/youtube\.com\/(?:c|user)\/([\w.-]+)/i);
  if (legacy && legacy[1]) {
    return {
      platform: "youtube",
      externalId: legacy[1],
      handle: legacy[1],
      url: value,
    };
  }

  // Bare youtube.com URL → not enough info on its own
  if (/^https?:\/\/(www\.)?youtube\.com\/?$/i.test(value)) return null;

  return null;
}

interface YouTubeChannelItem {
  id: string;
  snippet?: {
    title?: string;
    description?: string;
    customUrl?: string;
    country?: string;
    thumbnails?: { default?: { url?: string }; high?: { url?: string } };
  };
  statistics?: {
    subscriberCount?: string;
    viewCount?: string;
    videoCount?: string;
  };
  brandingSettings?: {
    channel?: { keywords?: string; country?: string };
  };
  topicDetails?: { topicCategories?: string[] };
  contentDetails?: { relatedPlaylists?: { uploads?: string } };
}

async function fetchChannelItem(ref: ChannelRef, key: string): Promise<YouTubeChannelItem> {
  // Channel id path
  if (ref.externalId.startsWith("UC")) {
    const url = new URL(`${API_BASE}/channels`);
    url.search = new URLSearchParams({
      part: "snippet,statistics,brandingSettings,topicDetails,contentDetails",
      id: ref.externalId,
      key,
    }).toString();
    const data = await fetchJsonWithTimeout<{ items?: YouTubeChannelItem[] }>(url);
    const item = data.items?.[0];
    if (!item) throw new Error("YouTube channel not found by id.");
    return item;
  }

  // Handle path (with or without leading @)
  const handle = ref.externalId.startsWith("@") ? ref.externalId : `@${ref.externalId}`;
  const url = new URL(`${API_BASE}/channels`);
  url.search = new URLSearchParams({
    part: "snippet,statistics,brandingSettings,topicDetails,contentDetails",
    forHandle: handle,
    key,
  }).toString();
  const data = await fetchJsonWithTimeout<{ items?: YouTubeChannelItem[] }>(url);
  const item = data.items?.[0];
  if (!item) {
    // Fallback: search
    const sUrl = new URL(`${API_BASE}/search`);
    sUrl.search = new URLSearchParams({
      part: "snippet",
      type: "channel",
      maxResults: "1",
      q: handle,
      key,
    }).toString();
    const sData = await fetchJsonWithTimeout<{
      items?: { snippet?: { channelId?: string } }[];
    }>(sUrl);
    const channelId = sData.items?.[0]?.snippet?.channelId;
    if (!channelId) throw new Error("YouTube channel not found by handle.");
    return fetchChannelItem(
      { ...ref, externalId: channelId },
      key,
    );
  }
  return item;
}

function toProfile(ref: ChannelRef, item: YouTubeChannelItem): ChannelProfile {
  const snippet = item.snippet ?? {};
  const stats = item.statistics ?? {};
  const branding = item.brandingSettings?.channel ?? {};
  const title = snippet.title ?? ref.handle ?? "YouTube creator";
  const description = snippet.description ?? "";
  const text = `${title} ${description} ${branding.keywords ?? ""} ${(item.topicDetails?.topicCategories ?? []).join(" ")}`;
  const niche = inferNiche(text);
  const region = branding.country ?? snippet.country ?? inferRegion(text);
  const thumbnailUrl = snippet.thumbnails?.high?.url ?? snippet.thumbnails?.default?.url;
  return {
    ref: { ...ref, externalId: item.id, handle: snippet.customUrl ?? ref.handle },
    name: title,
    description,
    thumbnailUrl,
    followers: Number(stats.subscriberCount ?? 0),
    views: Number(stats.viewCount ?? 0),
    posts: Number(stats.videoCount ?? 0),
    region,
    niche,
    language: inferLanguage(text, region),
    format: inferFormat(text, niche),
    topics: topicsForNiche(text, niche),
    confidence: stats.subscriberCount ? "High" : "Medium",
    sourceSnapshotAt: new Date().toISOString(),
    raw: item,
  };
}

export const youtubeAdapter: PlatformAdapter = {
  platform: "youtube",

  parseInput: parseYouTubeInput,

  async fetchProfile(ref: ChannelRef): Promise<ChannelProfile> {
    const key = YOUTUBE_API_KEY.value();
    const item = await fetchChannelItem(ref, key);
    return toProfile(ref, item);
  },

  async fetchRecentPosts(ref: ChannelRef, limit: number): Promise<Post[]> {
    const key = YOUTUBE_API_KEY.value();
    const item = await fetchChannelItem(ref, key);
    const uploads = item.contentDetails?.relatedPlaylists?.uploads;
    if (!uploads) return [];
    const plUrl = new URL(`${API_BASE}/playlistItems`);
    plUrl.search = new URLSearchParams({
      part: "snippet,contentDetails",
      playlistId: uploads,
      maxResults: String(Math.min(50, Math.max(1, limit))),
      key,
    }).toString();
    const plData = await fetchJsonWithTimeout<{
      items?: {
        snippet?: {
          title?: string;
          description?: string;
          publishedAt?: string;
          resourceId?: { videoId?: string };
          thumbnails?: { default?: { url?: string } };
        };
      }[];
    }>(plUrl);
    const basicPosts = (plData.items ?? [])
      .map((it): Post | null => {
        const videoId = it.snippet?.resourceId?.videoId;
        if (!videoId) return null;
        return {
          id: videoId,
          title: it.snippet?.title,
          description: (it.snippet?.description ?? "").slice(0, 500),
          publishedAt: it.snippet?.publishedAt,
          thumbnailUrl: it.snippet?.thumbnails?.default?.url,
        };
      })
      .filter((p): p is Post => p !== null);

    // Enrich with video details (tags, view/like/comment counts)
    if (basicPosts.length === 0) return basicPosts;
    const videoIds = basicPosts.map((p) => p.id).join(",");
    try {
      const vUrl = new URL(`${API_BASE}/videos`);
      vUrl.search = new URLSearchParams({
        part: "snippet,statistics",
        id: videoIds,
        key,
      }).toString();
      const vData = await fetchJsonWithTimeout<{
        items?: {
          id: string;
          snippet?: { tags?: string[]; defaultAudioLanguage?: string; defaultLanguage?: string };
          statistics?: {
            viewCount?: string;
            likeCount?: string;
            commentCount?: string;
          };
        }[];
      }>(vUrl);
      const detailMap = new Map(
        (vData.items ?? []).map((v) => [v.id, v]),
      );
      for (const post of basicPosts) {
        const detail = detailMap.get(post.id);
        if (!detail) continue;
        post.tags = detail.snippet?.tags;
        post.language = detail.snippet?.defaultAudioLanguage ?? detail.snippet?.defaultLanguage;
        post.views = Number(detail.statistics?.viewCount ?? 0);
        post.likes = Number(detail.statistics?.likeCount ?? 0);
        post.comments = Number(detail.statistics?.commentCount ?? 0);
      }
    } catch {
      // If video details fail, continue with basic posts
    }
    return basicPosts;
  },

  async fetchTopComments(_ref: ChannelRef, postIds: string[]): Promise<Comment[]> {
    const key = YOUTUBE_API_KEY.value();
    const results: Comment[] = [];
    for (const videoId of postIds.slice(0, 3)) {
      try {
        const url = new URL(`${API_BASE}/commentThreads`);
        url.search = new URLSearchParams({
          part: "snippet",
          videoId,
          order: "relevance",
          maxResults: "5",
          textFormat: "plainText",
          key,
        }).toString();
        const data = await fetchJsonWithTimeout<{
          items?: {
            id: string;
            snippet?: {
              topLevelComment?: {
                snippet?: {
                  authorDisplayName?: string;
                  textDisplay?: string;
                  likeCount?: number;
                };
              };
            };
          }[];
        }>(url);
        for (const it of data.items ?? []) {
          const c = it.snippet?.topLevelComment?.snippet;
          if (!c?.textDisplay) continue;
          results.push({
            id: it.id,
            postId: videoId,
            author: c.authorDisplayName,
            text: c.textDisplay.slice(0, 280),
            likeCount: c.likeCount,
          });
        }
      } catch {
        // Comments disabled / quota — skip silently.
      }
    }
    return results;
  },

  async searchCandidates(query: SearchQuery): Promise<ChannelRef[]> {
    const key = YOUTUBE_API_KEY.value();
    const url = new URL(`${API_BASE}/search`);
    url.search = new URLSearchParams({
      part: "snippet",
      type: "channel",
      maxResults: String(query.limit ?? 10),
      q: query.text ?? `${query.niche ?? ""} ${query.region ?? ""}`.trim(),
      key,
    }).toString();
    const data = await fetchJsonWithTimeout<{
      items?: { snippet?: { channelId?: string; title?: string } }[];
    }>(url);
    return (data.items ?? [])
      .map((it): ChannelRef | null => {
        const id = it.snippet?.channelId;
        if (!id) return null;
        return { platform: "youtube", externalId: id, handle: it.snippet?.title };
      })
      .filter((r): r is ChannelRef => r !== null);
  },
};

export { channelKey };
