import assert from "node:assert/strict";
import { CatalogError } from "../errors.ts";
import { decodeEntity, decodeSearchPayload, MusicBrainzClient } from "../musicbrainz.ts";

const fixtures = new URL("../fixtures/", import.meta.url);
const baseUrl = new URL("http://127.0.0.1:18081/ws/2/");
const userAgent = "tunedIn/test (mailto:test@example.com)";

Deno.test("committed fixtures decode all catalog kinds and place area limitations", async () => {
  const artists = decodeSearchPayload(
    "artist",
    await fixtureJson("search-artist-ambiguous.json"),
    0,
  );
  assert.equal(artists.results.length, 2);
  assert.equal(artists.results[0].metadata.artistType, "Group");
  assert.equal(artists.results[0].metadata.areaCatalogId, null);

  const area = decodeEntity("area", await fixtureJson("lookup-area.json"));
  assert.equal(area.metadata.subdivisionCode, "US-CA");

  const place = decodeEntity("place", await fixtureJson("lookup-place.json"));
  assert.equal(place.metadata.areaName, "San Francisco");
  assert.equal(place.metadata.areaCatalogId, null);
  const placeWithoutArea = decodeEntity(
    "place",
    await fixtureJson("lookup-place-without-area.json"),
  );
  assert.equal(placeWithoutArea.metadata.areaMusicBrainzId, null);

  const recording = decodeEntity("song", await fixtureJson("lookup-recording-with-work.json"));
  assert.equal(recording.metadata.workMusicBrainzId, "99999999-9999-4999-8999-999999999999");
  assert.deepEqual(recording.metadata.artistCredit, [{
    artistCatalogId: null,
    artistMusicBrainzId: "a74b1b7f-71a5-4011-9441-d0b5e4122711",
    name: "Radio Head",
    canonicalName: "Radiohead",
    joinPhrase: "",
  }]);

  const tour = decodeEntity("tour", await fixtureJson("lookup-tour.json"));
  assert.equal(tour.metadata.seriesType, "Tour");
  assert.deepEqual(tour.metadata.artistCredit, [{
    artistCatalogId: null,
    artistMusicBrainzId: "a74b1b7f-71a5-4011-9441-d0b5e4122711",
    name: "Radiohead",
    canonicalName: "Radiohead",
    joinPhrase: "",
  }]);
  const uncreditedTour = decodeEntity(
    "tour",
    await fixtureJson("lookup-tour-without-relations.json"),
  );
  assert.deepEqual(uncreditedTour.metadata.artistCredit, []);
});

Deno.test("recording artist context constrains the Lucene query and ranks matching credits", async () => {
  const captured: { url?: URL } = {};
  const client = new MusicBrainzClient({
    baseUrl,
    userAgent,
    fetch: (input) => {
      captured.url = new URL(String(input));
      return Promise.resolve(jsonResponse(awaitableFixture("search-recording.json")));
    },
  });
  const context = [{
    catalogId: "e1000000-0000-4000-8000-000000000002",
    musicBrainzId: "88888888-8888-4888-8888-888888888888",
    name: "Fixture Singer",
  }];

  const response = await client.search("song", "Creep", 0, context);

  assert.equal(
    captured.url?.searchParams.get("query"),
    'recording:"Creep" AND (arid:88888888-8888-4888-8888-888888888888)',
  );
  assert.equal(response.results[0].musicBrainzId, "77777777-7777-4777-8777-777777777777");
});

Deno.test("Series search stays global even when local tour ranking has artist context", async () => {
  const captured: { url?: URL } = {};
  const client = new MusicBrainzClient({
    baseUrl,
    userAgent,
    fetch: (input) => {
      captured.url = new URL(String(input));
      return Promise.resolve(jsonResponse(awaitableFixture("search-tour.json")));
    },
  });

  await client.search("tour", "In Rainbows", 0, [{
    catalogId: "e1000000-0000-4000-8000-000000000001",
    musicBrainzId: "a74b1b7f-71a5-4011-9441-d0b5e4122711",
    name: "Radiohead",
  }]);

  assert.equal(
    captured.url?.searchParams.get("query"),
    'series:"In Rainbows" AND type:"Tour"',
  );
});

Deno.test("MusicBrainz search sends JSON headers, meaningful User-Agent, bounds, and escaped query", async () => {
  const captured: { url?: URL; headers?: Headers } = {};
  const client = new MusicBrainzClient({
    baseUrl,
    userAgent,
    fetch: (input, init) => {
      captured.url = new URL(String(input));
      captured.headers = new Headers(init?.headers);
      return Promise.resolve(jsonResponse(awaitableFixture("search-artist-ambiguous.json")));
    },
  });
  const response = await client.search("artist", "AC/DC + artist:other", 0, []);
  assert.equal(response.results.length, 2);
  assert.equal(captured.headers?.get("accept"), "application/json");
  assert.equal(captured.headers?.get("user-agent"), userAgent);
  assert.equal(captured.url?.searchParams.get("limit"), "15");
  assert.equal(captured.url?.searchParams.get("offset"), "0");
  assert.equal(captured.url?.searchParams.get("query"), 'artist:"AC\\/DC \\+ artist\\:other"');
});

Deno.test("lookup follows bounded same-origin redirects and reserves another slot", async () => {
  const lookup = await fixtureText("lookup-artist.json");
  let calls = 0;
  let redirectReservations = 0;
  const client = new MusicBrainzClient({
    baseUrl,
    userAgent,
    beforeRedirect: () => {
      redirectReservations += 1;
      return Promise.resolve();
    },
    fetch: () => {
      calls += 1;
      if (calls === 1) {
        return Promise.resolve(
          new Response(null, {
            status: 301,
            headers: {
              location: "/ws/2/artist/a74b1b7f-71a5-4011-9441-d0b5e4122711?fmt=json",
            },
          }),
        );
      }
      return Promise.resolve(jsonResponse(lookup));
    },
  });
  const result = await client.lookup("artist", "11111111-1111-4111-8111-111111111111");
  assert.equal(result.musicBrainzId, "a74b1b7f-71a5-4011-9441-d0b5e4122711");
  assert.equal(calls, 2);
  assert.equal(redirectReservations, 1);
});

Deno.test("lookup requires song credits but accepts Tour series without artist relations", async () => {
  const noCredits = JSON.stringify({
    id: "66666666-6666-4666-8666-666666666666",
    title: "Missing credits",
    "artist-credit": [],
  });
  const songClient = fixtureClient(() => Promise.resolve(jsonResponse(noCredits)));
  await assert.rejects(
    () => songClient.lookup("song", "66666666-6666-4666-8666-666666666666"),
    isCatalogError("upstream_invalid_response"),
  );

  const tourText = await fixtureText("lookup-tour-without-relations.json");
  const tourClient = fixtureClient(() => Promise.resolve(jsonResponse(tourText)));
  const tour = await tourClient.lookup("tour", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb");
  assert.deepEqual(tour.metadata.artistCredit, []);
});

Deno.test("429, 503, malformed, oversized, and timeout responses map to typed safe errors", async () => {
  const rateLimited = fixtureClient(() =>
    Promise.resolve(
      new Response("{}", {
        status: 429,
        headers: { "content-type": "application/json", "retry-after": "3" },
      }),
    )
  );
  await assert.rejects(
    () => rateLimited.search("artist", "Radiohead", 0, []),
    (error) =>
      error instanceof CatalogError && error.code === "upstream_rate_limited" &&
      error.retryAfterSeconds === 3,
  );

  const unavailable = fixtureClient(() =>
    Promise.resolve(
      new Response("{}", {
        status: 503,
        headers: { "content-type": "application/json" },
      }),
    )
  );
  await assert.rejects(
    () => unavailable.search("artist", "Radiohead", 0, []),
    isCatalogError("upstream_unavailable"),
  );

  const malformed = await fixtureText("malformed.json");
  const malformedClient = fixtureClient(() => Promise.resolve(jsonResponse(malformed)));
  await assert.rejects(
    () => malformedClient.search("artist", "Radiohead", 0, []),
    isCatalogError("upstream_invalid_response"),
  );

  const oversized = fixtureClient(() =>
    Promise.resolve(
      new Response("{}", {
        status: 200,
        headers: { "content-type": "application/json", "content-length": "1000001" },
      }),
    )
  );
  await assert.rejects(
    () => oversized.search("artist", "Radiohead", 0, []),
    isCatalogError("upstream_invalid_response"),
  );

  const timedOut = new MusicBrainzClient({
    baseUrl,
    userAgent,
    timeoutMs: 5,
    fetch: (_input, init) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () =>
          reject(new DOMException("aborted", "AbortError")));
      }),
  });
  await assert.rejects(
    () => timedOut.search("artist", "Radiohead", 0, []),
    isCatalogError("upstream_timeout"),
  );

  const stalledBody = new MusicBrainzClient({
    baseUrl,
    userAgent,
    timeoutMs: 5,
    fetch: (_input, init) => {
      const stream = new ReadableStream<Uint8Array>({
        start(controller) {
          controller.enqueue(new TextEncoder().encode('{"artists":['));
          init?.signal?.addEventListener(
            "abort",
            () => controller.error(new DOMException("aborted", "AbortError")),
          );
        },
      });
      return Promise.resolve(
        new Response(stream, {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    },
  });
  await assert.rejects(
    () => stalledBody.search("artist", "Radiohead", 0, []),
    isCatalogError("upstream_timeout"),
  );
});

function fixtureClient(transport: typeof fetch): MusicBrainzClient {
  return new MusicBrainzClient({ baseUrl, userAgent, fetch: transport });
}

function jsonResponse(body: string): Response {
  return new Response(body, { status: 200, headers: { "content-type": "application/json" } });
}

function awaitableFixture(name: string): string {
  return Deno.readTextFileSync(new URL(name, fixtures));
}

async function fixtureText(name: string): Promise<string> {
  return await Deno.readTextFile(new URL(name, fixtures));
}

async function fixtureJson(name: string): Promise<unknown> {
  return JSON.parse(await fixtureText(name));
}

function isCatalogError(code: string): (error: unknown) => boolean {
  return (error) => error instanceof CatalogError && error.code === code;
}
