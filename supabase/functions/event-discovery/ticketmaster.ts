import { DiscoveryError } from "./errors.ts";
import type {
  DiscoverRequest,
  DiscoveryArtist,
  DiscoveryCandidate,
  DiscoveryVenue,
  JsonValue,
} from "./types.ts";
import { isObject } from "./validation.ts";

const PAGE_SIZE = 20;
const MAX_RESPONSE_BYTES = 2_000_000;

export type TicketmasterRejectionReason =
  | "event_shape"
  | "event_dates"
  | "venue"
  | "lineup"
  | "source_url";

export type TicketmasterRejectionCode =
  | "event_shape_invalid"
  | "event_dates_invalid"
  | "venue_invalid"
  | "attractions_missing"
  | "attractions_not_array"
  | "attractions_too_many"
  | "attractions_empty"
  | "attractions_all_invalid"
  | "source_url_invalid";

export interface TicketmasterAttractionRejectionCounts {
  attractionShape: number;
  artistId: number;
  artistName: number;
  artistURL: number;
}

export interface TicketmasterRejectedEvent {
  rawPosition: number;
  externalEventId: string | null;
  eventName: string | null;
  localDate: string | null;
  venueName: string | null;
  reason: TicketmasterRejectionReason;
  code: TicketmasterRejectionCode;
  attractionCount: number | null;
  invalidAttractions: TicketmasterAttractionRejectionCounts;
}

export interface TicketmasterDiscoveryPage {
  events: DiscoveryCandidate[];
  rejections: TicketmasterRejectedEvent[];
  pageNumber: number;
  pageSize: number;
  totalElements: number;
  totalPages: number;
  rawEventCount: number;
  rejectedEventCount: number;
  rejectionReasons: Record<TicketmasterRejectionReason, number>;
  hasMore: boolean;
}

export class TicketmasterClient {
  readonly #baseURL: URL;
  readonly #apiKey: string;
  readonly #fetch: typeof fetch;

  constructor(options: { baseURL: URL; apiKey: string; fetch?: typeof fetch }) {
    this.#baseURL = options.baseURL;
    this.#apiKey = options.apiKey;
    this.#fetch = options.fetch ?? fetch;
  }

  async discover(
    request: DiscoverRequest,
  ): Promise<TicketmasterDiscoveryPage> {
    const url = new URL("events.json", this.#baseURL);
    url.searchParams.set("apikey", this.#apiKey);
    url.searchParams.set("source", "ticketmaster");
    url.searchParams.set("segmentName", "Music");
    url.searchParams.set("city", request.location.city);
    url.searchParams.set("countryCode", request.location.countryCode);
    if (request.location.stateCode !== null) {
      url.searchParams.set("stateCode", request.location.stateCode);
    }
    url.searchParams.set("startDateTime", request.startDateTime);
    url.searchParams.set("endDateTime", request.endDateTime);
    if (request.genre !== null) url.searchParams.set("classificationName", request.genre);
    url.searchParams.set("includeTBA", "no");
    url.searchParams.set("includeTBD", "no");
    url.searchParams.set("size", String(PAGE_SIZE));
    url.searchParams.set("page", String(request.page));
    url.searchParams.set("sort", "date,asc");
    const payload = await this.#request(url);
    const root = object(payload);
    const embedded = optionalObject(root._embedded);
    const rawEvents = embedded === null ? [] : array(embedded.events, PAGE_SIZE);
    const page = optionalObject(root.page);
    const pageNumber = page === null ? request.page : integer(page.number);
    const pageSize = page === null ? PAGE_SIZE : integer(page.size);
    const totalElements = page === null ? rawEvents.length : integer(page.totalElements);
    const totalPages = page === null
      ? request.page + (rawEvents.length === PAGE_SIZE ? 2 : 1)
      : integer(page.totalPages);
    if (
      pageNumber !== request.page ||
      pageSize !== PAGE_SIZE ||
      totalPages > 50 ||
      totalElements > 1_000
    ) {
      throw upstreamInvalid();
    }
    const rejectionReasons = emptyRejectionReasons();
    const rejections: TicketmasterRejectedEvent[] = [];
    const events = rawEvents.flatMap((event, rawPosition) => {
      try {
        return [decodeEvent(event)];
      } catch (error) {
        const reason = error instanceof TicketmasterDecodeError ? error.reason : "event_shape";
        rejectionReasons[reason] += 1;
        rejections.push(rejectedEvent(event, rawPosition, error));
        return [];
      }
    });
    return {
      events,
      rejections,
      pageNumber,
      pageSize,
      totalElements,
      totalPages,
      rawEventCount: rawEvents.length,
      rejectedEventCount: rawEvents.length - events.length,
      rejectionReasons,
      hasMore: request.page + 1 < totalPages,
    };
  }

  async event(eventId: string): Promise<DiscoveryCandidate> {
    const url = new URL(`events/${encodeURIComponent(eventId)}.json`, this.#baseURL);
    url.searchParams.set("apikey", this.#apiKey);
    return decodeEvent(await this.#request(url));
  }

  async #request(url: URL): Promise<JsonValue> {
    if (url.origin !== this.#baseURL.origin || !url.pathname.startsWith(this.#baseURL.pathname)) {
      throw upstreamInvalid();
    }
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 8_000);
    let response: Response;
    try {
      response = await this.#fetch(url, {
        headers: { Accept: "application/json" },
        redirect: "error",
        signal: controller.signal,
      });
    } catch {
      throw new DiscoveryError(
        "upstream_unavailable",
        503,
        "Ticketmaster is temporarily unavailable.",
        true,
      );
    } finally {
      clearTimeout(timeout);
    }
    if (response.status === 404) {
      throw new DiscoveryError(
        "event_not_found",
        404,
        "That Ticketmaster event is no longer available.",
      );
    }
    if (response.status === 429) {
      throw new DiscoveryError(
        "upstream_rate_limited",
        503,
        "Ticketmaster is busy. Try again shortly.",
        true,
        30,
      );
    }
    if (!response.ok) {
      throw new DiscoveryError(
        "upstream_unavailable",
        503,
        "Ticketmaster is temporarily unavailable.",
        true,
      );
    }
    const declared = Number(response.headers.get("content-length") ?? "0");
    if (declared > MAX_RESPONSE_BYTES) throw upstreamInvalid();
    const text = await response.text();
    if (new TextEncoder().encode(text).byteLength > MAX_RESPONSE_BYTES) throw upstreamInvalid();
    try {
      return JSON.parse(text) as JsonValue;
    } catch {
      throw upstreamInvalid();
    }
  }
}

export function decodeEvent(value: unknown): DiscoveryCandidate {
  const event = decodeStage("event_shape", "event_shape_invalid", () => object(value));
  const identity = decodeStage("event_shape", "event_shape_invalid", () => ({
    id: string(event.id, 200),
    name: string(event.name, 160),
  }));
  const temporal = decodeStage("event_dates", "event_dates_invalid", () => {
    const dates = object(event.dates);
    const start = object(dates.start);
    const status = optionalObject(dates.status);
    return {
      localDate: dateString(start.localDate),
      localTime: optionalTime(start.localTime),
      dateTime: optionalDateTime(start.dateTime),
      timeZone: optionalString(dates.timezone, 100),
      status: mapStatus(status === null ? null : optionalString(status.code, 40)),
    };
  });
  const embedded = decodeStage("venue", "venue_invalid", () => object(event._embedded));
  const venue = decodeStage("venue", "venue_invalid", () => {
    const venues = array(embedded.venues, 5);
    return decodeVenue(venues[0]);
  });
  const attractions = decodeAttractions(embedded.attractions);
  const classifications = Array.isArray(event.classifications) ? event.classifications : [];
  const classification = classifications.length > 0 ? optionalObject(classifications[0]) : null;
  const genre = classification === null ? null : optionalObject(classification.genre);
  const imageURL = preferredImage(Array.isArray(event.images) ? event.images : []);
  const ticketURL = decodeStage("source_url", "source_url_invalid", () => httpsURL(event.url));
  return {
    id: identity.id,
    name: identity.name,
    localDate: temporal.localDate,
    localTime: temporal.localTime,
    dateTime: temporal.dateTime,
    timeZone: temporal.timeZone,
    status: temporal.status,
    venue,
    artists: attractions,
    genre: genre === null ? null : optionalString(genre.name, 80),
    imageURL,
    ticketURL,
  };
}

class TicketmasterDecodeError extends Error {
  constructor(
    readonly reason: TicketmasterRejectionReason,
    readonly code: TicketmasterRejectionCode,
    readonly attractionCount: number | null = null,
    readonly invalidAttractions: TicketmasterAttractionRejectionCounts = emptyAttractionCounts(),
  ) {
    super(code);
  }
}

function decodeStage<T>(
  reason: TicketmasterRejectionReason,
  code: TicketmasterRejectionCode,
  operation: () => T,
): T {
  try {
    return operation();
  } catch {
    throw new TicketmasterDecodeError(reason, code);
  }
}

function emptyRejectionReasons(): Record<TicketmasterRejectionReason, number> {
  return {
    event_shape: 0,
    event_dates: 0,
    venue: 0,
    lineup: 0,
    source_url: 0,
  };
}

function decodeVenue(value: unknown): DiscoveryVenue {
  const venue = object(value);
  const city = object(venue.city);
  const country = object(venue.country);
  const state = optionalObject(venue.state);
  const address = optionalObject(venue.address);
  const location = optionalObject(venue.location);
  return {
    id: string(venue.id, 200),
    name: string(venue.name, 160),
    url: venue.url === undefined ? null : httpsURL(venue.url),
    address: address === null ? null : optionalString(address.line1, 240),
    city: string(city.name, 160),
    stateCode: state === null ? null : optionalString(state.stateCode, 8),
    countryCode: countryCode(country.countryCode),
    latitude: location === null ? null : coordinate(location.latitude, -90, 90),
    longitude: location === null ? null : coordinate(location.longitude, -180, 180),
  };
}

function decodeAttractions(value: unknown): DiscoveryArtist[] {
  if (value === undefined) {
    throw new TicketmasterDecodeError("lineup", "attractions_missing");
  }
  if (!Array.isArray(value)) {
    throw new TicketmasterDecodeError("lineup", "attractions_not_array");
  }
  if (value.length > 20) {
    throw new TicketmasterDecodeError(
      "lineup",
      "attractions_too_many",
      boundedAuditCount(value.length),
    );
  }
  if (value.length === 0) {
    throw new TicketmasterDecodeError("lineup", "attractions_empty", 0);
  }
  const invalidAttractions = emptyAttractionCounts();
  const decoded = value.flatMap((artist) => {
    const result = decodeArtist(artist);
    if (result.artist !== null) return [result.artist];
    invalidAttractions[result.reason] += 1;
    return [];
  }).slice(0, 10);
  if (decoded.length === 0) {
    throw new TicketmasterDecodeError(
      "lineup",
      "attractions_all_invalid",
      value.length,
      invalidAttractions,
    );
  }
  return decoded;
}

function decodeArtist(
  value: unknown,
): { artist: DiscoveryArtist | null; reason: keyof TicketmasterAttractionRejectionCounts } {
  const artist = optionalObject(value);
  if (artist === null) return { artist: null, reason: "attractionShape" };
  let id: string;
  let name: string;
  let url: string | null;
  try {
    id = string(artist.id, 200);
  } catch {
    return { artist: null, reason: "artistId" };
  }
  try {
    name = string(artist.name, 160);
  } catch {
    return { artist: null, reason: "artistName" };
  }
  try {
    url = artist.url === undefined ? null : httpsURL(artist.url);
  } catch {
    return { artist: null, reason: "artistURL" };
  }
  return { artist: { id, name, url }, reason: "attractionShape" };
}

function rejectedEvent(
  value: unknown,
  rawPosition: number,
  error: unknown,
): TicketmasterRejectedEvent {
  const decodedError = error instanceof TicketmasterDecodeError
    ? error
    : new TicketmasterDecodeError("event_shape", "event_shape_invalid");
  const event = optionalObject(value);
  const dates = event === null ? null : optionalObject(event.dates);
  const start = dates === null ? null : optionalObject(dates.start);
  const embedded = event === null ? null : optionalObject(event._embedded);
  const venues = embedded !== null && Array.isArray(embedded.venues) ? embedded.venues : [];
  const venue = optionalObject(venues[0]);
  return {
    rawPosition,
    externalEventId: event === null ? null : safeAuditString(event.id, 200),
    eventName: event === null ? null : safeAuditString(event.name, 160),
    localDate: start === null ? null : safeAuditDate(start.localDate),
    venueName: venue === null ? null : safeAuditString(venue.name, 160),
    reason: decodedError.reason,
    code: decodedError.code,
    attractionCount: decodedError.attractionCount,
    invalidAttractions: decodedError.invalidAttractions,
  };
}

function emptyAttractionCounts(): TicketmasterAttractionRejectionCounts {
  return {
    attractionShape: 0,
    artistId: 0,
    artistName: 0,
    artistURL: 0,
  };
}

function safeAuditString(value: unknown, maximum: number): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().replace(/\s+/g, " ");
  if (
    normalized.length < 1 ||
    normalized.length > maximum ||
    Array.from(normalized).some((character) => {
      const codePoint = character.codePointAt(0) ?? 0;
      return codePoint <= 31 || codePoint === 127;
    })
  ) {
    return null;
  }
  return normalized;
}

function safeAuditDate(value: unknown): string | null {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) ? value : null;
}

function boundedAuditCount(value: number): number | null {
  return value <= 1_000 ? value : null;
}

function preferredImage(values: unknown[]): string | null {
  const candidates = values.flatMap((value) => {
    const image = optionalObject(value);
    if (image === null || typeof image.url !== "string" || !image.url.startsWith("https://")) {
      return [];
    }
    const width = typeof image.width === "number" ? image.width : 0;
    const ratio = typeof image.ratio === "string" ? image.ratio : "";
    return [{ url: image.url, score: (ratio === "16_9" ? 1_000_000 : 0) + width }];
  });
  return candidates.sort((lhs, rhs) => rhs.score - lhs.score)[0]?.url ?? null;
}

function mapStatus(value: string | null): DiscoveryCandidate["status"] {
  if (value === "cancelled" || value === "canceled") return "cancelled";
  if (value === "postponed" || value === "rescheduled") return "postponed";
  return "active";
}

function object(value: unknown): Record<string, unknown> {
  if (!isObject(value)) throw upstreamInvalid();
  return value;
}

function optionalObject(value: unknown): Record<string, unknown> | null {
  return isObject(value) ? value : null;
}

function array(value: unknown, maximum: number): unknown[] {
  if (!Array.isArray(value) || value.length > maximum) throw upstreamInvalid();
  return value;
}

function string(value: unknown, maximum: number): string {
  if (typeof value !== "string" || value.length < 1 || value.length > maximum) {
    throw upstreamInvalid();
  }
  return value;
}

function optionalString(value: unknown, maximum: number): string | null {
  return value === undefined || value === null ? null : string(value, maximum);
}

function integer(value: unknown): number {
  if (!Number.isInteger(value) || (value as number) < 0) throw upstreamInvalid();
  return value as number;
}

function countryCode(value: unknown): string {
  const code = string(value, 2);
  if (!/^[A-Z]{2}$/.test(code)) throw upstreamInvalid();
  return code;
}

function dateString(value: unknown): string {
  const result = string(value, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(result)) throw upstreamInvalid();
  return result;
}

function optionalTime(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  const result = string(value, 8);
  if (!/^\d{2}:\d{2}(?::\d{2})?$/.test(result)) throw upstreamInvalid();
  return result;
}

function optionalDateTime(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  const result = string(value, 40);
  if (!Number.isFinite(Date.parse(result))) throw upstreamInvalid();
  return result;
}

function httpsURL(value: unknown): string {
  const result = string(value, 2048);
  let url: URL;
  try {
    url = new URL(result);
  } catch {
    throw upstreamInvalid();
  }
  if (url.protocol !== "https:" || url.username !== "" || url.password !== "") {
    throw upstreamInvalid();
  }
  return url.href;
}

function coordinate(value: unknown, minimum: number, maximum: number): string | null {
  if (value === undefined || value === null) return null;
  const result = string(value, 32);
  const numeric = Number(result);
  if (!Number.isFinite(numeric) || numeric < minimum || numeric > maximum) throw upstreamInvalid();
  return result;
}

function upstreamInvalid(): DiscoveryError {
  return new DiscoveryError(
    "invalid_upstream_response",
    502,
    "Ticketmaster returned an unsupported event.",
    true,
  );
}
