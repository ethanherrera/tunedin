const apiUrl = requiredLoopbackUrl(Deno.env.get("LOCAL_SUPABASE_URL"));
const publishableKey = requiredValue(
  Deno.env.get("LOCAL_SUPABASE_PUBLISHABLE_KEY"),
);

const tokenResponse = await fetch(
  new URL("auth/v1/token?grant_type=password", apiUrl),
  {
    method: "POST",
    headers: { apikey: publishableKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      email: "listener@tunedin.local",
      password: "tunedIn-local-seeded-account",
    }),
  },
);
assert(tokenResponse.ok, "Local seeded-account authentication failed.");
const tokenPayload = await boundedJson(tokenResponse);
assert(
  isObject(tokenPayload) && typeof tokenPayload.access_token === "string",
  "Missing local session.",
);
const authorization = `Bearer ${tokenPayload.access_token}`;
assert(
  /^Bearer [A-Za-z0-9._~-]+$/.test(authorization),
  "Local access token has an unsupported authorization-header shape.",
);

const userResponse = await fetch(new URL("auth/v1/user", apiUrl), {
  headers: { Authorization: authorization, apikey: publishableKey },
});
assert(
  userResponse.ok,
  `Local seeded session was rejected by Auth (${userResponse.status}).`,
);
const profileResponse = await fetch(
  new URL("rest/v1/profiles?select=id,onboarding_completed_at&limit=1", apiUrl),
  { headers: { Authorization: authorization, apikey: publishableKey } },
);
assert(
  profileResponse.ok,
  `Local seeded session was rejected by PostgREST (${profileResponse.status}).`,
);

const invalid = await catalogRequest({
  operation: "search",
  entity: "artist",
  query: "a",
});
assert(
  invalid.response.status === 400,
  "Short catalog query was not rejected.",
);
assert(
  errorCode(invalid.payload) === "invalid_request",
  "Short query returned the wrong error.",
);

for (
  const scenario of [
    {
      kind: "artist",
      query: "Radiohead",
      expectedMbid: "a74b1b7f-71a5-4011-9441-d0b5e4122711",
    },
    {
      kind: "area",
      query: "San Francisco",
      expectedMbid: "33333333-3333-4333-8333-333333333333",
    },
    {
      kind: "place",
      query: "Fillmore",
      expectedMbid: "44444444-4444-4444-8444-444444444444",
    },
    {
      kind: "song",
      query: "Creep",
      expectedMbid: "66666666-6666-4666-8666-666666666666",
    },
    {
      kind: "tour",
      query: "In Rainbows",
      expectedMbid: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    },
  ] as const
) {
  const search = await catalogRequest({
    operation: "search",
    entity: scenario.kind,
    query: scenario.query,
  });
  assert(
    search.response.ok && isObject(search.payload),
    `Fixture ${scenario.kind} search failed (${search.response.status}:${
      String(errorCode(search.payload))
    }).`,
  );
  assert(
    search.payload.isPartial === false,
    "Healthy fixture search was incorrectly partial.",
  );
  const results = search.payload.results;
  assert(
    Array.isArray(results) && results.length <= 15,
    "Fixture search result bound failed.",
  );
  assert(
    search.payload.limit === 15,
    "Fixture search did not preserve the fixed page size.",
  );
  assert(
    search.payload.isPartial === false,
    "Healthy fixture search was marked partial.",
  );
  const candidate = results.find((result) =>
    isObject(result) && result.origin === "musicbrainz" &&
    result.musicBrainzId === scenario.expectedMbid
  );
  assert(
    isObject(candidate),
    "Expected MusicBrainz-origin fixture result was missing.",
  );

  const resolve = await catalogRequest({
    operation: "resolve",
    entity: scenario.kind,
    musicBrainzId: scenario.expectedMbid,
  });
  assert(
    resolve.response.ok && isObject(resolve.payload),
    "Fixture candidate resolution failed.",
  );
  const entity = resolve.payload.entity;
  assert(
    isObject(entity) && typeof entity.catalogId === "string" &&
      entity.source === "tunedin",
    "Resolved fixture did not return a tunedIn catalog identity.",
  );
  if (scenario.kind === "place") {
    assert(
      isObject(entity.metadata) &&
        typeof entity.metadata.areaCatalogId === "string",
      "Resolved place did not derive a tunedIn area identity.",
    );
  }
}

console.log("Local music catalog fixture gateway verified.");

async function catalogRequest(
  body: unknown,
): Promise<{ response: Response; payload: unknown }> {
  const response = await fetch(new URL("functions/v1/music-catalog", apiUrl), {
    method: "POST",
    headers: {
      Authorization: authorization,
      apikey: publishableKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  return { response, payload: await boundedJson(response) };
}

async function boundedJson(response: Response): Promise<unknown> {
  const text = await response.text();
  assert(
    new TextEncoder().encode(text).byteLength <= 2_000_000,
    "Local response was oversized.",
  );
  try {
    return JSON.parse(text);
  } catch {
    throw new Error("Local endpoint returned malformed JSON.");
  }
}

function errorCode(value: unknown): unknown {
  return isObject(value) && isObject(value.error) ? value.error.code : null;
}

function requiredLoopbackUrl(value: string | undefined): URL {
  if (value === undefined) throw new Error("LOCAL_SUPABASE_URL is required.");
  const url = new URL(value);
  if (
    url.protocol !== "http:" ||
    (url.hostname !== "127.0.0.1" && url.hostname !== "localhost" &&
      url.hostname !== "[::1]")
  ) {
    throw new Error(
      "LOCAL_SUPABASE_URL must use the disposable loopback stack.",
    );
  }
  return url;
}

function requiredValue(value: string | undefined): string {
  if (value === undefined || value.length === 0) {
    throw new Error("Local publishable key is required.");
  }
  return value;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}
