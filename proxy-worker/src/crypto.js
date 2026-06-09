// Pure HMAC seam for the image proxy. No I/O, no Worker bindings — just the
// signing payload + base64url HMAC-SHA256 verification, so it can be unit-tested
// with `node --test` and matched against the pinned cross-language vector.
//
// Signing contract (must match MMail's CryptoKit signer):
//   payload   = "<e>:<assetURL>"               (UTF-8 bytes)
//   key       = raw UTF-8 bytes of the secret K
//   signature = base64url( HMAC-SHA256(key, payload) ), '+'->'-', '/'->'_', '=' stripped

const encoder = new TextEncoder();

/// Build the HMAC payload string for an expiry and decoded asset URL.
export function payload(expiry, assetURL) {
  return `${expiry}:${assetURL}`;
}

function base64url(bytes) {
  // Standard base64 of the raw bytes, then URL-safe + padding-stripped.
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function importKey(secret) {
  return crypto.subtle.importKey(
    "raw",
    encoder.encode(secret), // raw UTF-8 bytes of the secret
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
}

/// Compute the base64url (no-pad) HMAC-SHA256 signature.
export async function sign(secret, expiry, assetURL) {
  const key = await importKey(secret);
  const msg = encoder.encode(payload(expiry, assetURL)); // UTF-8 message bytes
  const mac = await crypto.subtle.sign("HMAC", key, msg);
  return base64url(new Uint8Array(mac));
}

/// Constant-time-ish compare of a candidate signature against the freshly
/// computed one. Returns true iff `candidate` is the valid signature for
/// (secret, expiry, assetURL). The expected signature is recomputed and the
/// strings are compared with a length-independent XOR accumulator.
export async function verify(secret, expiry, assetURL, candidate) {
  if (typeof candidate !== "string" || candidate.length === 0) return false;
  const expected = await sign(secret, expiry, assetURL);
  if (expected.length !== candidate.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= expected.charCodeAt(i) ^ candidate.charCodeAt(i);
  }
  return diff === 0;
}
