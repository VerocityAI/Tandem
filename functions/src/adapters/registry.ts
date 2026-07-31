import type {
  ChannelRef,
  Platform,
  PlatformAdapter,
  PlatformRegistry,
} from "@cohyve/shared-types";

import { youtubeAdapter } from "./youtube/index.js";
import { instagramAdapter } from "./instagram/index.js";
import { tiktokAdapter } from "./tiktok/index.js";

const adapters: Record<Platform, PlatformAdapter> = {
  youtube: youtubeAdapter,
  instagram: instagramAdapter,
  tiktok: tiktokAdapter,
};

export const platformRegistry: PlatformRegistry = {
  get(p: Platform): PlatformAdapter {
    const a = adapters[p];
    if (!a) throw new Error(`No adapter registered for platform: ${p}`);
    return a;
  },
  all(): PlatformAdapter[] {
    return Object.values(adapters);
  },
  detect(text: string): ChannelRef | null {
    for (const a of Object.values(adapters)) {
      const ref = a.parseInput(text);
      if (ref) return ref;
    }
    return null;
  },
};
