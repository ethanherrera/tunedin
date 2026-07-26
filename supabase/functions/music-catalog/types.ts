export const CATALOG_KINDS = ["artist", "area", "place", "song", "tour"] as const;
export type CatalogKind = (typeof CATALOG_KINDS)[number];

export const CATALOG_ORIGINS = [
  "musicbrainz",
  "tunedin_custom",
] as const;
export type CatalogOrigin = (typeof CATALOG_ORIGINS)[number];

export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };

export interface SearchRequest {
  operation: "search";
  entity: CatalogKind;
  query: string;
  offset: number;
  artistContextIds: string[];
}

export interface ResolveRequest {
  operation: "resolve";
  entity: CatalogKind;
  musicBrainzId: string;
}

export interface SearchEventsRequest {
  operation: "search_events";
  query: string;
}

export type CatalogRequest = SearchRequest | ResolveRequest | SearchEventsRequest;

export interface ArtistCredit {
  artistCatalogId: string | null;
  artistMusicBrainzId: string | null;
  name: string;
  canonicalName: string;
  joinPhrase: string;
}

export interface ArtistSearchContext {
  catalogId: string;
  musicBrainzId: string | null;
  name: string;
}

export interface CatalogResult {
  source: "tunedin" | "musicbrainz";
  origin: CatalogOrigin;
  kind: CatalogKind;
  catalogId: string | null;
  musicBrainzId: string | null;
  displayName: string;
  sortName: string | null;
  disambiguation: string | null;
  subtitle: string | null;
  metadata: JsonObject;
}

export interface SearchResponse {
  operation: "search";
  entity: CatalogKind;
  offset: number;
  limit: 15;
  hasMore: boolean;
  isPartial: boolean;
  results: CatalogResult[];
}

export interface ResolveResponse {
  operation: "resolve";
  entity: CatalogResult;
}

export interface SearchEventsResponse {
  operation: "search_events";
  eventIds: string[];
}

export interface MusicBrainzEventInput {
  event_mbid: string;
  title: string;
  event_date: string;
  local_start_time: string | null;
  venue: {
    mbid: string;
    name: string;
    area_mbid: string | null;
    area_name: string | null;
  };
  artists: Array<{
    mbid: string;
    name: string;
    is_headliner: boolean;
  }>;
  source_status: "active" | "cancelled";
  source_updated_at: string | null;
}

export interface SafeErrorBody {
  error: {
    code: string;
    message: string;
    retryable: boolean;
    retryAfterSeconds: number | null;
  };
}

export interface AuthenticatedProfile {
  id: string;
  authorization: string;
}

export interface CachedSearchPayload {
  schemaVersion: 1;
  kind: CatalogKind;
  hasMore: boolean;
  results: CatalogResult[];
}

export interface CachedLookupPayload {
  schemaVersion: 1;
  kind: CatalogKind;
  entity: CatalogResult;
}

export interface UpsertMusicBrainzInput {
  kind: CatalogKind;
  musicBrainzId: string;
  displayName: string;
  sortName: string | null;
  disambiguation: string | null;
  metadata: JsonObject;
  artistCredits: Array<{
    artist_mbid: string;
    name: string;
    credit_name: string;
    join_phrase: string;
  }>;
}

export interface CatalogBackend {
  authenticate(authorization: string): Promise<AuthenticatedProfile>;
  searchLocal(
    profile: AuthenticatedProfile,
    kind: CatalogKind,
    query: string,
    artistContextIds: string[],
    limit: number,
    offset: number,
  ): Promise<CatalogResult[]>;
  getArtistSearchContext(
    profile: AuthenticatedProfile,
    artistContextIds: string[],
  ): Promise<ArtistSearchContext[]>;
  consumeSearchQuota(profileId: string): Promise<void>;
  getCache(cacheKey: string): Promise<JsonValue>;
  putCache(
    cacheKey: string,
    kind: CatalogKind,
    requestType: "search" | "lookup",
    payload: JsonValue,
    ttlSeconds: number,
  ): Promise<void>;
  claimRequest(cacheKey: string, leaseId: string, leaseSeconds: number): Promise<boolean>;
  releaseRequest(cacheKey: string, leaseId: string): Promise<void>;
  reserveRequestSlot(maxWaitMs: number): Promise<Date>;
  upsertMusicBrainz(input: UpsertMusicBrainzInput): Promise<CatalogResult>;
  upsertMusicBrainzEvent(input: MusicBrainzEventInput): Promise<string>;
}

export interface UpstreamTransport {
  search(
    kind: CatalogKind,
    query: string,
    offset: number,
    artistContext: ArtistSearchContext[],
  ): Promise<{
    results: CatalogResult[];
    hasMore: boolean;
  }>;
  lookup(kind: CatalogKind, musicBrainzId: string): Promise<CatalogResult>;
  searchEvents(query: string): Promise<MusicBrainzEventInput[]>;
}
