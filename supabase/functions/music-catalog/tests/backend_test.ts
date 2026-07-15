import assert from "node:assert/strict";
import { SupabaseCatalogBackend } from "../backend.ts";
import { CatalogError } from "../errors.ts";

const supabaseUrl = new URL("http://127.0.0.1:54321/");
const authorization = "Bearer fixture-token";
const profileId = "d1000000-0000-4000-8000-000000000001";

Deno.test("Supabase backend authenticates, requires onboarding, and strictly decodes local metadata", async () => {
  const requests: Request[] = [];
  const backend = new SupabaseCatalogBackend({
    supabaseUrl,
    anonymousKey: "fixture-anon",
    serviceRoleKey: "fixture-service",
    fetch: (input, init) => {
      const request = new Request(input, init);
      requests.push(request);
      if (request.url.includes("/auth/v1/user")) {
        return Promise.resolve(json({ id: profileId }));
      }
      if (request.url.includes("/rest/v1/profiles")) {
        return Promise.resolve(
          json([{ id: profileId, onboarding_completed_at: "2026-07-15T00:00:00Z" }]),
        );
      }
      if (request.url.includes("/rpc/search_catalog")) {
        return Promise.resolve(json([localPlaceRow()]));
      }
      throw new Error("Unexpected fixture request");
    },
  });

  const profile = await backend.authenticate(authorization);
  const results = await backend.searchLocal(profile, "place", "Fillmore", [], null, 20, 0);
  assert.equal(results.length, 1);
  assert.equal(results[0].metadata.areaCatalogId, "e3000000-0000-4000-8000-000000000003");
  assert.equal(results[0].metadata.areaName, "San Francisco");
  assert.equal(requests[0].headers.get("apikey"), "fixture-anon");
  assert.equal(requests[2].headers.get("authorization"), authorization);
  assert.equal((await requests[2].clone().json()).p_concert_id, null);
});

Deno.test("Supabase backend rejects an incomplete profile", async () => {
  const backend = new SupabaseCatalogBackend({
    supabaseUrl,
    anonymousKey: "fixture-anon",
    serviceRoleKey: "fixture-service",
    fetch: (input) => {
      const url = String(input);
      return Promise.resolve(url.includes("/auth/v1/user") ? json({ id: profileId }) : json([]));
    },
  });
  await assert.rejects(
    () => backend.authenticate(authorization),
    (error) => error instanceof CatalogError && error.code === "profile_required",
  );
});

Deno.test("privileged RPCs use only the service-role authorization boundary", async () => {
  const requests: Request[] = [];
  const backend = new SupabaseCatalogBackend({
    supabaseUrl,
    anonymousKey: "fixture-anon",
    serviceRoleKey: "fixture-service",
    fetch: (input, init) => {
      const request = new Request(input, init);
      requests.push(request);
      return Promise.resolve(json(storedArtistRow()));
    },
  });
  const result = await backend.upsertMusicBrainz({
    kind: "artist",
    musicBrainzId: "a74b1b7f-71a5-4011-9441-d0b5e4122711",
    displayName: "Radiohead",
    sortName: "Radiohead",
    disambiguation: null,
    metadata: {
      artist_type: "Group",
      country_code: "GB",
      area_name: "United Kingdom",
      life_span_begin: "1991",
      life_span_end: null,
      ended: false,
    },
    artistCredits: [],
  });
  assert.equal(result.catalogId, "e1000000-0000-4000-8000-000000000001");
  assert.equal(requests[0].headers.get("authorization"), "Bearer fixture-service");
  assert.equal(requests[0].headers.get("apikey"), "fixture-service");
  assert.equal((await requests[0].clone().json()).p_kind, "artist");
});

Deno.test("artist search context uses the service role and forwards shared-concert context", async () => {
  const requests: Request[] = [];
  const artistIds = [
    "e1000000-0000-4000-8000-000000000001",
    "e1000000-0000-4000-8000-000000000002",
  ];
  const concertId = "c1000000-0000-4000-8000-000000000001";
  const backend = new SupabaseCatalogBackend({
    supabaseUrl,
    anonymousKey: "fixture-anon",
    serviceRoleKey: "fixture-service",
    fetch: (input, init) => {
      requests.push(new Request(input, init));
      return Promise.resolve(json([
        {
          catalog_id: artistIds[0],
          musicbrainz_mbid: "a74b1b7f-71a5-4011-9441-d0b5e4122711",
          display_name: "Radiohead",
        },
        {
          catalog_id: artistIds[1],
          musicbrainz_mbid: null,
          display_name: "Saved Custom Artist",
        },
      ]));
    },
  });

  const contexts = await backend.getArtistSearchContext(
    { id: profileId, authorization },
    artistIds,
    concertId,
  );

  assert.deepEqual(contexts.map((context) => context.catalogId), artistIds);
  assert.equal(requests[0].headers.get("authorization"), "Bearer fixture-service");
  const body = await requests[0].clone().json();
  assert.deepEqual(body, {
    p_profile_id: profileId,
    p_artist_ids: artistIds,
    p_concert_id: concertId,
  });
});

Deno.test("only the exact quota and queue database outcomes receive public typed errors", async () => {
  const matchingQuota = rpcErrorBackend(
    400,
    "P0001",
    "Catalog search limit reached. Try again later.",
  );
  await assert.rejects(
    () => matchingQuota.consumeSearchQuota(profileId),
    (error) => error instanceof CatalogError && error.code === "search_quota_exceeded",
  );

  const missingQuotaRpc = rpcErrorBackend(404, "42883", "function does not exist");
  await assert.rejects(
    () => missingQuotaRpc.consumeSearchQuota(profileId),
    (error) => error instanceof CatalogError && error.code === "internal_error",
  );

  const matchingQueue = rpcErrorBackend(400, "P0001", "MusicBrainz is busy. Try again shortly.");
  await assert.rejects(
    () => matchingQueue.reserveRequestSlot(5_000),
    (error) => error instanceof CatalogError && error.code === "queue_timeout",
  );

  const invalidQueueArgument = rpcErrorBackend(
    400,
    "22023",
    "MusicBrainz queue wait is out of range",
  );
  await assert.rejects(
    () => invalidQueueArgument.reserveRequestSlot(5_000),
    (error) => error instanceof CatalogError && error.code === "internal_error",
  );
});

Deno.test("auth infrastructure failures are retryable internal errors, not invalid sessions", async () => {
  const unavailable = new SupabaseCatalogBackend({
    supabaseUrl,
    anonymousKey: "fixture-anon",
    serviceRoleKey: "fixture-service",
    fetch: () => Promise.resolve(json({ message: "unavailable" }, 503)),
  });
  await assert.rejects(
    () => unavailable.authenticate(authorization),
    (error) => error instanceof CatalogError && error.code === "internal_error" && error.retryable,
  );

  const invalidSession = new SupabaseCatalogBackend({
    supabaseUrl,
    anonymousKey: "fixture-anon",
    serviceRoleKey: "fixture-service",
    fetch: () => Promise.resolve(json({ message: "invalid" }, 401)),
  });
  await assert.rejects(
    () => invalidSession.authenticate(authorization),
    (error) => error instanceof CatalogError && error.code === "authentication_required",
  );
});

function rpcErrorBackend(status: number, code: string, message: string) {
  return new SupabaseCatalogBackend({
    supabaseUrl,
    anonymousKey: "fixture-anon",
    serviceRoleKey: "fixture-service",
    fetch: () => Promise.resolve(json({ code, message }, status)),
  });
}

function localPlaceRow() {
  return {
    id: "e4000000-0000-4000-8000-000000000004",
    kind: "place",
    origin: "tunedin_custom",
    display_name: "The Fillmore",
    sort_name: "The Fillmore",
    disambiguation: null,
    musicbrainz_mbid: null,
    subtitle: "Indoor arena · San Francisco",
    metadata: {
      placeType: "Indoor arena",
      address: "1805 Geary Blvd",
      latitude: 37.7841,
      longitude: -122.4332,
      ended: false,
      areaCatalogId: "e3000000-0000-4000-8000-000000000003",
      areaMusicBrainzId: null,
      areaName: "San Francisco",
    },
  };
}

function storedArtistRow() {
  return {
    id: "e1000000-0000-4000-8000-000000000001",
    kind: "artist",
    origin: "musicbrainz",
    display_name: "Radiohead",
    sort_name: "Radiohead",
    disambiguation: null,
    musicbrainz_mbid: "a74b1b7f-71a5-4011-9441-d0b5e4122711",
    subtitle: "Group · United Kingdom · GB",
    metadata: {
      artistType: "Group",
      countryCode: "GB",
      areaCatalogId: "e3000000-0000-4000-8000-000000000003",
      areaMusicBrainzId: "8a754a16-0027-3a29-b6d7-2b40ea0481ed",
      areaName: "United Kingdom",
      lifeSpanBegin: "1991",
      lifeSpanEnd: null,
      ended: false,
    },
  };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
