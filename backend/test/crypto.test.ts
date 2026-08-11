import { describe, expect, it } from "vitest";

import { decryptSecret, encryptSecret, randomToken, sha256 } from "../src/crypto";

describe("provider secret encryption", () => {
  const key = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));

  it("round trips without exposing plaintext", async () => {
    const encrypted = await encryptSecret("sk_live_secret", key);
    expect(encrypted).not.toContain("sk_live_secret");
    await expect(decryptSecret(encrypted, key)).resolves.toBe("sk_live_secret");
  });

  it("uses a unique IV", async () => {
    const first = await encryptSecret("same", key);
    const second = await encryptSecret("same", key);
    expect(first).not.toBe(second);
  });
});

describe("oauth state", () => {
  it("creates URL-safe, high-entropy values", () => {
    expect(randomToken()).toMatch(/^[A-Za-z0-9_-]{43}$/);
  });

  it("hashes deterministically", async () => {
    await expect(sha256("state")).resolves.toBe(
      "4ba69735ca53765ed6a709edb56c6ea236b7193a3b29a6b390c346f0f4340e4e",
    );
  });
});
