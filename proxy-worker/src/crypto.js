// Pure HMAC seam for the image proxy. No I/O, no Worker bindings — just the
// signing payload + base64url HMAC-SHA256 verification, so it can be unit-tested
// with `node --test` and matched against the pinned cross-language vector.
//
// Signing contract (must match MMail's CryptoKit signer):
//   payload   = "<e>:<assetURL>"               (UTF-8 bytes)
//   key       = raw UTF-8 bytes of the secret K
//   signature = base64url( HMAC-SHA256(key, payload) ), '+'->'-', '/'->'_', '=' stripped

/* eslint-disable no-unused-vars */

/// Build the HMAC payload string for an expiry and decoded asset URL.
export function payload(expiry, assetURL) {
  return `${expiry}:${assetURL}`;
}

/// Compute the base64url (no-pad) HMAC-SHA256 signature.
export async function sign(secret, expiry, assetURL) {
  throw new Error("not implemented");
}

/// Constant-time compare of a candidate signature against the freshly computed one.
/// Returns true iff `candidate` is the valid signature for (secret, expiry, assetURL).
export async function verify(secret, expiry, assetURL, candidate) {
  throw new Error("not implemented");
}
