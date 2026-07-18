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

/**
 * Model routing for cost control.
 * - MODEL_DEEP: stable flash model, proven available on this project.
 * - MODEL_CHEAP: cheapest flash-lite (~2x cheaper) but currently INTERMITTENTLY
 *   404s on this project, so callers opt in via `{ model: MODEL_CHEAP,
 *   fallbackModel: MODEL_DEEP }` and we transparently fall back on failure.
 */
export const MODEL_DEEP = "gemini-flash-latest";
export const MODEL_CHEAP = "gemini-flash-lite-latest";

function endpoint(model: string): string {
  return `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
}

export interface GeminiOptions {
  /** Preferred model (defaults to MODEL_DEEP). */
  model?: string;
  /** If the preferred model fails, retry once with this model. */
  fallbackModel?: string;
}

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
 * Routes to `opts.model` (default MODEL_DEEP) and transparently retries once
 * with `opts.fallbackModel` if the preferred model fails (e.g. cheap-model 404).
 */
export async function callGemini<T>(
  prompt: string,
  schema: ZodType<T>,
  opts: GeminiOptions = {},
): Promise<T> {
  const primary = opts.model ?? MODEL_DEEP;
  try {
    return await callGeminiWithModel(prompt, schema, primary);
  } catch (e) {
    if (opts.fallbackModel && opts.fallbackModel !== primary) {
      console.warn(`Gemini model ${primary} failed, falling back to ${opts.fallbackModel}:`, e);
      return callGeminiWithModel(prompt, schema, opts.fallbackModel);
    }
    throw e;
  }
}

async function callGeminiWithModel<T>(
  prompt: string,
  schema: ZodType<T>,
  model: string,
): Promise<T> {
  const key = GEMINI_API_KEY.value();
  const url = new URL(endpoint(model));
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
