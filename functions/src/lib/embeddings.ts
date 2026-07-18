/**
 * Semantic embeddings via Gemini's `gemini-embedding-001` model.
 *
 * Used to measure audience/content similarity between two channels for the
 * scorer's Complementarity dimension — far more robust than exact-token overlap
 * ("workout" vs "workouts"). Embeddings are cached on `channels/{key}.embedding`.
 *
 * Reuses the GEMINI_API_KEY secret already declared for Gemini generation.
 */

import type { ChannelProfile } from "@tandem/shared-types";

import { GEMINI_API_KEY } from "./gemini.js";
import { fetchJsonWithTimeout } from "./http.js";

const MODEL = "gemini-embedding-001";
const ENDPOINT = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:embedContent`;

interface EmbedResponse {
  embedding?: { values?: number[] };
}

/**
 * Build the text that represents a channel's audience/content for embedding.
 * Emphasises niche/topics/pillars over raw description noise.
 */
export function profileEmbeddingText(p: ChannelProfile): string {
  return [
    p.niche,
    p.subNiche ?? "",
    p.topics.join(", "),
    (p.contentPillars ?? []).join(", "),
    (p.toneTags ?? []).join(", "),
    p.audiencePersona ?? "",
    p.description.slice(0, 400),
  ]
    .filter(Boolean)
    .join(". ")
    .slice(0, 2000);
}

/** Embed a string. Returns [] on failure (caller falls back to heuristics). */
export async function embedText(text: string): Promise<number[]> {
  if (!text.trim()) return [];
  const key = GEMINI_API_KEY.value();
  const url = new URL(ENDPOINT);
  url.searchParams.set("key", key);
  const body = {
    model: `models/${MODEL}`,
    content: { parts: [{ text }] },
  };
  const data = await fetchJsonWithTimeout<EmbedResponse>(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    timeoutMs: 15_000,
  });
  return data.embedding?.values ?? [];
}

/** Cosine similarity of two equal-length vectors; 0 when unusable. */
export function cosine(a: number[], b: number[]): number {
  if (a.length === 0 || a.length !== b.length) return 0;
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i++) {
    const av = a[i] ?? 0;
    const bv = b[i] ?? 0;
    dot += av * bv;
    na += av * av;
    nb += bv * bv;
  }
  if (na === 0 || nb === 0) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

/**
 * Map a raw embedding cosine onto the [0,1] "audience overlap" scale the scorer
 * expects (clone -> ~1, adjacent -> ~0.45, unrelated -> ~0). text-embedding-004
 * cosines for unrelated English text sit around ~0.35, near-duplicates ~0.95, so
 * we min-max normalise across that band. Bounds are heuristic and tunable.
 */
export function overlapFromCosine(cos: number): number {
  const LO = 0.35;
  const HI = 0.95;
  return Math.max(0, Math.min(1, (cos - LO) / (HI - LO)));
}
