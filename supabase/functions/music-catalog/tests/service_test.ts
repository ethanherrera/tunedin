import assert from "node:assert/strict";
import { CatalogError } from "../errors.ts";
import { hashedCacheKey, MusicCatalogService } from "../service.ts";
import type {
  ArtistSearchContext,
  AuthenticatedProfile,
  CatalogBackend,
  CatalogKind,
  CatalogResult,
  JsonValue,
  MusicBrainzEventInput,
  SearchRequest,
  UpsertMusicBrainzInput,
  UpstreamTransport,
} from "../types.ts";

const profile: AuthenticatedProfile = {
  id: "d1000000-0000-4000-8000-000000000001",
  authorization: "Bearer fixture-token",
};

Deno.test("combined pagination keeps local results first and does not skip MusicBrainz rows", async () => {
  const backend = new FakeBackend();
  backend.localResults = [0, 1, 2].map(customArtist);
  const upstreamResults = Array.from({ length: 30 }, (_, index) => musicBrainzArtist(index));
  const upstream = new FakeUpstream(upstreamResults);
  const service = new MusicCatalogService({ backend, upstream });

  const first = await service.search(searchRequest(0), profile.authorization);
  const second = await service.search(searchRequest(15), profile.authorization);
  const third = await service.search(searchRequest(30), profile.authorization);

  assert.equal(first.results.length, 15);
  assert.equal(second.results.length, 15);
  assert.equal(third.results.length, 3);
  assert.equal(first.hasMore, true);
  assert.equal(second.hasMore, true);
  assert.equal(third.hasMore, false);
  assert.equal(first.isPartial, false);
  assert.deepEqual(
    [...first.results, ...second.results, ...third.results].map((result) => result.displayName),
    [
      "Custom Artist 0",
      "Custom Artist 1",
      "Custom Artist 2",
      ...upstreamResults.map((result) => result.displayName),
    ],
  );
  assert.deepEqual(upstream.searchOffsets, [0, 12, 27]);
  assert.equal(backend.quotaCalls, 3);
});

Deno.test("write-through MusicBrainz rows are deduplicated without paging skips", async () => {
  const backend = new FakeBackend();
  backend.localResults = [storedMusicBrainzArtist(0)];
  const upstreamResults = Array.from({ length: 30 }, (_, index) => musicBrainzArtist(index));
  const upstream = new FakeUpstream(upstreamResults);
  const service = new MusicCatalogService({ backend, upstream });

  const first = await service.search(searchRequest(0), profile.authorization);
  const second = await service.search(searchRequest(15), profile.authorization);

  assert.deepEqual(
    [...first.results, ...second.results].map((result) => result.displayName),
    upstreamResults.map((result) => result.displayName),
  );
  assert.equal(
    new Set([...first.results, ...second.results].map((result) => result.musicBrainzId)).size,
    30,
  );
  assert.equal(first.hasMore, true);
  assert.equal(second.hasMore, false);
  assert.deepEqual(upstream.searchOffsets, [0, 15]);
});

Deno.test("event discovery is rate-gated and writes only validated provider rows", async () => {
  const backend = new FakeBackend();
  const upstream = new FakeUpstream([]);
  upstream.eventResults = [musicBrainzEvent()];
  const service = new MusicCatalogService({ backend, upstream });

  const response = await service.searchEvents({
    operation: "search_events",
    query: "Fixture Artist",
  }, profile.authorization);

  assert.equal(backend.reserveCalls, 1);
  assert.equal(backend.eventUpsertInputs.length, 1);
  assert.equal(response.eventIds.length, 1);
});

Deno.test("local pagination reads beyond 20 rows before filling from MusicBrainz", async () => {
  const backend = new FakeBackend();
  backend.localResults = Array.from({ length: 65 }, (_, index) => customArtist(index));
  const upstream = new FakeUpstream(
    Array.from({ length: 20 }, (_, index) => musicBrainzArtist(index)),
  );
  const service = new MusicCatalogService({ backend, upstream });

  const response = await service.search(searchRequest(60), profile.authorization);

  assert.equal(response.results.length, 15);
  assert.deepEqual(
    response.results.slice(0, 5).map((result) => result.displayName),
    Array.from({ length: 5 }, (_, index) => `Custom Artist ${index + 60}`),
  );
  assert.equal(response.results[5].displayName, "MusicBrainz Artist 0");
  assert.deepEqual(backend.localSearchOffsets, [0, 50]);
  assert.deepEqual(upstream.searchOffsets, [0]);
  assert.equal(response.isPartial, false);
});

Deno.test("the final allowed page never advertises an unreachable next offset", async () => {
  const backend = new FakeBackend();
  const upstream = new FakeUpstream(
    Array.from({ length: 180 }, (_, index) => musicBrainzArtist(index)),
  );
  const service = new MusicCatalogService({ backend, upstream });

  const response = await service.search(searchRequest(150), profile.authorization);

  assert.equal(response.results.length, 15);
  assert.equal(response.hasMore, false);
  assert.deepEqual(upstream.searchOffsets, [150]);
});

Deno.test("upstream outages return known saved results as an explicit partial response", async () => {
  const backend = new FakeBackend();
  backend.localResults = [customArtist(0)];
  const upstream = new FakeUpstream([]);
  upstream.searchError = new CatalogError(
    "upstream_unavailable",
    503,
    "MusicBrainz is temporarily unavailable.",
    true,
  );
  const service = new MusicCatalogService({ backend, upstream });

  const response = await service.search(searchRequest(0), profile.authorization);

  assert.deepEqual(response.results.map((result) => result.displayName), ["Custom Artist 0"]);
  assert.equal(response.isPartial, true);
  assert.equal(response.hasMore, false);
});

Deno.test("upstream outages remain typed errors when no saved result exists", async () => {
  const backend = new FakeBackend();
  const upstream = new FakeUpstream([]);
  upstream.searchError = new CatalogError(
    "upstream_timeout",
    504,
    "MusicBrainz did not respond in time.",
    true,
  );
  const service = new MusicCatalogService({ backend, upstream });

  await assert.rejects(
    () => service.search(searchRequest(0), profile.authorization),
    (error) => error instanceof CatalogError && error.code === "upstream_timeout",
  );
});

Deno.test("song artist context is validated and forwarded to MusicBrainz", async () => {
  const backend = new FakeBackend();
  const artistId = "e1000000-0000-4000-8000-000000000001";
  backend.artistContexts = [{
    catalogId: artistId,
    musicBrainzId: "a74b1b7f-71a5-4011-9441-d0b5e4122711",
    name: "Radiohead",
  }];
  const upstream = new FakeUpstream([musicBrainzSong()]);
  const service = new MusicCatalogService({ backend, upstream });
  const request: SearchRequest = {
    operation: "search",
    entity: "song",
    query: "Creep",
    offset: 0,
    artistContextIds: [artistId],
  };

  await service.search(request, profile.authorization);

  assert.deepEqual(backend.contextRequests, [[artistId]]);
  assert.deepEqual(upstream.artistContexts, [backend.artistContexts]);
});

Deno.test("tour context ranks only saved rows and leaves remote Series search global", async () => {
  const backend = new FakeBackend();
  const artistId = "e1000000-0000-4000-8000-000000000001";
  const upstream = new FakeUpstream([]);
  const service = new MusicCatalogService({ backend, upstream });

  await service.search({
    operation: "search",
    entity: "tour",
    query: "In Rainbows",
    offset: 0,
    artistContextIds: [artistId],
  }, profile.authorization);

  assert.deepEqual(backend.contextRequests, []);
  assert.deepEqual(backend.localArtistContextIds, [[artistId]]);
  assert.deepEqual(upstream.artistContexts, [[]]);
});

Deno.test("cache hits avoid MusicBrainz but still consume the user request quota", async () => {
  const backend = new FakeBackend();
  const upstream = new FakeUpstream([musicBrainzArtist(0)]);
  const service = new MusicCatalogService({ backend, upstream });
  await service.search(searchRequest(0), profile.authorization);
  await service.search(searchRequest(0), profile.authorization);
  assert.equal(upstream.searchCalls, 1);
  assert.equal(backend.reserveCalls, 1);
  assert.equal(backend.quotaCalls, 2);
});

Deno.test("concurrent identical cache misses single-flight into one upstream request", async () => {
  const backend = new FakeBackend();
  const upstream = new FakeUpstream([musicBrainzArtist(0)]);
  upstream.pauseSearch = true;
  const service = new MusicCatalogService({ backend, upstream });
  const first = service.search(searchRequest(0), profile.authorization);
  const second = service.search(searchRequest(0), profile.authorization);
  for (let attempt = 0; attempt < 20 && upstream.searchCalls === 0; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
  assert.equal(upstream.searchCalls, 1);
  upstream.releaseSearch();
  await Promise.all([first, second]);
  assert.equal(upstream.searchCalls, 1);
  assert.equal(backend.reserveCalls, 1);
  assert.equal(backend.claimCalls, 1);
  assert.deepEqual(backend.claimLeaseSeconds, [60]);
});

Deno.test("resolve is quota-bound and sends an artist-only song credit label to ingestion", async () => {
  const backend = new FakeBackend();
  const upstream = new FakeUpstream([]);
  upstream.lookupResult = musicBrainzSong();
  backend.upsertResult = storedSong();
  const service = new MusicCatalogService({ backend, upstream });

  const response = await service.resolve({
    operation: "resolve",
    entity: "song",
    musicBrainzId: "66666666-6666-4666-8666-666666666666",
  }, profile.authorization);

  assert.equal(backend.quotaCalls, 1);
  assert.equal(backend.upsertInputs.length, 1);
  assert.equal(backend.upsertInputs[0].metadata.artist_credit, "Radiohead");
  assert.notEqual(backend.upsertInputs[0].metadata.artist_credit, "Radiohead · 1992-09-21");
  assert.deepEqual(backend.upsertInputs[0].artistCredits, [{
    artist_mbid: "a74b1b7f-71a5-4011-9441-d0b5e4122711",
    name: "Radiohead",
    credit_name: "Radiohead",
    join_phrase: "",
  }]);
  assert.equal(response.entity.catalogId, "e6000000-0000-4000-8000-000000000006");
  assert.equal(response.entity.metadata.artistCredit instanceof Array, true);
});

Deno.test("song ingestion bounds the display credit label but preserves structured credits", async () => {
  const backend = new FakeBackend();
  const upstream = new FakeUpstream([]);
  const longCredits = [1, 2, 3].map((index) => ({
    artistCatalogId: null,
    artistMusicBrainzId: uuid(index + 500),
    name: String.fromCharCode(64 + index).repeat(160),
    canonicalName: String.fromCharCode(64 + index).repeat(160),
    joinPhrase: index < 3 ? ", " : "",
  }));
  upstream.lookupResult = {
    ...musicBrainzSong(),
    musicBrainzId: "77777777-7777-4777-8777-777777777777",
    metadata: { ...songMetadata(null), artistCredit: longCredits },
  };
  backend.upsertResult = {
    ...storedSong(),
    musicBrainzId: "77777777-7777-4777-8777-777777777777",
    metadata: { ...songMetadata(null), artistCredit: longCredits },
  };
  const service = new MusicCatalogService({ backend, upstream });
  await service.resolve({
    operation: "resolve",
    entity: "song",
    musicBrainzId: "77777777-7777-4777-8777-777777777777",
  }, profile.authorization);

  const input = backend.upsertInputs[0];
  assert.equal(Array.from(String(input.metadata.artist_credit)).length, 320);
  assert.equal(input.artistCredits.length, 3);
  assert.equal(input.artistCredits[2].name, "C".repeat(160));
});

Deno.test("cache keys are hashed and never contain a raw query or MBID", async () => {
  const key = await hashedCacheKey({
    schemaVersion: 1,
    operation: "search",
    kind: "artist",
    query: "private fixture query",
    offset: 0,
  });
  assert.match(key, /^v1:[0-9a-f]{64}$/);
  assert.equal(key.includes("private fixture query"), false);
});

class FakeBackend implements CatalogBackend {
  localResults: CatalogResult[] = [];
  upsertResult: CatalogResult = storedArtist();
  readonly upsertInputs: UpsertMusicBrainzInput[] = [];
  readonly eventUpsertInputs: MusicBrainzEventInput[] = [];
  readonly cache = new Map<string, JsonValue>();
  artistContexts: ArtistSearchContext[] = [];
  readonly contextRequests: string[][] = [];
  readonly localSearchOffsets: number[] = [];
  readonly localArtistContextIds: string[][] = [];
  quotaCalls = 0;
  reserveCalls = 0;
  claimCalls = 0;
  readonly claimLeaseSeconds: number[] = [];

  authenticate(authorization: string): Promise<AuthenticatedProfile> {
    assert.equal(authorization, profile.authorization);
    return Promise.resolve(profile);
  }

  searchLocal(
    _profile: AuthenticatedProfile,
    _kind: CatalogKind,
    _query: string,
    artistContextIds: string[],
    limit: number,
    offset: number,
  ): Promise<CatalogResult[]> {
    this.localSearchOffsets.push(offset);
    this.localArtistContextIds.push(artistContextIds);
    return Promise.resolve(this.localResults.slice(offset, offset + limit));
  }

  getArtistSearchContext(
    _profile: AuthenticatedProfile,
    artistContextIds: string[],
  ): Promise<ArtistSearchContext[]> {
    this.contextRequests.push(artistContextIds);
    return Promise.resolve(this.artistContexts);
  }

  consumeSearchQuota(profileId: string): Promise<void> {
    assert.equal(profileId, profile.id);
    this.quotaCalls += 1;
    return Promise.resolve();
  }

  getCache(cacheKey: string): Promise<JsonValue> {
    return Promise.resolve(this.cache.get(cacheKey) ?? null);
  }

  putCache(
    cacheKey: string,
    _kind: CatalogKind,
    _requestType: "search" | "lookup",
    payload: JsonValue,
    _ttlSeconds: number,
  ): Promise<void> {
    this.cache.set(cacheKey, payload);
    return Promise.resolve();
  }

  claimRequest(_cacheKey: string, _leaseId: string, leaseSeconds: number): Promise<boolean> {
    this.claimCalls += 1;
    this.claimLeaseSeconds.push(leaseSeconds);
    return Promise.resolve(true);
  }

  releaseRequest(_cacheKey: string, _leaseId: string): Promise<void> {
    return Promise.resolve();
  }

  reserveRequestSlot(_maxWaitMs: number): Promise<Date> {
    this.reserveCalls += 1;
    return Promise.resolve(new Date());
  }

  upsertMusicBrainz(input: UpsertMusicBrainzInput): Promise<CatalogResult> {
    this.upsertInputs.push(input);
    return Promise.resolve(this.upsertResult);
  }

  upsertMusicBrainzEvent(_input: MusicBrainzEventInput): Promise<string> {
    this.eventUpsertInputs.push(_input);
    return Promise.resolve("e1000000-0000-4000-8000-000000000001");
  }
}

class FakeUpstream implements UpstreamTransport {
  searchCalls = 0;
  readonly searchOffsets: number[] = [];
  lookupResult: CatalogResult = musicBrainzArtist(0);
  pauseSearch = false;
  searchError: Error | null = null;
  readonly artistContexts: ArtistSearchContext[][] = [];
  eventResults: MusicBrainzEventInput[] = [];
  #release: (() => void) | null = null;

  constructor(readonly results: CatalogResult[]) {}

  async search(
    _kind: CatalogKind,
    _query: string,
    offset: number,
    artistContext: ArtistSearchContext[],
  ): Promise<{ results: CatalogResult[]; hasMore: boolean }> {
    this.searchCalls += 1;
    this.searchOffsets.push(offset);
    this.artistContexts.push(artistContext);
    if (this.searchError !== null) throw this.searchError;
    if (this.pauseSearch) {
      await new Promise<void>((resolve) => {
        this.#release = resolve;
      });
    }
    return {
      results: this.results.slice(offset, offset + 15),
      hasMore: offset + 15 < this.results.length,
    };
  }

  lookup(_kind: CatalogKind, _musicBrainzId: string): Promise<CatalogResult> {
    return Promise.resolve(this.lookupResult);
  }

  searchEvents(_query: string): Promise<MusicBrainzEventInput[]> {
    return Promise.resolve(this.eventResults);
  }

  releaseSearch(): void {
    this.#release?.();
  }
}

function searchRequest(offset: number): SearchRequest {
  return {
    operation: "search" as const,
    entity: "artist" as const,
    query: "Fixture Artist",
    offset,
    artistContextIds: [],
  };
}

function customArtist(index: number): CatalogResult {
  return {
    source: "tunedin",
    origin: "tunedin_custom",
    kind: "artist",
    catalogId: uuid(index + 100),
    musicBrainzId: null,
    displayName: `Custom Artist ${index}`,
    sortName: `Custom Artist ${index}`,
    disambiguation: null,
    subtitle: "Your catalog",
    metadata: artistMetadata(),
  };
}

function musicBrainzArtist(index: number): CatalogResult {
  return {
    source: "musicbrainz",
    origin: "musicbrainz",
    kind: "artist",
    catalogId: null,
    musicBrainzId: uuid(index + 1),
    displayName: `MusicBrainz Artist ${index}`,
    sortName: `MusicBrainz Artist ${index}`,
    disambiguation: null,
    subtitle: "Group · GB",
    metadata: artistMetadata(),
  };
}

function storedArtist(): CatalogResult {
  return {
    ...musicBrainzArtist(0),
    source: "tunedin",
    catalogId: "e1000000-0000-4000-8000-000000000001",
  };
}

function musicBrainzEvent(): MusicBrainzEventInput {
  return {
    event_mbid: "e1000000-0000-4000-8000-000000000002",
    title: "Fixture Tour",
    event_date: "2026-08-01",
    local_start_time: "20:00:00",
    venue: {
      mbid: "e1000000-0000-4000-8000-000000000003",
      name: "Fixture Venue",
      area_mbid: null,
      area_name: null,
    },
    artists: [{
      mbid: "e1000000-0000-4000-8000-000000000004",
      name: "Fixture Artist",
      is_headliner: true,
    }],
    source_status: "active",
    source_updated_at: null,
  };
}

function storedMusicBrainzArtist(index: number): CatalogResult {
  return {
    ...musicBrainzArtist(index),
    source: "tunedin",
    catalogId: uuid(index + 900),
  };
}

function musicBrainzSong(): CatalogResult {
  return {
    source: "musicbrainz",
    origin: "musicbrainz",
    kind: "song",
    catalogId: null,
    musicBrainzId: "66666666-6666-4666-8666-666666666666",
    displayName: "Creep",
    sortName: null,
    disambiguation: null,
    subtitle: "Radiohead · 1992-09-21",
    metadata: songMetadata(null),
  };
}

function storedSong(): CatalogResult {
  return {
    ...musicBrainzSong(),
    source: "tunedin",
    catalogId: "e6000000-0000-4000-8000-000000000006",
    metadata: songMetadata("e1000000-0000-4000-8000-000000000001"),
  };
}

function artistMetadata() {
  return {
    artistType: "Group",
    countryCode: "GB",
    areaCatalogId: null,
    areaMusicBrainzId: "8a754a16-0027-3a29-b6d7-2b40ea0481ed",
    areaName: "United Kingdom",
    lifeSpanBegin: "1991",
    lifeSpanEnd: null,
    ended: false,
  };
}

function songMetadata(artistCatalogId: string | null) {
  return {
    workMusicBrainzId: "99999999-9999-4999-8999-999999999999",
    durationMs: 238000,
    firstReleaseDate: "1992-09-21",
    artistCredit: [{
      artistCatalogId,
      artistMusicBrainzId: "a74b1b7f-71a5-4011-9441-d0b5e4122711",
      name: "Radiohead",
      canonicalName: "Radiohead",
      joinPhrase: "",
    }],
  };
}

function uuid(index: number): string {
  return `${index.toString(16).padStart(8, "0")}-0000-4000-8000-000000000000`;
}
