import { DiscoveryError } from "./errors.ts";
import type { AuthenticatedProfile, DiscoveryCandidate, JsonValue } from "./types.ts";
import { isObject } from "./validation.ts";

const MAX_DATABASE_RESPONSE_BYTES = 2_000_000;

export class DiscoveryBackend {
  readonly #supabaseURL: URL;
  readonly #anonymousKey: string;
  readonly #serviceRoleKey: string;
  readonly #fetch: typeof fetch;

  constructor(options: {
    supabaseURL: URL;
    anonymousKey: string;
    serviceRoleKey: string;
    fetch?: typeof fetch;
  }) {
    this.#supabaseURL = options.supabaseURL;
    this.#anonymousKey = options.anonymousKey;
    this.#serviceRoleKey = options.serviceRoleKey;
    this.#fetch = options.fetch ?? fetch;
  }

  async authenticate(authorization: string): Promise<AuthenticatedProfile> {
    if (authorization.length > 8192 || !/^Bearer [A-Za-z0-9._~-]+$/.test(authorization)) {
      throw authenticationRequired();
    }
    const userURL = new URL("auth/v1/user", this.#supabaseURL);
    const response = await this.#safeFetch(userURL, {
      headers: { Authorization: authorization, apikey: this.#anonymousKey },
    });
    if (!response.ok) throw authenticationRequired();
    const user = await readJson(response);
    if (!isObject(user) || typeof user.id !== "string" || !isUuid(user.id)) {
      throw authenticationRequired();
    }
    const profileURL = new URL("rest/v1/profiles", this.#supabaseURL);
    profileURL.searchParams.set("select", "id,onboarding_completed_at");
    profileURL.searchParams.set("id", `eq.${user.id}`);
    profileURL.searchParams.set("limit", "1");
    const profileResponse = await this.#safeFetch(profileURL, {
      headers: {
        Authorization: authorization,
        apikey: this.#anonymousKey,
        Accept: "application/json",
      },
    });
    const profiles = await readJson(profileResponse);
    if (
      !profileResponse.ok ||
      !Array.isArray(profiles) ||
      profiles.length !== 1 ||
      !isObject(profiles[0]) ||
      typeof profiles[0].onboarding_completed_at !== "string"
    ) {
      throw new DiscoveryError(
        "profile_required",
        403,
        "Complete your tunedIn profile before discovering events.",
      );
    }
    return { id: user.id };
  }

  async consumeQuota(profileId: string): Promise<void> {
    await this.#rpc("consume_ticketmaster_discovery_quota", { p_profile_id: profileId });
  }

  async cached(cacheKey: string): Promise<JsonValue | null> {
    return await this.#rpc("get_ticketmaster_cache", { p_cache_key: cacheKey });
  }

  async cache(
    cacheKey: string,
    requestType: "discover" | "detail",
    payload: JsonValue,
    ttlSeconds: number,
  ): Promise<void> {
    await this.#rpc("put_ticketmaster_cache", {
      p_cache_key: cacheKey,
      p_request_type: requestType,
      p_payload: payload,
      p_ttl_seconds: ttlSeconds,
    });
  }

  async reserveUpstreamSlot(): Promise<void> {
    const reservedAt = await this.#rpc("reserve_ticketmaster_request_slot", {});
    if (typeof reservedAt !== "string") throw databaseFailure();
    const wait = Date.parse(reservedAt) - Date.now();
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, Math.min(wait, 5_000)));
  }

  async upsertEvent(event: DiscoveryCandidate): Promise<string> {
    const payload = {
      event_id: event.id,
      title: event.name,
      event_date: event.localDate,
      local_start_time: event.localTime,
      starts_at: event.dateTime,
      time_zone: event.timeZone ?? "UTC",
      status: event.status,
      source_url: event.ticketURL,
      image_url: event.imageURL,
      source_updated_at: null,
      venue: {
        id: event.venue.id,
        name: event.venue.name,
        url: event.venue.url,
        address: event.venue.address,
        latitude: event.venue.latitude,
        longitude: event.venue.longitude,
        area: {
          city: event.venue.city,
          state_code: event.venue.stateCode,
          country_code: event.venue.countryCode,
        },
      },
      artists: event.artists.map((artist, index) => ({
        id: artist.id,
        name: artist.name,
        url: artist.url,
        is_headliner: index === 0,
      })),
    };
    const eventId = await this.#rpc("upsert_ticketmaster_catalog_event", { p_event: payload });
    if (typeof eventId !== "string" || !isUuid(eventId)) throw databaseFailure();
    return eventId;
  }

  async #rpc(name: string, body: Record<string, unknown>): Promise<JsonValue> {
    const url = new URL(`rest/v1/rpc/${name}`, this.#supabaseURL);
    const response = await this.#safeFetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.#serviceRoleKey}`,
        apikey: this.#serviceRoleKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
    if (!response.ok) {
      throw databaseFailure();
    }
    if (response.status === 204) return null;
    return await readJson(response);
  }

  async #safeFetch(url: URL, init: RequestInit): Promise<Response> {
    try {
      return await this.#fetch(url, init);
    } catch {
      throw databaseFailure();
    }
  }
}

async function readJson(response: Response): Promise<JsonValue> {
  const text = await response.text();
  if (new TextEncoder().encode(text).byteLength > MAX_DATABASE_RESPONSE_BYTES) {
    throw databaseFailure();
  }
  try {
    return JSON.parse(text) as JsonValue;
  } catch {
    throw databaseFailure();
  }
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function authenticationRequired(): DiscoveryError {
  return new DiscoveryError("authentication_required", 401, "Sign in to discover concerts.");
}

function databaseFailure(): DiscoveryError {
  return new DiscoveryError(
    "internal_error",
    500,
    "Event discovery could not be completed.",
    true,
  );
}
