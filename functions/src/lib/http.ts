/**
 * Minimal fetch helper with a hard timeout.
 *
 * Node 20 ships a global `fetch` (undici). We wrap it so every outbound call
 * has a deadline and throws a readable error on non-2xx responses.
 */

export interface FetchJsonOptions {
  method?: string;
  headers?: Record<string, string>;
  body?: string;
  /** Abort the request after this many milliseconds. Default 10s. */
  timeoutMs?: number;
}

/**
 * Fetch `url` and parse the JSON body as `T`.
 * Throws on timeout or non-2xx status.
 */
export async function fetchJsonWithTimeout<T>(
  url: URL | string,
  options: FetchJsonOptions = {},
): Promise<T> {
  const { timeoutMs = 10_000, ...init } = options;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url.toString(), { ...init, signal: controller.signal });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      throw new Error(`HTTP ${res.status} ${res.statusText}: ${text.slice(0, 300)}`);
    }
    return (await res.json()) as T;
  } finally {
    clearTimeout(timer);
  }
}
