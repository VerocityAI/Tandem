/**
 * Tandem Cloud Functions entrypoint.
 *
 * All callables are App Check enforced. Secrets live in Secret Manager:
 *   YOUTUBE_API_KEY, GEMINI_API_KEY
 *
 * v1 callables:
 *   - detectChannel    (cheap, pure parsing across registry)
 *   - analyzeChannel   (YouTube/IG/TikTok fetch + Gemini profiling)
 *   - findMatches      (rule scorer + AI rerank)
 *   - draftOutreach    (Gemini-templated outreach)
 *   - deleteAccount    (store-required)
 *
 * Scheduled:
 *   - refreshChannel   (weekly per active channel) [stubbed for v1]
 */

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const app = initializeApp();
getFirestore(app).settings({ ignoreUndefinedProperties: true });

export { detectChannel } from "./callables/detectChannel.js";
export { analyzeChannel } from "./callables/analyzeChannel.js";
export { findMatches } from "./callables/findMatches.js";
export { draftOutreach } from "./callables/draftOutreach.js";
export { deleteAccount } from "./callables/deleteAccount.js";
