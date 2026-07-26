import { CatalogError } from "./errors.ts";
import type {
  ArtistCredit,
  ArtistSearchContext,
  CatalogKind,
  CatalogResult,
  JsonObject,
  MusicBrainzEventInput,
  UpstreamTransport,
} from "./types.ts";
import { artistCreditsFromMetadata } from "./result_validation.ts";
import { buildLuceneQuery, isPlainObject, parseMusicBrainzUuid } from "./validation.ts";

const SEARCH_LIMIT = 15;
const MAX_RESPONSE_BYTES = 1_000_000;
const DEFAULT_TIMEOUT_MS = 8_000;
const MAX_REDIRECTS = 2;

const endpointFor: Record<CatalogKind, string> = {
  artist: "artist",
  area: "area",
  place: "place",
  song: "recording",
  tour: "series",
};

const collectionFor: Record<CatalogKind, string> = {
  artist: "artists",
  area: "areas",
  place: "places",
  song: "recordings",
  tour: "series",
};

export interface MusicBrainzClientOptions {
  baseUrl: URL;
  userAgent: string;
  fetch?: typeof fetch;
  timeoutMs?: number;
  maxResponseBytes?: number;
  beforeRedirect?: () => Promise<void>;
}

export class MusicBrainzClient implements UpstreamTransport {
  readonly #baseUrl: URL;
  readonly #userAgent: string;
  readonly #fetch: typeof fetch;
  readonly #timeoutMs: number;
  readonly #maxResponseBytes: number;
  readonly #beforeRedirect: () => Promise<void>;

  constructor(options: MusicBrainzClientOptions) {
    this.#baseUrl = options.baseUrl;
    this.#userAgent = options.userAgent;
    this.#fetch = options.fetch ?? fetch;
    this.#timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.#maxResponseBytes = options.maxResponseBytes ?? MAX_RESPONSE_BYTES;
    this.#beforeRedirect = options.beforeRedirect ?? (() => Promise.resolve());
  }

  async search(
    kind: CatalogKind,
    query: string,
    offset: number,
    artistContext: ArtistSearchContext[],
  ): Promise<{ results: CatalogResult[]; hasMore: boolean }> {
    const url = new URL(endpointFor[kind], this.#baseUrl);
    url.searchParams.set("query", buildLuceneQuery(kind, query, artistContext));
    url.searchParams.set("fmt", "json");
    url.searchParams.set("limit", String(SEARCH_LIMIT));
    url.searchParams.set("offset", String(offset));

    const payload = await this.#requestJson(url, "search");
    const decoded = decodeSearchPayload(kind, payload, offset);
    return {
      ...decoded,
      results: kind === "song"
        ? rankByArtistContext(decoded.results, artistContext)
        : decoded.results,
    };
  }

  async lookup(
    kind: CatalogKind,
    musicBrainzId: string,
  ): Promise<CatalogResult> {
    const endpoint = endpointFor[kind];
    const url = new URL(`${endpoint}/${musicBrainzId}`, this.#baseUrl);
    url.searchParams.set("fmt", "json");
    if (kind === "song") {
      url.searchParams.set("inc", "artist-credits+work-rels");
    } else if (kind === "tour") {
      url.searchParams.set("inc", "artist-rels");
    }
    const payload = await this.#requestJson(url, "lookup");
    const entity = decodeEntity(kind, payload);
    if (
      kind === "song" && artistCreditsFromMetadata(entity.metadata).length === 0
    ) {
      throw invalidUpstream();
    }
    return entity;
  }

  async searchEvents(query: string): Promise<MusicBrainzEventInput[]> {
    const url = new URL("event", this.#baseUrl);
    url.searchParams.set(
      "query",
      `type:"Concert" AND (event:"${escapeEventQuery(query)}" OR artist:"${
        escapeEventQuery(query)
      }" OR place:"${escapeEventQuery(query)}" OR area:"${escapeEventQuery(query)}")`,
    );
    url.searchParams.set("fmt", "json");
    url.searchParams.set("limit", "5");
    url.searchParams.set("inc", "artist-rels+place-rels");
    const payload = await this.#requestJson(url, "search");
    const root = objectValue(payload);
    return arrayValue(root.events, "events", 5)
      .flatMap((value) => {
        try {
          return [decodeEvent(value)];
        } catch {
          return [];
        }
      });
  }

  async #requestJson(
    url: URL,
    requestType: "search" | "lookup",
  ): Promise<unknown> {
    this.#assertAllowedUrl(url);
    let currentUrl = url;

    for (let redirects = 0; redirects <= MAX_REDIRECTS; redirects += 1) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), this.#timeoutMs);
      let response: Response;
      try {
        response = await this.#fetch(currentUrl, {
          method: "GET",
          redirect: "manual",
          headers: {
            Accept: "application/json",
            "User-Agent": this.#userAgent,
          },
          signal: controller.signal,
        });
      } catch (error) {
        clearTimeout(timeout);
        if (
          controller.signal.aborted ||
          (error instanceof DOMException && error.name === "AbortError")
        ) {
          throw new CatalogError(
            "upstream_timeout",
            504,
            "MusicBrainz did not respond in time.",
            true,
          );
        }
        throw new CatalogError(
          "upstream_unavailable",
          503,
          "MusicBrainz is temporarily unavailable.",
          true,
        );
      }

      try {
        if ([301, 302, 307, 308].includes(response.status)) {
          if (redirects === MAX_REDIRECTS) {
            throw invalidUpstream();
          }
          const location = response.headers.get("location");
          if (location === null) {
            throw invalidUpstream();
          }
          currentUrl = new URL(location, currentUrl);
          this.#assertAllowedUrl(currentUrl);
          await this.#beforeRedirect();
          continue;
        }

        if (response.status === 404 && requestType === "lookup") {
          throw new CatalogError(
            "candidate_not_found",
            404,
            "That MusicBrainz result is no longer available.",
          );
        }
        if (response.status === 429) {
          const retryAfterSeconds = parseRetryAfter(
            response.headers.get("retry-after"),
          );
          throw new CatalogError(
            "upstream_rate_limited",
            503,
            "MusicBrainz is busy. Try again shortly.",
            true,
            retryAfterSeconds,
          );
        }
        if (!response.ok) {
          throw new CatalogError(
            "upstream_unavailable",
            503,
            "MusicBrainz is temporarily unavailable.",
            true,
          );
        }

        const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
        if (!contentType.startsWith("application/json")) {
          throw invalidUpstream();
        }
        return await readBoundedJson(response, this.#maxResponseBytes);
      } catch (error) {
        if (error instanceof CatalogError) throw error;
        if (
          controller.signal.aborted ||
          (error instanceof DOMException && error.name === "AbortError")
        ) {
          throw new CatalogError(
            "upstream_timeout",
            504,
            "MusicBrainz did not respond in time.",
            true,
          );
        }
        throw invalidUpstream();
      } finally {
        clearTimeout(timeout);
      }
    }

    throw invalidUpstream();
  }

  #assertAllowedUrl(url: URL): void {
    if (
      url.origin !== this.#baseUrl.origin ||
      !url.pathname.startsWith(this.#baseUrl.pathname) ||
      url.username !== "" ||
      url.password !== "" ||
      url.hash !== ""
    ) {
      throw new CatalogError(
        "upstream_invalid_response",
        502,
        "MusicBrainz returned an invalid response.",
        true,
      );
    }
  }
}

export async function readBoundedJson(
  response: Response,
  maxBytes: number,
): Promise<unknown> {
  const declaredLength = response.headers.get("content-length");
  if (declaredLength !== null && Number(declaredLength) > maxBytes) {
    throw invalidUpstream();
  }

  const reader = response.body?.getReader();
  if (reader === undefined) {
    throw invalidUpstream();
  }
  const chunks: Uint8Array[] = [];
  let byteCount = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    byteCount += value.byteLength;
    if (byteCount > maxBytes) {
      await reader.cancel();
      throw invalidUpstream();
    }
    chunks.push(value);
  }

  const bytes = new Uint8Array(byteCount);
  let cursor = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, cursor);
    cursor += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw invalidUpstream();
  }
}

export function decodeSearchPayload(
  kind: CatalogKind,
  value: unknown,
  requestedOffset: number,
): { results: CatalogResult[]; hasMore: boolean } {
  const object = objectValue(value);
  const count = integerValue(object.count, "count", 0, 10_000_000);
  const offset = integerValue(object.offset, "offset", 0, 10_000_000);
  if (offset !== requestedOffset) {
    throw invalidUpstream();
  }
  const collection = arrayValue(
    object[collectionFor[kind]],
    collectionFor[kind],
    SEARCH_LIMIT,
  );
  const results = collection.map((entity) => decodeEntity(kind, entity));
  return { results, hasMore: offset + results.length < count };
}

export function decodeEntity(kind: CatalogKind, value: unknown): CatalogResult {
  const object = objectValue(value);
  switch (kind) {
    case "artist":
      return decodeArtist(object);
    case "area":
      return decodeArea(object);
    case "place":
      return decodePlace(object);
    case "song":
      return decodeRecording(object);
    case "tour":
      return decodeTour(object);
  }
}

function decodeArtist(object: Record<string, unknown>): CatalogResult {
  const area = optionalObject(object.area);
  const lifeSpan = optionalObject(object["life-span"]);
  const artistType = optionalString(object.type, "type", 80);
  const areaName = area === null ? null : optionalString(area.name, "area.name", 160);
  const areaMusicBrainzId = area === null ? null : optionalUuid(area.id, "area.id");
  const countryCode = optionalCode(object.country, "country", 2);
  const lifeSpanBegin = lifeSpan === null
    ? null
    : optionalPartialDate(lifeSpan.begin, "life-span.begin");
  const lifeSpanEnd = lifeSpan === null ? null : optionalPartialDate(lifeSpan.end, "life-span.end");
  const ended = lifeSpan === null ? null : optionalBoolean(lifeSpan.ended, "life-span.ended");
  const disambiguation = optionalString(
    object.disambiguation,
    "disambiguation",
    240,
  );
  return candidate(
    "artist",
    object,
    stringValue(object.name, "name", 160),
    optionalString(object["sort-name"], "sort-name", 160),
    disambiguation,
    compactSubtitle([artistType, areaName, countryCode]),
    {
      artistType,
      countryCode,
      areaCatalogId: null,
      areaMusicBrainzId,
      areaName,
      lifeSpanBegin,
      lifeSpanEnd,
      ended,
    },
  );
}

function decodeArea(object: Record<string, unknown>): CatalogResult {
  const areaType = optionalString(object.type, "type", 80);
  const countryCode = firstCode(object["iso-3166-1-codes"], 2);
  const subdivisionCode = firstCode(object["iso-3166-2-codes"], 10);
  const disambiguation = optionalString(
    object.disambiguation,
    "disambiguation",
    240,
  );
  return candidate(
    "area",
    object,
    stringValue(object.name, "name", 160),
    optionalString(object["sort-name"], "sort-name", 160),
    disambiguation,
    compactSubtitle([areaType, subdivisionCode, countryCode]),
    {
      areaType,
      countryCode,
      subdivisionCode,
      parentAreaCatalogId: null,
      parentMusicBrainzId: null,
      parentName: null,
    },
  );
}

function decodePlace(object: Record<string, unknown>): CatalogResult {
  const area = optionalObject(object.area);
  const coordinates = optionalObject(object.coordinates);
  const lifeSpan = optionalObject(object["life-span"]);
  const placeType = optionalString(object.type, "type", 80);
  const address = optionalString(object.address, "address", 240);
  const areaMusicBrainzId = area === null ? null : optionalUuid(area.id, "area.id");
  const areaName = area === null ? null : optionalString(area.name, "area.name", 160);
  const latitude = coordinates === null
    ? null
    : optionalCoordinate(coordinates.latitude, "coordinates.latitude", -90, 90);
  const longitude = coordinates === null ? null : optionalCoordinate(
    coordinates.longitude,
    "coordinates.longitude",
    -180,
    180,
  );
  const ended = lifeSpan === null ? null : optionalBoolean(lifeSpan.ended, "life-span.ended");
  const disambiguation = optionalString(
    object.disambiguation,
    "disambiguation",
    240,
  );
  return candidate(
    "place",
    object,
    stringValue(object.name, "name", 160),
    optionalString(object["sort-name"], "sort-name", 160),
    disambiguation,
    compactSubtitle([placeType, areaName, address]),
    {
      placeType,
      address,
      latitude,
      longitude,
      ended,
      areaCatalogId: null,
      areaMusicBrainzId,
      areaName,
    },
  );
}

function decodeRecording(object: Record<string, unknown>): CatalogResult {
  const credits = decodeArtistCredits(object["artist-credit"]);
  if (credits.length === 0) throw invalidUpstream();
  const workMusicBrainzId = decodeWorkMusicBrainzId(object.relations);
  const durationMs = optionalInteger(object.length, "length", 0, 86_400_000);
  const firstReleaseDate = optionalPartialDate(
    object["first-release-date"],
    "first-release-date",
  );
  const disambiguation = optionalString(
    object.disambiguation,
    "disambiguation",
    240,
  );
  const artistLabel = credits.map((credit) => `${credit.name}${credit.joinPhrase}`).join("");
  return candidate(
    "song",
    object,
    stringValue(object.title, "title", 160),
    null,
    disambiguation,
    compactSubtitle([artistLabel || null, firstReleaseDate]),
    {
      workMusicBrainzId,
      durationMs,
      firstReleaseDate,
      artistCredit: credits.map((credit) => ({ ...credit })),
    },
  );
}

function decodeTour(object: Record<string, unknown>): CatalogResult {
  const seriesType = optionalString(object.type, "type", 80);
  if (seriesType !== null && seriesType.toLocaleLowerCase("en-US") !== "tour") {
    throw invalidUpstream();
  }
  const disambiguation = optionalString(
    object.disambiguation,
    "disambiguation",
    240,
  );
  const credits = decodeArtistRelations(object.relations);
  const artistLabel = credits.map((credit) => `${credit.name}${credit.joinPhrase}`).join("");
  return candidate(
    "tour",
    object,
    stringValue(object.name, "name", 160),
    null,
    disambiguation,
    compactSubtitle([artistLabel || null, seriesType, disambiguation]),
    {
      seriesType,
      disambiguation,
      artistCredit: credits.map((credit) => ({ ...credit })),
    },
  );
}

function decodeEvent(value: unknown): MusicBrainzEventInput {
  const event = objectValue(value);
  if (optionalString(event.type, "type", 80)?.toLocaleLowerCase("en-US") !== "concert") {
    throw invalidUpstream();
  }
  const lifeSpan = objectValue(event["life-span"]);
  const eventDate = stringValue(lifeSpan.begin, "life-span.begin", 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(eventDate)) throw invalidUpstream();
  const rawTime = optionalString(event.time, "time", 32);
  const localStartTime = rawTime === null ? null : normalizeEventTime(rawTime);
  const relations = arrayValue(event.relations, "relations", 100);
  const artists: MusicBrainzEventInput["artists"] = [];
  let venue: MusicBrainzEventInput["venue"] | null = null;
  for (const value of relations) {
    const relation = objectValue(value);
    const artist = optionalObject(relation.artist);
    if (artist !== null && artists.length < 10) {
      artists.push({
        mbid: requiredUuid(artist.id, "relations.artist.id"),
        name: stringValue(artist.name, "relations.artist.name", 160),
        is_headliner: relation.type === "main performer" || relation.type === "headliner",
      });
    }
    const place = optionalObject(relation.place);
    if (place !== null && venue === null) {
      const area = optionalObject(place.area);
      venue = {
        mbid: requiredUuid(place.id, "relations.place.id"),
        name: stringValue(place.name, "relations.place.name", 160),
        area_mbid: area === null ? null : optionalUuid(area.id, "relations.place.area.id"),
        area_name: area === null
          ? null
          : optionalString(area.name, "relations.place.area.name", 160),
      };
    }
  }
  if (artists.length === 0 || venue === null) throw invalidUpstream();
  if (!artists.some((artist) => artist.is_headliner)) artists[0].is_headliner = true;
  return {
    event_mbid: requiredUuid(event.id, "id"),
    title: stringValue(event.name, "name", 160),
    event_date: eventDate,
    local_start_time: localStartTime,
    venue,
    artists,
    source_status: event.cancelled === true ? "cancelled" : "active",
    source_updated_at: optionalString(event["last-updated"], "last-updated", 40),
  };
}

function normalizeEventTime(value: string): string {
  const normalized = value.replace(/\s+/g, "");
  const matched = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(normalized);
  if (matched === null) throw invalidUpstream();
  const hour = Number(matched[1]);
  const minute = Number(matched[2]);
  const second = Number(matched[3] ?? "0");
  if (hour > 23 || minute > 59 || second > 59) throw invalidUpstream();
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:${
    String(second).padStart(2, "0")
  }`;
}

function escapeEventQuery(value: string): string {
  return value.replace(/[+\-&|!(){}\[\]^"~*?:\\/]/g, "\\$&");
}

function candidate(
  kind: CatalogKind,
  object: Record<string, unknown>,
  displayName: string,
  sortName: string | null,
  disambiguation: string | null,
  subtitle: string | null,
  metadata: JsonObject,
): CatalogResult {
  return {
    source: "musicbrainz",
    origin: "musicbrainz",
    kind,
    catalogId: null,
    musicBrainzId: requiredUuid(object.id, "id"),
    displayName,
    sortName,
    disambiguation,
    subtitle,
    metadata,
  };
}

function decodeArtistCredits(value: unknown): ArtistCredit[] {
  if (value === undefined) return [];
  return arrayValue(value, "artist-credit", 50).map((item) => {
    const credit = objectValue(item);
    const artist = objectValue(credit.artist);
    return {
      artistCatalogId: null,
      artistMusicBrainzId: requiredUuid(artist.id, "artist-credit.artist.id"),
      name: optionalString(credit.name, "artist-credit.name", 160) ??
        stringValue(artist.name, "artist-credit.artist.name", 160),
      canonicalName: stringValue(artist.name, "artist-credit.artist.name", 160),
      joinPhrase: optionalString(credit.joinphrase, "artist-credit.joinphrase", 40) ?? "",
    };
  });
}

function decodeArtistRelations(value: unknown): ArtistCredit[] {
  if (value === undefined) return [];
  const relations = arrayValue(value, "relations", 100);
  const credits: ArtistCredit[] = [];
  for (const item of relations) {
    const relation = objectValue(item);
    if (relation.type !== "tour") continue;
    const artist = optionalObject(relation.artist);
    if (artist === null) continue;
    credits.push({
      artistCatalogId: null,
      artistMusicBrainzId: requiredUuid(artist.id, "relations.artist.id"),
      name: stringValue(artist.name, "relations.artist.name", 160),
      canonicalName: stringValue(artist.name, "relations.artist.name", 160),
      joinPhrase: "",
    });
  }
  for (let index = 0; index + 1 < credits.length; index += 1) {
    credits[index].joinPhrase = ", ";
  }
  return credits;
}

function decodeWorkMusicBrainzId(value: unknown): string | null {
  if (value === undefined) return null;
  for (const item of arrayValue(value, "relations", 100)) {
    const relation = objectValue(item);
    const work = optionalObject(relation.work);
    if (work !== null && relation.type === "performance") {
      return requiredUuid(work.id, "relations.work.id");
    }
  }
  return null;
}

function objectValue(value: unknown): Record<string, unknown> {
  if (!isPlainObject(value)) throw invalidUpstream();
  return value;
}

function optionalObject(value: unknown): Record<string, unknown> | null {
  if (value === undefined || value === null) return null;
  return objectValue(value);
}

function arrayValue(
  value: unknown,
  _field: string,
  maxLength: number,
): unknown[] {
  if (!Array.isArray(value) || value.length > maxLength) {
    throw invalidUpstream();
  }
  return value;
}

function stringValue(
  value: unknown,
  _field: string,
  maxLength: number,
): string {
  if (
    typeof value !== "string" || value.length === 0 ||
    Array.from(value).length > maxLength ||
    /[\p{Cc}\p{Cf}]/u.test(value)
  ) {
    throw invalidUpstream();
  }
  return value;
}

function optionalString(
  value: unknown,
  field: string,
  maxLength: number,
): string | null {
  if (value === undefined || value === null || value === "") return null;
  return stringValue(value, field, maxLength);
}

function integerValue(
  value: unknown,
  _field: string,
  minimum: number,
  maximum: number,
): number {
  if (
    !Number.isInteger(value) || (value as number) < minimum ||
    (value as number) > maximum
  ) {
    throw invalidUpstream();
  }
  return value as number;
}

function optionalInteger(
  value: unknown,
  field: string,
  minimum: number,
  maximum: number,
): number | null {
  if (value === undefined || value === null) return null;
  return integerValue(value, field, minimum, maximum);
}

function optionalBoolean(value: unknown, _field: string): boolean | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "boolean") throw invalidUpstream();
  return value;
}

function optionalCoordinate(
  value: unknown,
  _field: string,
  minimum: number,
  maximum: number,
): number | null {
  if (value === undefined || value === null) return null;
  const number = typeof value === "string" && value.trim() !== "" ? Number(value) : value;
  if (
    typeof number !== "number" || !Number.isFinite(number) ||
    number < minimum || number > maximum
  ) {
    throw invalidUpstream();
  }
  return number;
}

function optionalPartialDate(value: unknown, field: string): string | null {
  if (value === undefined || value === null || value === "") return null;
  const date = stringValue(value, field, 10);
  if (
    !/^\d{4}(?:-(?:0[1-9]|1[0-2])(?:-(?:0[1-9]|[12]\d|3[01]))?)?$/.test(date)
  ) {
    throw invalidUpstream();
  }
  return date;
}

function optionalCode(
  value: unknown,
  field: string,
  maxLength: number,
): string | null {
  if (value === undefined || value === null || value === "") return null;
  const code = stringValue(value, field, maxLength);
  if (!/^[A-Z0-9-]+$/.test(code)) throw invalidUpstream();
  return code;
}

function firstCode(value: unknown, maxLength: number): string | null {
  if (value === undefined || value === null) return null;
  const values = arrayValue(value, "codes", 20);
  return values.length === 0 ? null : optionalCode(values[0], "code", maxLength);
}

function requiredUuid(value: unknown, field: string): string {
  try {
    return parseMusicBrainzUuid(value, field);
  } catch {
    throw invalidUpstream();
  }
}

function optionalUuid(value: unknown, field: string): string | null {
  if (value === undefined || value === null) return null;
  return requiredUuid(value, field);
}

function compactSubtitle(values: Array<string | null>): string | null {
  const subtitle = values.filter((value): value is string => value !== null && value !== "").join(
    " · ",
  );
  return subtitle === "" ? null : subtitle.slice(0, 500);
}

function rankByArtistContext(
  results: CatalogResult[],
  artistContext: ArtistSearchContext[],
): CatalogResult[] {
  if (artistContext.length === 0) return results;
  const scored = results.map((result, index) => ({
    result,
    index,
    score: artistContextScore(result, artistContext),
  }));
  scored.sort((left, right) => right.score - left.score || left.index - right.index);
  return scored.map(({ result }) => result);
}

function artistContextScore(
  result: CatalogResult,
  artistContext: ArtistSearchContext[],
): number {
  const credits = artistCreditsFromMetadata(result.metadata);
  let score = 0;
  for (const context of artistContext) {
    const normalizedContextName = context.name.normalize("NFKC")
      .toLocaleLowerCase("en-US");
    for (const credit of credits) {
      if (
        context.musicBrainzId !== null &&
        credit.artistMusicBrainzId === context.musicBrainzId
      ) {
        score += 4;
        continue;
      }
      if (
        credit.canonicalName.normalize("NFKC").toLocaleLowerCase("en-US") ===
          normalizedContextName ||
        credit.name.normalize("NFKC").toLocaleLowerCase("en-US") ===
          normalizedContextName
      ) {
        score += 2;
      }
    }
  }
  return score;
}

function parseRetryAfter(value: string | null): number | null {
  if (value === null) return null;
  const seconds = Number(value);
  if (Number.isInteger(seconds) && seconds >= 1 && seconds <= 300) {
    return seconds;
  }
  return null;
}

function invalidUpstream(): CatalogError {
  return new CatalogError(
    "upstream_invalid_response",
    502,
    "MusicBrainz returned an invalid response.",
    true,
  );
}
