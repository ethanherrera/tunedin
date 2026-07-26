import { invalidRequest } from "./errors.ts";
import {
  type ArtistSearchContext,
  CATALOG_KINDS,
  type CatalogKind,
  type CatalogRequest,
  type JsonObject,
  type JsonValue,
} from "./types.ts";

// PostgreSQL's uuid type accepts every canonical 128-bit value. tunedIn IDs
// therefore must not be restricted to an RFC version/variant (deterministic
// local fixtures intentionally use other bit layouts).
const UUID_PATTERN = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const MUSICBRAINZ_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const LUCENE_SPECIAL_CHARACTERS = new Set(
  Array.from('+-&|!(){}[]^"~*?:\\/'),
);

export function isPlainObject(
  value: unknown,
): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype;
}

export function assertExactKeys(
  object: Record<string, unknown>,
  allowed: readonly string[],
): void {
  const allowedSet = new Set(allowed);
  if (Object.keys(object).some((key) => !allowedSet.has(key))) {
    throw invalidRequest("The catalog request contains an unsupported field.");
  }
}

export function parseCatalogRequest(value: unknown): CatalogRequest {
  if (!isPlainObject(value) || typeof value.operation !== "string") {
    throw invalidRequest();
  }

  if (value.operation === "search") {
    assertExactKeys(value, [
      "operation",
      "entity",
      "query",
      "offset",
      "artistContextIds",
    ]);
    const entity = parseKind(value.entity);
    const query = normalizeSearchQuery(value.query);
    const offset = value.offset === undefined ? 0 : parseOffset(value.offset);
    const artistContextIds = value.artistContextIds === undefined
      ? []
      : parseArtistContextIds(value.artistContextIds);
    if (artistContextIds.length > 0 && entity !== "song" && entity !== "tour") {
      throw invalidRequest(
        "Artist context is supported only for song and tour searches.",
      );
    }

    return {
      operation: "search",
      entity,
      query,
      offset,
      artistContextIds,
    };
  }

  if (value.operation === "resolve") {
    assertExactKeys(value, ["operation", "entity", "musicBrainzId"]);
    return {
      operation: "resolve",
      entity: parseKind(value.entity),
      musicBrainzId: parseMusicBrainzUuid(
        value.musicBrainzId,
        "MusicBrainz ID",
      ),
    };
  }

  if (value.operation === "search_events") {
    assertExactKeys(value, ["operation", "query"]);
    return { operation: "search_events", query: normalizeSearchQuery(value.query) };
  }

  throw invalidRequest("The catalog operation is not supported.");
}

export function parseKind(value: unknown): CatalogKind {
  if (
    typeof value !== "string" || !CATALOG_KINDS.includes(value as CatalogKind)
  ) {
    throw invalidRequest("The catalog entity type is not supported.");
  }
  return value as CatalogKind;
}

export function normalizeSearchQuery(value: unknown): string {
  if (typeof value !== "string") {
    throw invalidRequest("A catalog search query is required.");
  }
  if (/\p{Cc}|\p{Cf}/u.test(value)) {
    throw invalidRequest(
      "The catalog search query contains unsupported characters.",
    );
  }
  const normalized = value.normalize("NFKC").trim().replace(/\s+/gu, " ");
  const visibleLength = Array.from(normalized).filter((character) => !/\s/u.test(character)).length;
  if (visibleLength < 2 || Array.from(normalized).length > 100) {
    throw invalidRequest("Catalog searches must contain 2-100 characters.");
  }
  return normalized;
}

export function parseUuid(value: unknown, fieldName = "ID"): string {
  if (typeof value !== "string" || !UUID_PATTERN.test(value)) {
    throw invalidRequest(`${fieldName} must be a UUID.`);
  }
  return value.toLowerCase();
}

export function parseMusicBrainzUuid(
  value: unknown,
  fieldName = "MusicBrainz ID",
): string {
  if (typeof value !== "string" || !MUSICBRAINZ_UUID_PATTERN.test(value)) {
    throw invalidRequest(`${fieldName} must be a UUID.`);
  }
  return value.toLowerCase();
}

function parseOffset(value: unknown): number {
  if (
    !Number.isInteger(value) || (value as number) < 0 || (value as number) > 150
  ) {
    throw invalidRequest(
      "Catalog search offset must be an integer from 0 through 150.",
    );
  }
  return value as number;
}

function parseArtistContextIds(value: unknown): string[] {
  if (!Array.isArray(value) || value.length > 10) {
    throw invalidRequest("Artist context must contain at most 10 catalog IDs.");
  }
  const ids = value.map((item) => parseUuid(item, "Artist context ID"));
  if (new Set(ids).size !== ids.length) {
    throw invalidRequest("Artist context IDs must be unique.");
  }
  return ids;
}

export function escapeLucene(value: string): string {
  let escaped = "";
  for (const character of value) {
    escaped += LUCENE_SPECIAL_CHARACTERS.has(character) ? `\\${character}` : character;
  }
  return escaped;
}

export function buildLuceneQuery(
  kind: CatalogKind,
  query: string,
  artistContext: ArtistSearchContext[] = [],
): string {
  const field: Record<CatalogKind, string> = {
    artist: "artist",
    area: "area",
    place: "place",
    song: "recording",
    tour: "series",
  };
  const phrase = `${field[kind]}:"${escapeLucene(query)}"`;
  if (kind === "tour") return `${phrase} AND type:"Tour"`;
  if (kind !== "song" || artistContext.length === 0) return phrase;
  const contextClauses = artistContext.map((artist) =>
    artist.musicBrainzId === null
      ? `artist:"${escapeLucene(artist.name)}"`
      : `arid:${artist.musicBrainzId}`
  );
  return `${phrase} AND (${contextClauses.join(" OR ")})`;
}

export function asJsonValue(value: unknown): JsonValue {
  if (
    value === null || typeof value === "string" || typeof value === "boolean"
  ) {
    return value;
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(asJsonValue);
  }
  if (isPlainObject(value)) {
    const result: JsonObject = {};
    for (const [key, child] of Object.entries(value)) {
      result[key] = asJsonValue(child);
    }
    return result;
  }
  throw new TypeError("Value is not JSON serializable");
}
