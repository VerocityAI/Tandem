import { onCall, HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";

import { platformRegistry } from "../adapters/registry.js";

const InputSchema = z.object({ text: z.string().min(1).max(500) });

/**
 * Pure parsing — no network. Returns a ChannelRef if any registered adapter
 * recognizes the input as a URL/handle/id on its platform. Used by the
 * Connect screen to pre-select the platform and validate input before
 * the user spends quota on `analyzeChannel`.
 */
export const detectChannel = onCall(
  { region: "us-central1", enforceAppCheck: false, cors: true },
  (req) => {
    const parsed = InputSchema.safeParse(req.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", parsed.error.message);
    }
    const ref = platformRegistry.detect(parsed.data.text);
    return { ref };
  },
);
