/**
 * Gemini client. Uses the REST `generateContent` endpoint (no SDK dependency)
 * with JSON response mode, then validates the payload against a Zod schema.
 *
 * The API key lives in Secret Manager (GEMINI_API_KEY) — never in code/files.
 */

import { defineSecret } from "firebase-functions/params";
import type { ZodType } from "zod";

import { fetchJsonWithTimeout } from "./http.js";

export const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

const MODEL = "gemini-2.5-flash";
const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`;

interface GeminiResponse {
  candidates?: Array<{
    content?: { parts?: Array<{ text?: string }> };
    finishReason?: string;
  }>;
}

/** Strip markdown code fences and isolate the first JSON object/array. */
function extractJson(text: string): unknown {
  let cleaned = text.trim();
  // Remove ```json ... ``` or ``` ... ``` fences.
  const fence = cleaned.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  if (fence && fence[1]) cleaned = fence[1].trim();

  try {
    return JSON.parse(cleaned);
  } catch {
    // Fallback: grab the outermost {...} or [...] block.
    const start = cleaned.search(/[{[]/);
    const end = Math.max(cleaned.lastIndexOf("}"), cleaned.lastIndexOf("]"));
    if (start >= 0 && end > start) {
      return JSON.parse(cleaned.slice(start, end + 1));
    }
    throw new Error("Gemini response was not valid JSON.");
  }
}

/**
 * Call Gemini with `prompt`, request JSON output, and validate it with `schema`.
 * Throws if the call fails, returns empty, or the JSON fails validation.
 */
export async function callGemini<T>(prompt: string, schema: ZodType<T>): Promise<T> {
  const key = GEMINI_API_KEY.value();
  const url = new URL(ENDPOINT);
  url.searchParams.set("key", key);

  const body = {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: {
      temperature: 0.4,
      responseMimeType: "application/json",
      maxOutputTokens: 2048,
    },
  };

  const data = await fetchJsonWithTimeout<GeminiResponse>(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    timeoutMs: 25_000,
  });

  const text =
    data.candidates?.[0]?.content?.parts?.map((p) => p.text ?? "").join("") ?? "";
  if (!text.trim()) throw new Error("Gemini returned an empty response.");

  return schema.parse(extractJson(text));
}
