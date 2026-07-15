import assert from "node:assert/strict";
import { verifyDeployedFunction } from "../verify-deployed-function.ts";

Deno.test("returns the positive version for one active matching function", () => {
  const verified = verifyDeployedFunction(
    JSON.stringify([
      {
        slug: "another-function",
        status: "ACTIVE",
        version: 12,
      },
      {
        slug: "music-catalog",
        status: "ACTIVE",
        version: 7,
      },
    ]),
    "music-catalog",
  );

  assert.deepEqual(verified, {
    slug: "music-catalog",
    status: "ACTIVE",
    version: 7,
  });
});

Deno.test("rejects missing, duplicate, and inactive matching functions", () => {
  assert.throws(
    () => verifyDeployedFunction("[]", "music-catalog"),
    /does not contain music-catalog/,
  );
  assert.throws(
    () =>
      verifyDeployedFunction(
        JSON.stringify([
          { slug: "music-catalog", status: "ACTIVE", version: 1 },
          { slug: "music-catalog", status: "ACTIVE", version: 2 },
        ]),
        "music-catalog",
      ),
    /duplicate music-catalog/,
  );
  assert.throws(
    () =>
      verifyDeployedFunction(
        JSON.stringify([{
          slug: "music-catalog",
          status: "FAILED",
          version: 3,
        }]),
        "music-catalog",
      ),
    /not active/,
  );
  assert.throws(
    () =>
      verifyDeployedFunction(
        JSON.stringify([{
          slug: "music-catalog",
          status: "active",
          version: 3,
        }]),
        "music-catalog",
      ),
    /not active/,
  );
});

Deno.test("rejects malformed envelopes and invalid versions without including their contents", () => {
  assert.throws(
    () => verifyDeployedFunction('{"secret":"do-not-echo"}', "music-catalog"),
    (error) => error instanceof Error && !error.message.includes("do-not-echo"),
  );

  for (const version of [0, -1, 1.5, "9", null]) {
    assert.throws(
      () =>
        verifyDeployedFunction(
          JSON.stringify([{
            slug: "music-catalog",
            status: "ACTIVE",
            version,
          }]),
          "music-catalog",
        ),
      /invalid version/,
    );
  }
});

Deno.test("requires a safe function slug", () => {
  assert.throws(
    () => verifyDeployedFunction("[]", "music-catalog\nversion=999"),
    /slug is invalid/,
  );
});
