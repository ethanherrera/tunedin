const port = parsePort(Deno.env.get("MUSICBRAINZ_STUB_PORT") ?? "18081");
const fixtureDirectory = new URL(
  "../supabase/functions/music-catalog/fixtures/",
  import.meta.url,
);

const searchFixtures: Record<string, { file: string; collection: string }> = {
  artist: { file: "search-artist-ambiguous.json", collection: "artists" },
  area: { file: "search-area.json", collection: "areas" },
  place: { file: "search-place.json", collection: "places" },
  recording: { file: "search-recording.json", collection: "recordings" },
  series: { file: "search-tour.json", collection: "series" },
  event: { file: "search-event.json", collection: "events" },
};

const lookupFixtures: Record<string, Record<string, string>> = {
  artist: {
    "a74b1b7f-71a5-4011-9441-d0b5e4122711": "lookup-artist.json",
  },
  area: {
    "33333333-3333-4333-8333-333333333333": "lookup-area.json",
  },
  place: {
    "44444444-4444-4444-8444-444444444444": "lookup-place.json",
    "55555555-5555-4555-8555-555555555555": "lookup-place-without-area.json",
  },
  recording: {
    "66666666-6666-4666-8666-666666666666": "lookup-recording-with-work.json",
  },
  series: {
    "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa": "lookup-tour.json",
    "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb":
      "lookup-tour-without-relations.json",
  },
};

Deno.serve({ hostname: "0.0.0.0", port }, async (request) => {
  if (request.method !== "GET") {
    return json({ error: "method not allowed" }, 405);
  }
  const accept = request.headers.get("accept")?.toLowerCase() ?? "";
  const userAgent = request.headers.get("user-agent") ?? "";
  if (
    !accept.includes("application/json") || !userAgent.startsWith("tunedIn/")
  ) {
    return json({ error: "missing required fixture headers" }, 400);
  }

  const url = new URL(request.url);
  const match = url.pathname.match(
    /^\/ws\/2\/(artist|area|place|recording|series|event)(?:\/([0-9a-f-]+))?$/,
  );
  if (match === null) return json({ error: "fixture route not found" }, 404);
  const endpoint = match[1];
  const musicBrainzId = match[2];

  if (musicBrainzId !== undefined) {
    if (
      endpoint === "artist" &&
      musicBrainzId === "11111111-1111-4111-8111-111111111111"
    ) {
      return new Response(null, {
        status: 301,
        headers: {
          location:
            "/ws/2/artist/a74b1b7f-71a5-4011-9441-d0b5e4122711?fmt=json",
        },
      });
    }
    const fixtureName = lookupFixtures[endpoint]?.[musicBrainzId];
    if (fixtureName === undefined) {
      return json({ error: "fixture lookup not found" }, 404);
    }
    return fixtureResponse(fixtureName);
  }

  const query = (url.searchParams.get("query") ?? "").toLocaleLowerCase(
    "en-US",
  );
  if (query.includes("fixture-timeout")) {
    await new Promise((resolve) => setTimeout(resolve, 9_000));
  }
  if (query.includes("fixture-429")) {
    return json({ error: "fixture rate limited" }, 429, { "retry-after": "3" });
  }
  if (query.includes("fixture-503")) {
    return json({ error: "fixture unavailable" }, 503);
  }
  if (query.includes("fixture-malformed")) {
    return new Response(await readFixture("malformed.json"), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }
  if (query.includes("fixture-oversized")) {
    return json({ value: "x".repeat(1_000_001) });
  }

  const descriptor = searchFixtures[endpoint];
  if (descriptor === undefined) {
    return json({ error: "fixture search not found" }, 404);
  }
  const offset = parseOffset(url.searchParams.get("offset"));
  if (query.includes("fixture-empty")) {
    return json({
      created: "2026-07-15T00:00:00Z",
      count: 0,
      offset,
      [descriptor.collection]: [],
    });
  }
  const payload = JSON.parse(await readFixture(descriptor.file)) as Record<
    string,
    unknown
  >;
  payload.offset = offset;
  if (offset > 0) payload[descriptor.collection] = [];
  return json(payload);
});

async function fixtureResponse(name: string): Promise<Response> {
  return new Response(await readFixture(name), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function readFixture(name: string): Promise<string> {
  return await Deno.readTextFile(new URL(name, fixtureDirectory));
}

function json(
  body: unknown,
  status = 200,
  extraHeaders: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      ...Object.fromEntries(new Headers(extraHeaders)),
    },
  });
}

function parseOffset(value: string | null): number {
  const offset = Number(value ?? "0");
  return Number.isInteger(offset) && offset >= 0 ? offset : 0;
}

function parsePort(value: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1_024 || parsed > 65_535) {
    throw new Error(
      "MUSICBRAINZ_STUB_PORT must be an integer from 1024 through 65535.",
    );
  }
  return parsed;
}
