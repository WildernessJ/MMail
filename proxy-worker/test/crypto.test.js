import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { sign, verify } from "../src/crypto.js";

const vector = JSON.parse(
  readFileSync(fileURLToPath(new URL("./vector.json", import.meta.url)), "utf8")
);

test("sign reproduces the pinned cross-language vector S", async () => {
  const s = await sign(vector.K, vector.e, vector.A);
  assert.equal(s, vector.S);
});

test("verify accepts the pinned vector signature", async () => {
  const ok = await verify(vector.K, vector.e, vector.A, vector.S);
  assert.equal(ok, true);
});

test("verify rejects S with any single byte flipped", async () => {
  // Flip each character position in turn; every variant must be rejected.
  for (let i = 0; i < vector.S.length; i++) {
    const orig = vector.S[i];
    // pick a different but still-base64url character
    const repl = orig === "A" ? "B" : "A";
    const tampered = vector.S.slice(0, i) + repl + vector.S.slice(i + 1);
    assert.notEqual(tampered, vector.S, "tampered must differ");
    const ok = await verify(vector.K, vector.e, vector.A, tampered);
    assert.equal(ok, false, `tampered signature at index ${i} must be rejected`);
  }
});

test("verify rejects a signature made with the wrong secret", async () => {
  const wrong = await sign(vector.K + "x", vector.e, vector.A);
  const ok = await verify(vector.K, vector.e, vector.A, wrong);
  assert.equal(ok, false);
});
