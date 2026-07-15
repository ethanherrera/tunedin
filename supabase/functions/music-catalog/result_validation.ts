import { CatalogError } from "./errors.ts";
import type { ArtistCredit, CatalogKind, CatalogResult, JsonObject, JsonValue } from "./types.ts";
import { CATALOG_KINDS, CATALOG_ORIGINS } from "./types.ts";
import { isPlainObject } from "./validation.ts";

const CATALOG_UUID_PATTERN = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const MUSICBRAINZ_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export interface ResultValidationOptions {
  expectedKind?: CatalogKind;
  expectedSource?: "tunedin" | "musicbrainz";
}

export function decodeCatalogResult(
  value: unknown,
  options: ResultValidationOptions = {},
): CatalogResult {
  const object = objectValue(value);
  exactKeys(object, [
    "source",
    "origin",
    "kind",
    "catalogId",
    "musicBrainzId",
    "displayName",
    "sortName",
    "disambiguation",
    "subtitle",
    "metadata",
  ]);
  const source = oneOf(object.source, ["tunedin", "musicbrainz"] as const);
  const origin = oneOf(object.origin, CATALOG_ORIGINS);
  const kind = oneOf(object.kind, CATALOG_KINDS);
  if (options.expectedKind !== undefined && kind !== options.expectedKind) throw invalidResult();
  if (options.expectedSource !== undefined && source !== options.expectedSource) {
    throw invalidResult();
  }

  const catalogId = nullableCatalogUuid(object.catalogId);
  const musicBrainzId = nullableMusicBrainzUuid(object.musicBrainzId);
  if (
    source === "musicbrainz" &&
    (catalogId !== null || origin !== "musicbrainz" || musicBrainzId === null)
  ) {
    throw invalidResult();
  }
  if (source === "tunedin" && catalogId === null) throw invalidResult();

  return {
    source,
    origin,
    kind,
    catalogId,
    musicBrainzId,
    displayName: boundedString(object.displayName, 160),
    sortName: nullableString(object.sortName, 160),
    disambiguation: nullableString(object.disambiguation, 240),
    subtitle: nullableString(object.subtitle, 500),
    metadata: decodeMetadata(kind, object.metadata),
  };
}

export function decodeMetadata(
  kind: CatalogKind,
  value: unknown,
): JsonObject {
  const object = objectValue(value);
  switch (kind) {
    case "artist": {
      exactKeys(object, [
        "artistType",
        "countryCode",
        "areaCatalogId",
        "areaMusicBrainzId",
        "areaName",
        "lifeSpanBegin",
        "lifeSpanEnd",
        "ended",
      ]);
      return {
        artistType: nullableString(object.artistType, 80),
        countryCode: nullableCode(object.countryCode, 2),
        areaCatalogId: nullableCatalogUuid(object.areaCatalogId),
        areaMusicBrainzId: nullableMusicBrainzUuid(object.areaMusicBrainzId),
        areaName: nullableString(object.areaName, 160),
        lifeSpanBegin: nullableDate(object.lifeSpanBegin),
        lifeSpanEnd: nullableDate(object.lifeSpanEnd),
        ended: nullableBoolean(object.ended),
      };
    }
    case "area": {
      exactKeys(object, [
        "areaType",
        "countryCode",
        "subdivisionCode",
        "parentAreaCatalogId",
        "parentMusicBrainzId",
        "parentName",
      ]);
      return {
        areaType: nullableString(object.areaType, 80),
        countryCode: nullableCode(object.countryCode, 2),
        subdivisionCode: nullableCode(object.subdivisionCode, 10),
        parentAreaCatalogId: nullableCatalogUuid(object.parentAreaCatalogId),
        parentMusicBrainzId: nullableMusicBrainzUuid(object.parentMusicBrainzId),
        parentName: nullableString(object.parentName, 160),
      };
    }
    case "place": {
      exactKeys(object, [
        "placeType",
        "address",
        "latitude",
        "longitude",
        "ended",
        "areaCatalogId",
        "areaMusicBrainzId",
        "areaName",
      ]);
      return {
        placeType: nullableString(object.placeType, 80),
        address: nullableString(object.address, 240),
        latitude: nullableNumber(object.latitude, -90, 90),
        longitude: nullableNumber(object.longitude, -180, 180),
        ended: nullableBoolean(object.ended),
        areaCatalogId: nullableCatalogUuid(object.areaCatalogId),
        areaMusicBrainzId: nullableMusicBrainzUuid(object.areaMusicBrainzId),
        areaName: nullableString(object.areaName, 160),
      };
    }
    case "song": {
      exactKeys(object, [
        "workMusicBrainzId",
        "durationMs",
        "firstReleaseDate",
        "artistCredit",
      ]);
      const artistCredit = decodeCredits(object.artistCredit, true);
      return {
        workMusicBrainzId: nullableMusicBrainzUuid(object.workMusicBrainzId),
        durationMs: nullableInteger(object.durationMs, 0, 86_400_000),
        firstReleaseDate: nullableDate(object.firstReleaseDate),
        artistCredit,
      };
    }
    case "tour": {
      exactKeys(object, ["seriesType", "disambiguation", "artistCredit"]);
      const artistCredit = decodeCredits(object.artistCredit, false);
      return {
        seriesType: nullableString(object.seriesType, 80),
        disambiguation: nullableString(object.disambiguation, 240),
        artistCredit,
      };
    }
  }
}

export function artistCreditsFromMetadata(metadata: JsonObject): ArtistCredit[] {
  const value = metadata.artistCredit;
  if (!Array.isArray(value)) return [];
  return value.map((credit) => {
    if (!isPlainObject(credit)) throw invalidResult();
    const artistCatalogId = nullableCatalogUuid(credit.artistCatalogId);
    const artistMusicBrainzId = nullableMusicBrainzUuid(credit.artistMusicBrainzId);
    if (artistCatalogId === null && artistMusicBrainzId === null) throw invalidResult();
    return {
      artistCatalogId,
      artistMusicBrainzId,
      name: boundedString(credit.name, 160),
      canonicalName: boundedString(credit.canonicalName, 160),
      joinPhrase: boundedStringAllowEmpty(credit.joinPhrase, 40),
    };
  });
}

function decodeCredits(value: unknown, required: boolean): JsonValue[] {
  if (!Array.isArray(value) || value.length > 50 || (required && value.length === 0)) {
    throw invalidResult();
  }
  const seen = new Set<string>();
  return value.map((item) => {
    const credit = objectValue(item);
    exactKeys(credit, [
      "artistCatalogId",
      "artistMusicBrainzId",
      "name",
      "canonicalName",
      "joinPhrase",
    ]);
    const artistCatalogId = nullableCatalogUuid(credit.artistCatalogId);
    const artistMusicBrainzId = nullableMusicBrainzUuid(credit.artistMusicBrainzId);
    if (artistCatalogId === null && artistMusicBrainzId === null) throw invalidResult();
    const identity = artistCatalogId ?? `mb:${artistMusicBrainzId}`;
    if (seen.has(identity)) throw invalidResult();
    seen.add(identity);
    return {
      artistCatalogId,
      artistMusicBrainzId,
      name: boundedString(credit.name, 160),
      canonicalName: boundedString(credit.canonicalName, 160),
      joinPhrase: boundedStringAllowEmpty(credit.joinPhrase, 40),
    };
  });
}

function exactKeys(object: Record<string, unknown>, expected: readonly string[]): void {
  const actual = Object.keys(object).sort();
  const wanted = [...expected].sort();
  if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
    throw invalidResult();
  }
}

function objectValue(value: unknown): Record<string, unknown> {
  if (!isPlainObject(value)) throw invalidResult();
  return value;
}

function oneOf<T extends string>(value: unknown, allowed: readonly T[]): T {
  if (typeof value !== "string" || !allowed.includes(value as T)) throw invalidResult();
  return value as T;
}

function boundedString(value: unknown, maximum: number): string {
  if (
    typeof value !== "string" || value.length === 0 || Array.from(value).length > maximum ||
    /[\p{Cc}\p{Cf}]/u.test(value)
  ) {
    throw invalidResult();
  }
  return value;
}

function boundedStringAllowEmpty(value: unknown, maximum: number): string {
  if (
    typeof value !== "string" || Array.from(value).length > maximum || /[\p{Cc}\p{Cf}]/u.test(value)
  ) {
    throw invalidResult();
  }
  return value;
}

function nullableString(value: unknown, maximum: number): string | null {
  if (value === null) return null;
  return boundedString(value, maximum);
}

function requiredCatalogUuid(value: unknown): string {
  if (typeof value !== "string" || !CATALOG_UUID_PATTERN.test(value)) throw invalidResult();
  return value.toLowerCase();
}

function nullableCatalogUuid(value: unknown): string | null {
  if (value === null) return null;
  return requiredCatalogUuid(value);
}

function requiredMusicBrainzUuid(value: unknown): string {
  if (typeof value !== "string" || !MUSICBRAINZ_UUID_PATTERN.test(value)) throw invalidResult();
  return value.toLowerCase();
}

function nullableMusicBrainzUuid(value: unknown): string | null {
  if (value === null) return null;
  return requiredMusicBrainzUuid(value);
}

function nullableBoolean(value: unknown): boolean | null {
  if (value === null) return null;
  if (typeof value !== "boolean") throw invalidResult();
  return value;
}

function nullableNumber(value: unknown, minimum: number, maximum: number): number | null {
  if (value === null) return null;
  if (typeof value !== "number" || !Number.isFinite(value) || value < minimum || value > maximum) {
    throw invalidResult();
  }
  return value;
}

function nullableInteger(value: unknown, minimum: number, maximum: number): number | null {
  const number = nullableNumber(value, minimum, maximum);
  if (number !== null && !Number.isInteger(number)) throw invalidResult();
  return number;
}

function nullableCode(value: unknown, maximum: number): string | null {
  const code = nullableString(value, maximum);
  if (code !== null && !/^[A-Z0-9-]+$/.test(code)) throw invalidResult();
  return code;
}

function nullableDate(value: unknown): string | null {
  const date = nullableString(value, 10);
  if (date !== null && !/^\d{4}(?:-(?:0[1-9]|1[0-2])(?:-(?:0[1-9]|[12]\d|3[01]))?)?$/.test(date)) {
    throw invalidResult();
  }
  return date;
}

function invalidResult(): CatalogError {
  return new CatalogError(
    "upstream_invalid_response",
    502,
    "MusicBrainz returned an invalid response.",
    true,
  );
}
