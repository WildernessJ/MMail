import { test } from "node:test";
import assert from "node:assert/strict";
import { handleRequest } from "../src/index.js";
import { sign } from "../src/crypto.js";

// --- In-memory mock R2 bucket (subset of the R2Bucket API the Worker uses) ---
function mockR2() {
  const store = new Map();
  let gets = 0;
  let puts = 0;
  return {
    store,
    get gets() { return gets; },
    get puts() { return puts; },
    async get(key) {
      gets++;
      const v = store.get(key);
      if (!v) return null;
      return {
        body: v.body, // ReadableStream-ish; tests read via arrayBuffer/text
        httpMetadata: { contentType: v.contentType },
        async arrayBuffer() { return v.body; },
      };
    },
    async put(key, value, opts) {
      puts++;
      const buf = value instanceof ArrayBuffer ? value : new TextEncoder().encode(value).buffer;
      store.set(key, {
        body: buf,
        contentType: opts?.httpMetadata?.contentType,
      });
    },
  };
}

// --- Mock fetch: records calls, returns a scripted response ---
function mockFetch(script) {
  const fn = async (url, init) => {
    fn.calls++;
    fn.lastURL = typeof url === "string" ? url : url.url;
    fn.lastInit = init;
    return script(url, init);
  };
  fn.calls = 0;
  return fn;
}

function okImageResponse(bytes = new Uint8Array([1, 2, 3, 4]), type = "image/gif") {
  return new Response(bytes, { status: 200, headers: { "content-type": type } });
}

const SECRET = "handler-test-secret";
const ASSET = "https://origin.test/pixel.gif?id=ME";

function futureExpiry() { return Math.floor(Date.now() / 1000) + 300; }
function pastExpiry() { return Math.floor(Date.now() / 1000) - 10; }

async function signedURL(asset, expiry, secret = SECRET) {
  const s = await sign(secret, expiry, asset);
  const u = encodeURIComponent(asset);
  return `https://proxy.test/proxy?u=${u}&e=${expiry}&s=${s}`;
}

function makeEnv(overrides = {}) {
  return {
    PROXY_SECRET: SECRET,
    IMG_CACHE: mockR2(),
    MAX_BYTES: "10485760",
    ORIGIN_TIMEOUT_MS: "10000",
    ...overrides,
  };
}

test("valid sig + cache miss: origin fetched exactly once, stored, streamed", async () => {
  const env = makeEnv();
  const fetchFn = mockFetch(() => okImageResponse());
  const req = new Request(await signedURL(ASSET, futureExpiry()));
  const res = await handleRequest(req, env, { fetchImpl: fetchFn });

  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "image/gif");
  assert.equal(fetchFn.calls, 1, "origin fetched exactly once");
  assert.equal(env.IMG_CACHE.puts, 1, "body stored in R2 once");
  const body = new Uint8Array(await res.arrayBuffer());
  assert.deepEqual([...body], [1, 2, 3, 4]);
});

test("valid sig + cache hit: served from R2, origin not re-fetched", async () => {
  const env = makeEnv();
  const fetchFn = mockFetch(() => okImageResponse(new Uint8Array([9, 9])));
  // Prime the cache via a miss.
  await handleRequest(new Request(await signedURL(ASSET, futureExpiry())), env, {
    fetchImpl: fetchFn,
  });
  assert.equal(fetchFn.calls, 1);

  // Second request for the same asset: must be served from R2.
  const res = await handleRequest(new Request(await signedURL(ASSET, futureExpiry())), env, {
    fetchImpl: fetchFn,
  });
  assert.equal(res.status, 200);
  assert.equal(fetchFn.calls, 1, "origin NOT fetched on cache hit");
  const body = new Uint8Array(await res.arrayBuffer());
  assert.deepEqual([...body], [9, 9]);
});

test("bad signature: 4xx, no origin fetch", async () => {
  const env = makeEnv();
  const fetchFn = mockFetch(() => okImageResponse());
  const good = await signedURL(ASSET, futureExpiry());
  const tampered = good.slice(0, -1) + (good.endsWith("A") ? "B" : "A");
  const res = await handleRequest(new Request(tampered), env, { fetchImpl: fetchFn });
  assert.ok(res.status >= 400 && res.status < 500, `expected 4xx, got ${res.status}`);
  assert.equal(fetchFn.calls, 0, "no origin fetch on bad sig");
  assert.equal(env.IMG_CACHE.puts, 0);
});

test("expired expiry: 4xx, no origin fetch", async () => {
  const env = makeEnv();
  const fetchFn = mockFetch(() => okImageResponse());
  const res = await handleRequest(new Request(await signedURL(ASSET, pastExpiry())), env, {
    fetchImpl: fetchFn,
  });
  assert.ok(res.status >= 400 && res.status < 500, `expected 4xx, got ${res.status}`);
  assert.equal(fetchFn.calls, 0, "no origin fetch on expired");
  assert.equal(env.IMG_CACHE.puts, 0);
});

test("oversize origin: error status, nothing stored", async () => {
  const env = makeEnv({ MAX_BYTES: "4" });
  const big = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]); // 8 bytes > 4-byte cap
  const fetchFn = mockFetch(() => okImageResponse(big));
  const res = await handleRequest(new Request(await signedURL(ASSET, futureExpiry())), env, {
    fetchImpl: fetchFn,
  });
  assert.ok(res.status >= 400, `expected error status, got ${res.status}`);
  assert.equal(env.IMG_CACHE.puts, 0, "oversize asset must not be stored");
});

test("origin error: error status, nothing stored", async () => {
  const env = makeEnv();
  const fetchFn = mockFetch(() => new Response("boom", { status: 502 }));
  const res = await handleRequest(new Request(await signedURL(ASSET, futureExpiry())), env, {
    fetchImpl: fetchFn,
  });
  assert.ok(res.status >= 400, `expected error status, got ${res.status}`);
  assert.equal(env.IMG_CACHE.puts, 0, "failed origin must not be stored");
});

test("distinct asset URLs map to distinct cache keys", async () => {
  const env = makeEnv();
  const a1 = "https://origin.test/a.gif";
  const a2 = "https://origin.test/b.gif";
  const fetchFn = mockFetch((url) =>
    okImageResponse(new Uint8Array(String(url).includes("a.gif") ? [1] : [2]))
  );
  await handleRequest(new Request(await signedURL(a1, futureExpiry())), env, { fetchImpl: fetchFn });
  await handleRequest(new Request(await signedURL(a2, futureExpiry())), env, { fetchImpl: fetchFn });
  assert.equal(fetchFn.calls, 2, "two distinct assets fetched separately");
  assert.equal(env.IMG_CACHE.store.size, 2, "two distinct cache keys");
});
