import { DiscoveryBackend } from "./backend.ts";
import { DiscoveryError } from "./errors.ts";
import { TicketmasterClient } from "./ticketmaster.ts";
import type {
  DiscoverRequest,
  DiscoverResponse,
  DiscoveryCandidate,
  JsonValue,
  ResolveRequest,
  ResolveResponse,
} from "./types.ts";
import { isObject } from "./validation.ts";

const DISCOVER_TTL_SECONDS = 10 * 60;
const DETAIL_TTL_SECONDS = 30 * 60;

export class EventDiscoveryService {
  constructor(
    private readonly backend: DiscoveryBackend,
    private readonly ticketmaster: TicketmasterClient,
  ) {}

  async discover(request: DiscoverRequest, authorization: string): Promise<DiscoverResponse> {
    const profile = await this.backend.authenticate(authorization);
    await this.backend.consumeQuota(profile.id);
    const cacheKey = await requestCacheKey("discover", request);
    const cached = await this.backend.cached(cacheKey);
    if (cached !== null) return decodeDiscoverResponse(cached);
    await this.backend.reserveUpstreamSlot();
    const result = await this.ticketmaster.discover(request);
    const response: DiscoverResponse = {
      operation: "discover",
      location: request.location,
      page: request.page,
      hasMore: result.hasMore,
      events: result.events,
    };
    await this.backend.cache(
      cacheKey,
      "discover",
      response as unknown as JsonValue,
      DISCOVER_TTL_SECONDS,
    );
    return response;
  }

  async resolve(request: ResolveRequest, authorization: string): Promise<ResolveResponse> {
    const profile = await this.backend.authenticate(authorization);
    await this.backend.consumeQuota(profile.id);
    const cacheKey = await requestCacheKey("detail", { eventId: request.eventId });
    const cached = await this.backend.cached(cacheKey);
    let event: DiscoveryCandidate;
    if (cached === null) {
      await this.backend.reserveUpstreamSlot();
      event = await this.ticketmaster.event(request.eventId);
      await this.backend.cache(
        cacheKey,
        "detail",
        event as unknown as JsonValue,
        DETAIL_TTL_SECONDS,
      );
    } else {
      event = decodeCandidate(cached);
    }
    if (event.id !== request.eventId) {
      throw new DiscoveryError(
        "invalid_upstream_response",
        502,
        "Ticketmaster returned an unsupported event.",
        true,
      );
    }
    return {
      operation: "resolve",
      eventId: event.id,
      catalogEventId: await this.backend.upsertEvent(event),
    };
  }
}

async function requestCacheKey(kind: string, value: unknown): Promise<string> {
  const bytes = new TextEncoder().encode(JSON.stringify({ kind, value }));
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return `v1:${Array.from(digest).map((byte) => byte.toString(16).padStart(2, "0")).join("")}`;
}

function decodeDiscoverResponse(value: JsonValue): DiscoverResponse {
  if (!isObject(value) || value.operation !== "discover" || !Array.isArray(value.events)) {
    throw invalidCache();
  }
  const location = value.location;
  if (
    !isObject(location) ||
    typeof location.city !== "string" ||
    typeof location.countryCode !== "string" ||
    !(location.stateCode === null || typeof location.stateCode === "string") ||
    !Number.isInteger(value.page) ||
    typeof value.hasMore !== "boolean"
  ) {
    throw invalidCache();
  }
  return {
    operation: "discover",
    location: {
      city: location.city,
      stateCode: location.stateCode as string | null,
      countryCode: location.countryCode,
    },
    page: value.page as number,
    hasMore: value.hasMore,
    events: value.events.map(decodeCandidate),
  };
}

function decodeCandidate(value: unknown): DiscoveryCandidate {
  if (!isObject(value)) throw invalidCache();
  const venue = value.venue;
  if (!isObject(venue) || !Array.isArray(value.artists)) throw invalidCache();
  return value as unknown as DiscoveryCandidate;
}

function invalidCache(): DiscoveryError {
  return new DiscoveryError("internal_error", 500, "Event discovery could not be completed.", true);
}
