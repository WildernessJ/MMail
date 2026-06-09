# MMail Image Privacy Proxy (Cloudflare Worker + R2)

A single-tenant Cloudflare Worker that lets MMail load remote `<img>` images for
trusted/explicitly-loaded senders **without** revealing your IP, location, or
repeat-open timing to the sender's origin server. MMail rewrites each remote
`<img src>` into a short-lived HMAC-signed proxy URL; this Worker verifies the
signature, fetches the asset **once** (stripping cookies, sending a neutral
user-agent), caches the body in R2 keyed by `SHA-256(assetURL)`, and streams it
back. Repeat opens are served from R2 — the origin is hit at most once per asset.

It is **single-tenant by design**: only your MMail build holds the signing
secret, so there are no other users and no cross-user cache concerns.

> Scope note: Tier 3 hides your IP/location/repeat-open timing, NOT the *fact*
> of opening (a per-recipient pixel URL still confirms receipt on first fetch).
> See `specs/image-privacy-proxy.md` Non-Goals.

## Layout

- `src/index.js` — Worker entry (`fetch`) + testable `handleRequest`.
- `src/crypto.js` — pure HMAC-SHA256 sign/verify (base64url, no padding).
- `wrangler.toml` — Worker config: R2 binding `IMG_CACHE`, tunable `MAX_BYTES`
  (10 MB) and `ORIGIN_TIMEOUT_MS` (10 s). The `PROXY_SECRET` is **not** here —
  it is set out-of-band via `wrangler secret put` (never committed).
- `test/` — `node --test` suite (`crypto.test.js`, `handler.test.js`) plus the
  pinned cross-language vector `vector.json`.

## Run the tests (no Cloudflare account needed)

Requires Node 20+ (global `crypto.subtle`).

```sh
cd proxy-worker
node --version   # must be >= 20
node --test
```

## Deploy (USER STEP — needs your Cloudflare account)

You provision and deploy this yourself; MMail never does it for you.

```sh
cd proxy-worker

# 1. Authenticate (opens a browser).
npx wrangler login

# 2. Create the R2 bucket named in wrangler.toml (binding IMG_CACHE).
npx wrangler r2 bucket create mmail-img-cache

# 3. Set the shared signing secret. Choose a strong random string and RECORD it —
#    you will paste the SAME string into MMail (Settings -> "Image proxy secret",
#    stored only in the macOS Keychain). It is never written to a file or committed.
npx wrangler secret put PROXY_SECRET

# 4. Deploy.
npx wrangler deploy
```

After deploy, note the Worker URL (e.g. `https://mmail-image-proxy.<you>.workers.dev`).
Use that as the **proxy base URL** in MMail Settings (the toggle defaults ON).

## Live-verify with curl (USER STEP)

Mint a signed URL the way MMail does and confirm the four behaviors. Using the
same recipe as the pinned vector:

```sh
BASE='https://mmail-image-proxy.<you>.workers.dev'
SECRET='<the string you set via wrangler secret put>'
ASSET='https://www.gravatar.com/avatar/0?s=80'   # any public image

# expiry = now + 300s (MMail uses floor(now)+300)
E=$(( $(date +%s) + 300 ))

# u = RFC-3986 percent-encoded asset (space -> %20, never +)
U=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$ASSET")

# s = base64url( HMAC-SHA256(key=SECRET bytes, msg="<E>:<ASSET>") )
S=$(printf '%s' "${E}:${ASSET}" | openssl dgst -sha256 -hmac "$SECRET" -binary \
      | openssl base64 | tr '+/' '-_' | tr -d '=')

# (a) valid signed URL -> 200 + the origin image's content-type
curl -i "${BASE}/proxy?u=${U}&e=${E}&s=${S}"

# (b) tampered signature -> 4xx, no origin fetch
curl -i "${BASE}/proxy?u=${U}&e=${E}&s=${S}AAAA"

# (c) expired expiry -> 4xx, no origin fetch
EP=$(( $(date +%s) - 10 ))
SP=$(printf '%s' "${EP}:${ASSET}" | openssl dgst -sha256 -hmac "$SECRET" -binary \
      | openssl base64 | tr '+/' '-_' | tr -d '=')
curl -i "${BASE}/proxy?u=${U}&e=${EP}&s=${SP}"

# (d) request (a) again -> still 200, served from R2 (origin not re-hit).
#     Confirm via `npx wrangler tail` (no second origin request) or the R2 object
#     count in the Cloudflare dashboard.
curl -i "${BASE}/proxy?u=${U}&e=${E}&s=${S}"
```

Expected: 200 / 4xx / 4xx / cache-hit (second `(a)` served from R2).

## Tuning

Edit `[vars]` in `wrangler.toml` and re-deploy:

- `MAX_BYTES` — hard cap on a fetched asset (default 10 MB). Oversize → error,
  nothing stored.
- `ORIGIN_TIMEOUT_MS` — origin fetch timeout (default 10 s). Timeout → error,
  nothing stored.

Cache entries have no TTL by design (origin-hit-once is the goal; stale email
images are acceptable). R2 growth is bounded by your own image volume.
