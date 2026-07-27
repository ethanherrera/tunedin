import { DiscoveryError } from "./errors.ts";
import type { DiscoveryRequest } from "./types.ts";

const SAFE_TEXT = /^[\p{L}\p{N} .,'&()/-]+$/u;
const SAFE_ID = /^[A-Za-z0-9_-]{1,200}$/;
const COUNTRY_CODE = /^[A-Z]{2}$/;
const STATE_CODE = /^[A-Z0-9-]{1,8}$/;

export function parseDiscoveryRequest(value: unknown): DiscoveryRequest {
  if (!isObject(value) || typeof value.operation !== "string") throw invalidRequest();
  if (value.operation === "resolve") {
    assertKeys(value, ["operation", "eventId"]);
    if (typeof value.eventId !== "string" || !SAFE_ID.test(value.eventId)) throw invalidRequest();
    return { operation: "resolve", eventId: value.eventId };
  }
  if (value.operation !== "discover") throw invalidRequest();
  assertKeys(value, [
    "operation",
    "location",
    "startDateTime",
    "endDateTime",
    "page",
  ], ["genre"]);
  if (!isObject(value.location)) throw invalidRequest();
  assertKeys(value.location, ["city", "countryCode"], ["stateCode"]);
  const city = normalizedText(value.location.city, 100);
  const genreValue = value.genre;
  const genre = genreValue === undefined || genreValue === null
    ? null
    : normalizedText(genreValue, 80);
  const stateCodeValue = value.location.stateCode;
  const stateCode = stateCodeValue === undefined ? null : stateCodeValue;
  if (
    city === null ||
    (genreValue !== undefined && genreValue !== null && genre === null) ||
    typeof value.location.countryCode !== "string" ||
    !COUNTRY_CODE.test(value.location.countryCode) ||
    (stateCode !== null && (typeof stateCode !== "string" || !STATE_CODE.test(stateCode))) ||
    !isDateTime(value.startDateTime) ||
    !isDateTime(value.endDateTime) ||
    Date.parse(value.endDateTime as string) <= Date.parse(value.startDateTime as string) ||
    !Number.isInteger(value.page) ||
    (value.page as number) < 0 ||
    (value.page as number) > 49
  ) {
    throw invalidRequest();
  }
  return {
    operation: "discover",
    location: {
      city,
      stateCode: stateCode as string | null,
      countryCode: value.location.countryCode,
    },
    startDateTime: value.startDateTime as string,
    endDateTime: value.endDateTime as string,
    genre,
    page: value.page as number,
  };
}

export function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizedText(value: unknown, maximumLength: number): string | null {
  if (typeof value !== "string") return null;
  const normalized = value.trim().replace(/\s+/g, " ");
  if (
    normalized.length < 1 ||
    normalized.length > maximumLength ||
    containsControlCharacters(normalized) ||
    !SAFE_TEXT.test(normalized)
  ) {
    return null;
  }
  return normalized;
}

function containsControlCharacters(value: string): boolean {
  return Array.from(value).some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return codePoint <= 31 || codePoint === 127;
  });
}

function isDateTime(value: unknown): boolean {
  return typeof value === "string" &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(value) &&
    Number.isFinite(Date.parse(value));
}

function assertKeys(
  object: Record<string, unknown>,
  required: string[],
  optional: string[] = [],
): void {
  const keys = Object.keys(object);
  const allowed = new Set([...required, ...optional]);
  if (
    required.some((key) => !Object.hasOwn(object, key)) ||
    keys.some((key) => !allowed.has(key))
  ) {
    throw invalidRequest();
  }
}

function invalidRequest(): DiscoveryError {
  return new DiscoveryError("invalid_request", 400, "The discovery request is invalid.");
}
