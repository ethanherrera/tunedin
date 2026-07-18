import { CatalogError } from "./errors.ts";
import { artistCreditsFromMetadata, decodeCatalogResult } from "./result_validation.ts";
import type {
  ArtistSearchContext,
  AuthenticatedProfile,
  CachedLookupPayload,
  CachedSearchPayload,
  CatalogBackend,
  CatalogKind,
  CatalogResult,
  JsonObject,
  JsonValue,
  ResolveRequest,
  ResolveResponse,
  SearchRequest,
  SearchResponse,
  UpsertMusicBrainzInput,
  UpstreamTransport,
} from "./types.ts";
import { asJsonValue, isPlainObject } from "./validation.ts";

const SEARCH_LIMIT = 15 as const;
const LOCAL_SEARCH_BATCH_SIZE = 50;
const MAX_UPSTREAM_SCAN_PAGES = 24;
const SEARCH_TTL_SECONDS = 24 * 60 * 60;
const LOOKUP_TTL_SECONDS = 30 * 24 * 60 * 60;
// Covers the worst bounded lookup: initial slot + three 8-second HTTP attempts across
// two redirects + redirect slots, while remaining below the database's 60-second cap.
const CLAIM_LEASE_SECONDS = 60;
const MAX_QUEUE_WAIT_MS = 5_000;
const CLAIM_POLL_MS = 125;

const inFlightRequests = new Map<string, Promise<JsonValue>>();

interface ServiceOptions {
  backend: CatalogBackend;
  upstream: UpstreamTransport;
  now?: () => number;
  sleep?: (milliseconds: number) => Promise<void>;
  randomUuid?: () => string;
}

export class MusicCatalogService {
  readonly #backend: CatalogBackend;
  readonly #upstream: UpstreamTransport;
  readonly #now: () => number;
  readonly #sleep: (milliseconds: number) => Promise<void>;
  readonly #randomUuid: () => string;

  constructor(options: ServiceOptions) {
    this.#backend = options.backend;
    this.#upstream = options.upstream;
    this.#now = options.now ?? Date.now;
    this.#sleep = options.sleep ?? ((milliseconds) =>
      new Promise((resolve) => {
        setTimeout(resolve, milliseconds);
      }));
    this.#randomUuid = options.randomUuid ?? (() => crypto.randomUUID());
  }

  async search(request: SearchRequest, authorization: string): Promise<SearchResponse> {
    const profile = await this.#backend.authenticate(authorization);
    await this.#backend.consumeSearchQuota(profile.id);

    // Fetch from zero in bounded batches so the public offset describes one stable
    // sequence: every creator-owned tunedIn match, then MusicBrainz candidates.
    const [artistContext, localSearch] = await Promise.all([
      request.entity === "song" && request.artistContextIds.length > 0
        ? this.#backend.getArtistSearchContext(
          profile,
          request.artistContextIds,
        )
        : Promise.resolve([]),
      this.#loadLocalMatches(profile, request),
    ]);
    const { matches: localMatches, exhausted: localExhausted } = localSearch;
    const localPage = localMatches.slice(request.offset, request.offset + SEARCH_LIMIT);
    const remainingSlots = SEARCH_LIMIT - localPage.length;
    const upstreamOffset = Math.max(0, request.offset - localMatches.length);

    let selectedUpstream: CatalogResult[] = [];
    let upstreamHasMore = false;
    let isPartial = false;
    if (remainingSlots > 0 && localExhausted) {
      try {
        const search = await this.#loadUniqueUpstreamPage(
          request.entity,
          request.query,
          upstreamOffset,
          remainingSlots,
          artistContext,
          new Set(
            localMatches.flatMap((result) =>
              result.musicBrainzId === null ? [] : [result.musicBrainzId]
            ),
          ),
        );
        selectedUpstream = search.results;
        upstreamHasMore = search.hasMore;
      } catch (error) {
        if (localMatches.length === 0 || !isUpstreamAvailabilityError(error)) throw error;
        isPartial = true;
      }
    }

    const results = [...localPage, ...selectedUpstream];
    const localHasMore = request.offset + localPage.length < localMatches.length || !localExhausted;
    const moreResultsExist = isPartial ? localHasMore : localHasMore || upstreamHasMore;

    return {
      operation: "search",
      entity: request.entity,
      offset: request.offset,
      limit: SEARCH_LIMIT,
      hasMore: request.offset + SEARCH_LIMIT <= 150 && moreResultsExist,
      isPartial,
      results,
    };
  }

  async #loadLocalMatches(
    profile: AuthenticatedProfile,
    request: SearchRequest,
  ): Promise<{ matches: CatalogResult[]; exhausted: boolean }> {
    const matches: CatalogResult[] = [];
    const requiredCount = request.offset + SEARCH_LIMIT;
    let exhausted = false;
    while (matches.length < requiredCount) {
      const batch = await this.#backend.searchLocal(
        profile,
        request.entity,
        request.query,
        request.artistContextIds,
        LOCAL_SEARCH_BATCH_SIZE,
        matches.length,
      );
      matches.push(...batch);
      if (batch.length < LOCAL_SEARCH_BATCH_SIZE) {
        exhausted = true;
        break;
      }
    }
    return { matches, exhausted };
  }

  async resolve(request: ResolveRequest, authorization: string): Promise<ResolveResponse> {
    const profile = await this.#backend.authenticate(authorization);
    await this.#backend.consumeSearchQuota(profile.id);
    const candidate = await this.#cachedLookup(request.entity, request.musicBrainzId);
    const input = musicBrainzUpsertInput(candidate);
    const stored = await this.#backend.upsertMusicBrainz(input);
    if (
      stored.origin !== "musicbrainz" || stored.catalogId === null ||
      stored.musicBrainzId !== candidate.musicBrainzId
    ) {
      throw new CatalogError(
        "internal_error",
        500,
        "The catalog request could not be completed.",
        true,
      );
    }
    return {
      operation: "resolve",
      entity: {
        ...stored,
        source: "tunedin",
        subtitle: stored.subtitle ?? candidate.subtitle,
        metadata: stored.metadata,
      },
    };
  }

  async waitForAdditionalUpstreamSlot(): Promise<void> {
    const slot = await this.#backend.reserveRequestSlot(MAX_QUEUE_WAIT_MS);
    await this.#waitForSlot(slot);
  }

  async #cachedSearch(
    kind: CatalogKind,
    query: string,
    offset: number,
    artistContext: ArtistSearchContext[],
  ): Promise<CachedSearchPayload> {
    const cacheKey = await hashedCacheKey({
      schemaVersion: 1,
      operation: "search",
      kind,
      query,
      offset,
      artistContext: artistContext.map(({ musicBrainzId, name }) => ({ musicBrainzId, name })),
    });
    const value = await this.#cachedRequest(
      cacheKey,
      kind,
      "search",
      SEARCH_TTL_SECONDS,
      async () => {
        const upstream = await this.#upstream.search(kind, query, offset, artistContext);
        return {
          schemaVersion: 1,
          kind,
          hasMore: upstream.hasMore,
          results: upstream.results,
        } satisfies CachedSearchPayload;
      },
    );
    return decodeCachedSearch(value, kind);
  }

  async #loadUniqueUpstreamPage(
    kind: CatalogKind,
    query: string,
    logicalOffset: number,
    count: number,
    artistContext: ArtistSearchContext[],
    excludedMusicBrainzIds: Set<string>,
  ): Promise<{ results: CatalogResult[]; hasMore: boolean }> {
    if (excludedMusicBrainzIds.size === 0) {
      const page = await this.#cachedSearch(kind, query, logicalOffset, artistContext);
      return {
        results: page.results.slice(0, count),
        hasMore: page.results.length > count || page.hasMore,
      };
    }

    const uniqueResults: CatalogResult[] = [];
    const seenMusicBrainzIds = new Set(excludedMusicBrainzIds);
    const requiredCount = logicalOffset + count;
    let rawOffset = 0;
    let rawHasMore = true;
    let pages = 0;

    while (uniqueResults.length < requiredCount && rawHasMore) {
      if (pages >= MAX_UPSTREAM_SCAN_PAGES) {
        throw new CatalogError(
          "upstream_invalid_response",
          502,
          "MusicBrainz returned an invalid response.",
          true,
        );
      }
      const page = await this.#cachedSearch(kind, query, rawOffset, artistContext);
      pages += 1;
      for (const result of page.results) {
        const musicBrainzId = result.musicBrainzId;
        if (musicBrainzId === null || seenMusicBrainzIds.has(musicBrainzId)) continue;
        seenMusicBrainzIds.add(musicBrainzId);
        uniqueResults.push(result);
      }
      rawHasMore = page.hasMore;
      if (page.results.length === 0 && rawHasMore) {
        throw new CatalogError(
          "upstream_invalid_response",
          502,
          "MusicBrainz returned an invalid response.",
          true,
        );
      }
      rawOffset += SEARCH_LIMIT;
    }

    return {
      results: uniqueResults.slice(logicalOffset, requiredCount),
      hasMore: uniqueResults.length > requiredCount || rawHasMore,
    };
  }

  async #cachedLookup(kind: CatalogKind, musicBrainzId: string): Promise<CatalogResult> {
    const cacheKey = await hashedCacheKey({
      schemaVersion: 1,
      operation: "lookup",
      kind,
      musicBrainzId,
    });
    const value = await this.#cachedRequest(
      cacheKey,
      kind,
      "lookup",
      LOOKUP_TTL_SECONDS,
      async () => ({
        schemaVersion: 1,
        kind,
        entity: await this.#upstream.lookup(kind, musicBrainzId),
      } satisfies CachedLookupPayload),
    );
    return decodeCachedLookup(value, kind);
  }

  async #cachedRequest(
    cacheKey: string,
    kind: CatalogKind,
    requestType: "search" | "lookup",
    ttlSeconds: number,
    loader: () => Promise<unknown>,
  ): Promise<JsonValue> {
    const cached = await this.#backend.getCache(cacheKey);
    if (cached !== null) return cached;

    const existing = inFlightRequests.get(cacheKey);
    if (existing !== undefined) return await existing;

    const request = this.#claimLoadAndCache(cacheKey, kind, requestType, ttlSeconds, loader);
    inFlightRequests.set(cacheKey, request);
    try {
      return await request;
    } finally {
      if (inFlightRequests.get(cacheKey) === request) inFlightRequests.delete(cacheKey);
    }
  }

  async #claimLoadAndCache(
    cacheKey: string,
    kind: CatalogKind,
    requestType: "search" | "lookup",
    ttlSeconds: number,
    loader: () => Promise<unknown>,
  ): Promise<JsonValue> {
    const leaseId = this.#randomUuid();
    const deadline = this.#now() + MAX_QUEUE_WAIT_MS;
    let claimed = false;

    while (this.#now() <= deadline) {
      const cached = await this.#backend.getCache(cacheKey);
      if (cached !== null) return cached;
      claimed = await this.#backend.claimRequest(cacheKey, leaseId, CLAIM_LEASE_SECONDS);
      if (claimed) break;
      await this.#sleep(Math.min(CLAIM_POLL_MS, Math.max(0, deadline - this.#now())));
    }
    if (!claimed) {
      throw new CatalogError(
        "queue_timeout",
        503,
        "MusicBrainz is busy. Try again shortly.",
        true,
        2,
      );
    }

    try {
      const slot = await this.#backend.reserveRequestSlot(MAX_QUEUE_WAIT_MS);
      await this.#waitForSlot(slot);
      const loaded = asJsonValue(await loader());
      await this.#backend.putCache(cacheKey, kind, requestType, loaded, ttlSeconds);
      return loaded;
    } finally {
      try {
        await this.#backend.releaseRequest(cacheKey, leaseId);
      } catch {
        // The lease is bounded and will expire. Never leak database details or replace
        // an otherwise valid catalog response with a release-only failure.
      }
    }
  }

  async #waitForSlot(slot: Date): Promise<void> {
    const delay = slot.getTime() - this.#now();
    if (delay > MAX_QUEUE_WAIT_MS + 100) {
      throw new CatalogError(
        "queue_timeout",
        503,
        "MusicBrainz is busy. Try again shortly.",
        true,
        2,
      );
    }
    if (delay > 0) await this.#sleep(delay);
  }
}

function isUpstreamAvailabilityError(error: unknown): boolean {
  return error instanceof CatalogError &&
    (error.code.startsWith("upstream_") || error.code === "queue_timeout");
}

export async function hashedCacheKey(value: JsonObject): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify(value)),
  );
  const hash = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return `v1:${hash}`;
}

function decodeCachedSearch(value: JsonValue, expectedKind: CatalogKind): CachedSearchPayload {
  if (!isPlainObject(value)) throw invalidCache();
  exactKeys(value, ["schemaVersion", "kind", "hasMore", "results"]);
  if (
    value.schemaVersion !== 1 || value.kind !== expectedKind ||
    typeof value.hasMore !== "boolean" ||
    !Array.isArray(value.results) || value.results.length > SEARCH_LIMIT
  ) {
    throw invalidCache();
  }
  return {
    schemaVersion: 1,
    kind: expectedKind,
    hasMore: value.hasMore,
    results: value.results.map((result) => {
      try {
        return decodeCatalogResult(result, {
          expectedKind,
          expectedSource: "musicbrainz",
        });
      } catch {
        throw invalidCache();
      }
    }),
  };
}

function decodeCachedLookup(value: JsonValue, expectedKind: CatalogKind): CatalogResult {
  if (!isPlainObject(value)) throw invalidCache();
  exactKeys(value, ["schemaVersion", "kind", "entity"]);
  if (value.schemaVersion !== 1 || value.kind !== expectedKind) throw invalidCache();
  try {
    return decodeCatalogResult(value.entity, {
      expectedKind,
      expectedSource: "musicbrainz",
    });
  } catch {
    throw invalidCache();
  }
}

function musicBrainzUpsertInput(candidate: CatalogResult): UpsertMusicBrainzInput {
  if (candidate.musicBrainzId === null) throw invalidCache();
  const metadata = candidate.metadata;
  const credits = artistCreditsFromMetadata(metadata).map((credit) => {
    if (credit.artistMusicBrainzId === null) throw invalidCache();
    return {
      artist_mbid: credit.artistMusicBrainzId,
      name: credit.canonicalName,
      credit_name: credit.name,
      join_phrase: credit.joinPhrase,
    };
  });
  let databaseMetadata: JsonObject;
  switch (candidate.kind) {
    case "artist":
      databaseMetadata = {
        artist_type: metadata.artistType,
        country_code: metadata.countryCode,
        area_mbid: metadata.areaMusicBrainzId,
        area_name: metadata.areaName,
        life_span_begin: metadata.lifeSpanBegin,
        life_span_end: metadata.lifeSpanEnd,
        ended: metadata.ended,
      };
      break;
    case "area":
      databaseMetadata = {
        area_type: metadata.areaType,
        country_code: metadata.countryCode,
        subdivision_code: metadata.subdivisionCode,
        parent_mbid: metadata.parentMusicBrainzId,
        parent_name: metadata.parentName,
      };
      break;
    case "place":
      databaseMetadata = {
        place_type: metadata.placeType,
        address: metadata.address,
        latitude: metadata.latitude,
        longitude: metadata.longitude,
        ended: metadata.ended,
        area_mbid: metadata.areaMusicBrainzId,
        area_name: metadata.areaName,
      };
      break;
    case "song":
      databaseMetadata = {
        work_mbid: metadata.workMusicBrainzId,
        duration_ms: metadata.durationMs,
        first_release_date: metadata.firstReleaseDate,
        artist_credit: boundedCreditLabel(artistCreditsFromMetadata(metadata)),
      };
      break;
    case "tour":
      databaseMetadata = {
        series_type: metadata.seriesType,
        disambiguation: metadata.disambiguation,
      };
      break;
  }
  return {
    kind: candidate.kind,
    musicBrainzId: candidate.musicBrainzId,
    displayName: candidate.displayName,
    sortName: candidate.sortName,
    disambiguation: candidate.disambiguation,
    metadata: databaseMetadata,
    artistCredits: credits,
  };
}

function boundedCreditLabel(credits: ReturnType<typeof artistCreditsFromMetadata>): string {
  const label = credits.map((credit) => `${credit.name}${credit.joinPhrase}`).join("");
  return Array.from(label).slice(0, 320).join("");
}

function exactKeys(object: Record<string, unknown>, expected: readonly string[]): void {
  const actual = Object.keys(object).sort();
  const wanted = [...expected].sort();
  if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
    throw invalidCache();
  }
}

function invalidCache(): CatalogError {
  return new CatalogError(
    "internal_error",
    500,
    "The catalog request could not be completed.",
    true,
  );
}
