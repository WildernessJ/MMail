import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { sign, verify } from "../src/crypto.js";

const fixture = JSON.parse(
  readFileSync(fileURLToPath(new URL("./vector.json", import.meta.url)), "utf8")
);
const K = fixture.K;
const vectors = fixture.vectors;

for (const [idx, v] of vectors.entries()) {
  const label = `vector ${idx + 1} (${v.A})`;

  test(`sign reproduces the pinned cross-language ${label}`, async () => {
    const s = await sign(K, v.e, v.A);
    assert.equal(s, v.S);
  });

  test(`verify accepts the pinned ${label} signature`, async () => {
    const ok = await verify(K, v.e, v.A, v.S);
    assert.equal(ok, true);
  });

  test(`verify rejects ${label} S with any single byte flipped`, async () => {
    // Flip each character position in turn; every variant must be rejected.
    for (let i = 0; i < v.S.length; i++) {
      const orig = v.S[i];
      // pick a different but still-base64url character
      const repl = orig === "A" ? "B" : "A";
      const tampered = v.S.slice(0, i) + repl + v.S.slice(i + 1);
      assert.notEqual(tampered, v.S, "tampered must differ");
      const ok = await verify(K, v.e, v.A, tampered);
      assert.equal(ok, false, `tampered signature at index ${i} must be rejected`);
    }
  });

  test(`verify rejects a ${label} signature made with the wrong secret`, async () => {
    const wrong = await sign(K + "x", v.e, v.A);
    const ok = await verify(K, v.e, v.A, wrong);
    assert.equal(ok, false);
  });
}

// Regression guard for "decode u exactly once": vector 2's assetURL contains a
// LITERAL %XX (caf%C3%A9, q=a%2Fb). The client mints u with a single RFC-3986
// percent-encoding pass; URLSearchParams (and the Worker) decode it exactly ONCE.
// A second decode would turn %25C3 -> %C3 -> ... corrupting the value, so this
// test pins that ONE decode recovers A2 byte-for-byte and the recovered value
// still verifies against the pinned S2.
test("single-decode of minted u recovers A2 and verifies (no double-decode)", async () => {
  const v2 = vectors[1];
  // Mint u the way the client does: strict RFC-3986 unreserved-only encoding.
  const unreserved = /[A-Za-z0-9\-._~]/;
  const u = [...v2.A]
    .map((ch) =>
      unreserved.test(ch)
        ? ch
        : [...new TextEncoder().encode(ch)]
            .map((b) => "%" + b.toString(16).toUpperCase().padStart(2, "0"))
            .join("")
    )
    .join("");

  // URLSearchParams.get decodes exactly once — the same single decode the Worker
  // relies on. The recovered value must equal A2 byte-for-byte.
  const recovered = new URL(
    `https://proxy.test/proxy?u=${u}&e=${v2.e}&s=${v2.S}`
  ).searchParams.get("u");
  assert.equal(recovered, v2.A, "single decode of u must recover A2 exactly");

  // And the single-decoded value verifies against the pinned signature.
  const ok = await verify(K, v2.e, recovered, v2.S);
  assert.equal(ok, true, "single-decoded A2 must verify against pinned S2");

  // Sanity: a SECOND decode would change the value (proving the bug it guards).
  assert.notEqual(decodeURIComponent(recovered), recovered,
    "double-decode would corrupt A2 — that's exactly what must NOT happen");
});
