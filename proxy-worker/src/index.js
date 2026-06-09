// MMail image privacy proxy — Cloudflare Worker entry point.
//
// The request logic lives in `handleRequest` so it can be unit-tested with an
// in-memory mock R2 + mock fetch (see test/handler.test.js). The default export
// just wires the live Worker bindings into it.
//
// Behavior is implemented in T006; this is the testable-stub step (T005).

/* eslint-disable no-unused-vars */

/// Handle one proxy request.
/// @param request  the inbound Request
/// @param env      Worker env: { PROXY_SECRET, IMG_CACHE (R2), MAX_BYTES, ORIGIN_TIMEOUT_MS }
/// @param opts     test seam: { fetchImpl } overrides global fetch for the origin pull
export async function handleRequest(request, env, opts = {}) {
  return new Response("Not Implemented", { status: 501 });
}

export default {
  async fetch(request, env, _ctx) {
    return handleRequest(request, env);
  },
};
