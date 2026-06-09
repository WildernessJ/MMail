// MMail image privacy proxy — Cloudflare Worker entry point.
//
// Scaffold only (T001). Behavior is added in T006 once the crypto seam (T004)
// and the handler test (T005) are in place.

export default {
  async fetch(_request, _env, _ctx) {
    return new Response("Not Implemented", { status: 501 });
  },
};
