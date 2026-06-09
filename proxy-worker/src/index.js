// MMail image privacy proxy — Cloudflare Worker entry point.
//
// The request logic lives in `handleRequest` so it can be unit-tested with an
// in-memory mock R2 + mock fetch (see test/handler.test.js). The default export
// just wires the live Worker bindings into it.
//
// Flow: parse u/e/s -> percent-decode u to the canonical assetURL -> HMAC-verify
// against "<e>:<assetURL>" -> reject (4xx, no fetch) on bad/expired -> R2 get by
// SHA-256(decoded assetURL) -> on miss fetch origin once (no cookies, neutral UA,
// size cap, timeout) -> store body+content-type in R2 -> stream back. On hit, serve
// from R2 with no re-fetch. Oversize/origin-error -> error status, nothing stored.

import { verify } from "./crypto.js";

const DEFAULT_MAX_BYTES = 10 * 1024 * 1024; // 10 MB
const DEFAULT_TIMEOUT_MS = 10_000; // 10 s
const NEUTRAL_UA = "MMail-Image-Proxy/1.0";

function bad(status, message) {
  return new Response(message, { status });
}

/// SHA-256 hex of the decoded asset URL — the R2 cache key. No normalization,
/// so two distinct URLs always map to distinct keys.
async function cacheKey(assetURL) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(assetURL));
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (let i = 0; i < bytes.length; i++) hex += bytes[i].toString(16).padStart(2, "0");
  return hex;
}

/// Handle one proxy request.
/// @param request  the inbound Request
/// @param env      Worker env: { PROXY_SECRET, IMG_CACHE (R2), MAX_BYTES, ORIGIN_TIMEOUT_MS }
/// @param opts     test seam: { fetchImpl } overrides global fetch for the origin pull
export async function handleRequest(request, env, opts = {}) {
  const fetchImpl = opts.fetchImpl || fetch;
  const url = new URL(request.url);
  if (url.pathname !== "/proxy") return bad(404, "Not Found");

  const u = url.searchParams.get("u");
  const e = url.searchParams.get("e");
  const s = url.searchParams.get("s");
  if (!u || !e || !s) return bad(400, "Missing parameters");

  const expiry = Number(e);
  if (!Number.isFinite(expiry)) return bad(400, "Bad expiry");

  // Percent-decode u to recover the exact assetURL the client signed. This same
  // value is used for BOTH the HMAC payload and the cache key (no further
  // normalization), so client and Worker agree byte-for-byte.
  let assetURL;
  try {
    assetURL = decodeURIComponent(u);
  } catch {
    return bad(400, "Bad u");
  }

  // Verify the signature BEFORE any expiry decision or origin fetch.
  const ok = await verify(env.PROXY_SECRET, expiry, assetURL, s);
  if (!ok) return bad(403, "Invalid signature");

  // Reject expired requests before any origin fetch.
  const now = Math.floor(Date.now() / 1000);
  if (expiry < now) return bad(403, "Expired");

  // Only proxy http(s) origins.
  let parsedAsset;
  try {
    parsedAsset = new URL(assetURL);
  } catch {
    return bad(400, "Bad asset URL");
  }
  if (parsedAsset.protocol !== "http:" && parsedAsset.protocol !== "https:") {
    return bad(400, "Unsupported scheme");
  }

  const key = await cacheKey(assetURL);

  // Cache hit: serve from R2 without re-fetching the origin.
  const cached = await env.IMG_CACHE.get(key);
  if (cached) {
    const contentType = cached.httpMetadata?.contentType || "application/octet-stream";
    return new Response(cached.body, {
      status: 200,
      headers: {
        "content-type": contentType,
        "cache-control": "public, max-age=31536000, immutable",
      },
    });
  }

  // Cache miss: fetch the origin exactly once, stripping cookies and identity.
  const maxBytes = Number(env.MAX_BYTES) || DEFAULT_MAX_BYTES;
  const timeoutMs = Number(env.ORIGIN_TIMEOUT_MS) || DEFAULT_TIMEOUT_MS;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let originRes;
  try {
    originRes = await fetchImpl(assetURL, {
      method: "GET",
      redirect: "follow",
      signal: controller.signal,
      headers: {
        // Neutral UA; no cookies, no referer, no auth carried from the client.
        "user-agent": NEUTRAL_UA,
        accept: "image/*,*/*;q=0.8",
      },
    });
  } catch {
    clearTimeout(timer);
    return bad(502, "Origin fetch failed");
  }
  clearTimeout(timer);

  if (!originRes.ok) {
    return bad(502, "Origin error");
  }

  // Buffer with a hard size cap; oversize => error, store nothing.
  const buf = await originRes.arrayBuffer();
  if (buf.byteLength > maxBytes) {
    return bad(413, "Asset too large");
  }

  const contentType = originRes.headers.get("content-type") || "application/octet-stream";
  await env.IMG_CACHE.put(key, buf, { httpMetadata: { contentType } });

  return new Response(buf, {
    status: 200,
    headers: {
      "content-type": contentType,
      "cache-control": "public, max-age=31536000, immutable",
    },
  });
}

export default {
  async fetch(request, env, _ctx) {
    return handleRequest(request, env);
  },
};
