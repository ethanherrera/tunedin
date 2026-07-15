import { CatalogError } from "./errors.ts";
import type {
  ArtistSearchContext,
  AuthenticatedProfile,
  CatalogBackend,
  CatalogKind,
  CatalogResult,
  JsonObject,
  JsonValue,
  UpsertMusicBrainzInput,
} from "./types.ts";
import { decodeCatalogResult } from "./result_validation.ts";
import { isPlainObject, parseUuid } from "./validation.ts";

const MAX_DATABASE_RESPONSE_BYTES = 2_000_000;
const MAX_DATABASE_ERROR_BYTES = 16_384;
const SEARCH_QUOTA_ERROR = "Catalog search limit reached. Try again later.";
const MUSICBRAINZ_QUEUE_ERROR = "MusicBrainz is busy. Try again shortly.";

interface BackendOptions {
  supabaseUrl: URL;
  anonymousKey: string;
  serviceRoleKey: string;
  fetch?: typeof fetch;
}

class DatabaseError extends Error {
  constructor(
    readonly status: number,
    readonly code: string | null,
    readonly databaseMessage: string | null,
  ) {
    super("Database request failed");
  }
}

export class SupabaseCatalogBackend implements CatalogBackend {
  readonly #supabaseUrl: URL;
  readonly #anonymousKey: string;
  readonly #serviceRoleKey: string;
  readonly #fetch: typeof fetch;

  constructor(options: BackendOptions) {
    this.#supabaseUrl = options.supabaseUrl;
    this.#anonymousKey = options.anonymousKey;
    this.#serviceRoleKey = options.serviceRoleKey;
    this.#fetch = options.fetch ?? fetch;
  }

  async authenticate(authorization: string): Promise<AuthenticatedProfile> {
    if (
      authorization.length > 8_192 ||
      !/^Bearer [A-Za-z0-9._~-]+$/.test(authorization)
    ) {
      throw authenticationRequired();
    }

    const userUrl = new URL("auth/v1/user", this.#supabaseUrl);
    let userResponse: Response;
    try {
      userResponse = await this.#fetch(userUrl, {
        method: "GET",
        headers: { Authorization: authorization, apikey: this.#anonymousKey },
      });
    } catch {
      throw databaseFailure();
    }
    if (!userResponse.ok) {
      if (userResponse.status === 401 || userResponse.status === 403) {
        throw authenticationRequired();
      }
      throw databaseFailure();
    }
    const user = await readDatabaseJson(userResponse);
    if (!isPlainObject(user)) throw authenticationRequired();
    let profileId: string;
    try {
      profileId = parseUuid(user.id, "User ID");
    } catch {
      throw authenticationRequired();
    }

    const profileUrl = new URL("rest/v1/profiles", this.#supabaseUrl);
    profileUrl.searchParams.set("select", "id,onboarding_completed_at");
    profileUrl.searchParams.set("id", `eq.${profileId}`);
    profileUrl.searchParams.set("limit", "1");
    let profileResponse: Response;
    try {
      profileResponse = await this.#fetch(profileUrl, {
        method: "GET",
        headers: {
          Authorization: authorization,
          apikey: this.#anonymousKey,
          Accept: "application/json",
        },
      });
    } catch {
      throw databaseFailure();
    }
    if (!profileResponse.ok) {
      if (profileResponse.status === 401 || profileResponse.status === 403) {
        throw authenticationRequired();
      }
      throw new CatalogError(
        "internal_error",
        500,
        "The catalog request could not be completed.",
        true,
      );
    }
    const profiles = await readDatabaseJson(profileResponse);
    if (
      !Array.isArray(profiles) || profiles.length !== 1 ||
      !isPlainObject(profiles[0]) ||
      typeof profiles[0].onboarding_completed_at !== "string"
    ) {
      throw new CatalogError(
        "profile_required",
        403,
        "Complete your tunedIn profile before using the catalog.",
      );
    }
    return { id: profileId, authorization };
  }

  async searchLocal(
    profile: AuthenticatedProfile,
    kind: CatalogKind,
    query: string,
    artistContextIds: string[],
    concertContextId: string | null,
    limit: number,
    offset: number,
  ): Promise<CatalogResult[]> {
    const payload = await this.#rpc(
      "search_catalog",
      {
        p_kind: kind,
        p_query: query,
        p_artist_ids: artistContextIds.length === 0 ? null : artistContextIds,
        p_limit: limit,
        p_offset: offset,
        p_concert_id: concertContextId,
      },
      profile.authorization,
      this.#anonymousKey,
    );
    if (!Array.isArray(payload) || payload.length > limit) {
      throw databaseFailure();
    }
    return payload.map((row) => decodeLocalResult(row, kind));
  }

  async getArtistSearchContext(
    profile: AuthenticatedProfile,
    artistContextIds: string[],
    concertContextId: string | null,
  ): Promise<ArtistSearchContext[]> {
    if (artistContextIds.length === 0) return [];
    const payload = await this.#serviceRpc(
      "get_catalog_artist_search_context",
      {
        p_profile_id: profile.id,
        p_artist_ids: artistContextIds,
        p_concert_id: concertContextId,
      },
    );
    if (!Array.isArray(payload) || payload.length !== artistContextIds.length) {
      throw databaseFailure();
    }
    return payload.map((value, index): ArtistSearchContext => {
      if (!isPlainObject(value)) throw databaseFailure();
      const catalogId = requiredDatabaseUuid(value.catalog_id);
      if (catalogId !== artistContextIds[index]) throw databaseFailure();
      return {
        catalogId,
        musicBrainzId: nullableDatabaseUuid(value.musicbrainz_mbid),
        name: requiredDatabaseString(value.display_name, 160),
      };
    });
  }

  async consumeSearchQuota(profileId: string): Promise<void> {
    try {
      await this.#serviceRpc("consume_catalog_search_quota", {
        p_profile_id: profileId,
      });
    } catch (error) {
      if (
        error instanceof DatabaseError && error.code === "P0001" &&
        error.databaseMessage === SEARCH_QUOTA_ERROR
      ) {
        throw new CatalogError(
          "search_quota_exceeded",
          429,
          "Too many catalog searches. Try again later.",
          true,
          60,
        );
      }
      throw databaseFailure();
    }
  }

  async getCache(cacheKey: string): Promise<JsonValue> {
    const payload = await this.#serviceRpc("get_musicbrainz_cache", {
      p_cache_key: cacheKey,
    });
    return toJsonValue(payload);
  }

  async putCache(
    cacheKey: string,
    kind: CatalogKind,
    requestType: "search" | "lookup",
    payload: JsonValue,
    ttlSeconds: number,
  ): Promise<void> {
    await this.#serviceRpc("put_musicbrainz_cache", {
      p_cache_key: cacheKey,
      p_kind: kind,
      p_request_type: requestType,
      p_payload: payload,
      p_ttl_seconds: ttlSeconds,
    });
  }

  async claimRequest(
    cacheKey: string,
    leaseId: string,
    leaseSeconds: number,
  ): Promise<boolean> {
    const payload = await this.#serviceRpc("claim_musicbrainz_request", {
      p_cache_key: cacheKey,
      p_lease_id: leaseId,
      p_lease_seconds: leaseSeconds,
    });
    if (typeof payload !== "boolean") throw databaseFailure();
    return payload;
  }

  async releaseRequest(cacheKey: string, leaseId: string): Promise<void> {
    await this.#serviceRpc("release_musicbrainz_request", {
      p_cache_key: cacheKey,
      p_lease_id: leaseId,
    });
  }

  async reserveRequestSlot(maxWaitMs: number): Promise<Date> {
    let payload: unknown;
    try {
      payload = await this.#serviceRpc("reserve_musicbrainz_request_slot", {
        p_max_wait_ms: maxWaitMs,
      });
    } catch (error) {
      if (
        error instanceof DatabaseError && error.code === "P0001" &&
        error.databaseMessage === MUSICBRAINZ_QUEUE_ERROR
      ) {
        throw new CatalogError(
          "queue_timeout",
          503,
          MUSICBRAINZ_QUEUE_ERROR,
          true,
          2,
        );
      }
      throw databaseFailure();
    }
    if (typeof payload !== "string") throw databaseFailure();
    const date = new Date(payload);
    if (!Number.isFinite(date.getTime())) throw databaseFailure();
    return date;
  }

  async upsertMusicBrainz(
    input: UpsertMusicBrainzInput,
  ): Promise<CatalogResult> {
    const payload = await this.#serviceRpc(
      "upsert_musicbrainz_catalog_entity",
      {
        p_kind: input.kind,
        p_mbid: input.musicBrainzId,
        p_display_name: input.displayName,
        p_sort_name: input.sortName,
        p_disambiguation: input.disambiguation,
        p_metadata: input.metadata,
        p_artist_credits: input.artistCredits,
      },
    );
    const row = Array.isArray(payload) && payload.length === 1 ? payload[0] : payload;
    return decodeStoredResult(row, input.kind);
  }

  async #serviceRpc(name: string, body: JsonObject): Promise<unknown> {
    try {
      return await this.#rpc(
        name,
        body,
        `Bearer ${this.#serviceRoleKey}`,
        this.#serviceRoleKey,
      );
    } catch (error) {
      if (error instanceof DatabaseError) throw error;
      throw databaseFailure();
    }
  }

  async #rpc(
    name: string,
    body: JsonObject,
    authorization: string,
    apiKey: string,
  ): Promise<unknown> {
    const url = new URL(`rest/v1/rpc/${name}`, this.#supabaseUrl);
    let response: Response;
    try {
      response = await this.#fetch(url, {
        method: "POST",
        headers: {
          Authorization: authorization,
          apikey: apiKey,
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
    } catch {
      throw databaseFailure();
    }
    if (!response.ok) {
      const error = await readDatabaseError(response);
      throw new DatabaseError(response.status, error.code, error.message);
    }
    if (
      response.status === 204 || response.headers.get("content-length") === "0"
    ) return null;
    return await readDatabaseJson(response);
  }
}

async function readDatabaseError(
  response: Response,
): Promise<{ code: string | null; message: string | null }> {
  let text: string;
  try {
    text = await readBoundedText(response, MAX_DATABASE_ERROR_BYTES);
  } catch {
    return { code: null, message: null };
  }
  try {
    const value: unknown = JSON.parse(text);
    if (!isPlainObject(value)) return { code: null, message: null };
    return {
      code: safeDatabaseErrorString(value.code, 20),
      message: safeDatabaseErrorString(value.message, 240),
    };
  } catch {
    return { code: null, message: null };
  }
}

async function readBoundedText(
  response: Response,
  maximumBytes: number,
): Promise<string> {
  const declaredLength = response.headers.get("content-length");
  if (declaredLength !== null && Number(declaredLength) > maximumBytes) {
    throw databaseFailure();
  }
  const reader = response.body?.getReader();
  if (reader === undefined) return "";
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maximumBytes) {
      await reader.cancel();
      throw databaseFailure();
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

function safeDatabaseErrorString(
  value: unknown,
  maximum: number,
): string | null {
  if (
    typeof value !== "string" || value.length === 0 ||
    Array.from(value).length > maximum ||
    /[\p{Cc}\p{Cf}]/u.test(value)
  ) {
    return null;
  }
  return value;
}

function decodeLocalResult(
  value: unknown,
  requestedKind: CatalogKind,
): CatalogResult {
  if (!isPlainObject(value)) throw databaseFailure();
  try {
    return decodeCatalogResult({
      source: "tunedin",
      origin: value.origin,
      kind: value.kind,
      catalogId: value.id,
      musicBrainzId: value.musicbrainz_mbid,
      displayName: value.display_name,
      sortName: value.sort_name,
      disambiguation: value.disambiguation,
      subtitle: value.subtitle,
      metadata: value.metadata,
    }, { expectedKind: requestedKind, expectedSource: "tunedin" });
  } catch {
    throw databaseFailure();
  }
}

function decodeStoredResult(
  value: unknown,
  requestedKind: CatalogKind,
): CatalogResult {
  if (!isPlainObject(value)) throw databaseFailure();
  try {
    return decodeCatalogResult({
      source: "tunedin",
      origin: value.origin,
      kind: value.kind,
      catalogId: value.id,
      musicBrainzId: value.musicbrainz_mbid,
      displayName: value.display_name,
      sortName: value.sort_name,
      disambiguation: value.disambiguation,
      subtitle: value.subtitle,
      metadata: value.metadata,
    }, { expectedKind: requestedKind, expectedSource: "tunedin" });
  } catch {
    throw databaseFailure();
  }
}

async function readDatabaseJson(response: Response): Promise<unknown> {
  const text = await response.text();
  if (new TextEncoder().encode(text).byteLength > MAX_DATABASE_RESPONSE_BYTES) {
    throw databaseFailure();
  }
  try {
    return text === "" ? null : JSON.parse(text);
  } catch {
    throw databaseFailure();
  }
}

function toJsonValue(value: unknown): JsonValue {
  if (
    value === null || typeof value === "string" || typeof value === "boolean"
  ) return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (Array.isArray(value)) return value.map(toJsonValue);
  if (isPlainObject(value)) {
    const result: JsonObject = {};
    for (const [key, child] of Object.entries(value)) {
      result[key] = toJsonValue(child);
    }
    return result;
  }
  throw databaseFailure();
}

function requiredDatabaseUuid(value: unknown): string {
  try {
    return parseUuid(value);
  } catch {
    throw databaseFailure();
  }
}

function nullableDatabaseUuid(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  return requiredDatabaseUuid(value);
}

function requiredDatabaseString(value: unknown, maximum: number): string {
  if (
    typeof value !== "string" || value.length === 0 ||
    Array.from(value).length > maximum ||
    /[\p{Cc}\p{Cf}]/u.test(value)
  ) {
    throw databaseFailure();
  }
  return value;
}

function authenticationRequired(): CatalogError {
  return new CatalogError(
    "authentication_required",
    401,
    "Sign in to use the tunedIn catalog.",
  );
}

function databaseFailure(): CatalogError {
  return new CatalogError(
    "internal_error",
    500,
    "The catalog request could not be completed.",
    true,
  );
}
