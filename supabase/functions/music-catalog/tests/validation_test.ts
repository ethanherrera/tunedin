import assert from "node:assert/strict";
import { CatalogError } from "../errors.ts";
import { decodeCatalogResult } from "../result_validation.ts";
import { buildLuceneQuery, escapeLucene, parseCatalogRequest } from "../validation.ts";

Deno.test("search request normalizes input and applies fixed defaults", () => {
  assert.deepEqual(
    parseCatalogRequest({
      operation: "search",
      entity: "artist",
      query: "  Radiohead  ",
    }),
    {
      operation: "search",
      entity: "artist",
      query: "Radiohead",
      offset: 0,
      artistContextIds: [],
    },
  );
});

Deno.test("search rejects removed concert context fields", () => {
  assertCatalogError(
    () =>
      parseCatalogRequest({
        operation: "search",
        entity: "song",
        query: "Creep",
        concertContextId: "d2000000-0000-0000-0000-000000000001",
      }),
    "invalid_request",
  );
});

Deno.test("event search accepts an optional calendar-date range and rejects invalid bounds", () => {
  assert.deepEqual(
    parseCatalogRequest({
      operation: "search_events",
      query: "Eternal Sunshine Oakland",
      offset: 20,
      beginDate: "2026-08-15",
      endDate: "2026-08-31",
    }),
    {
      operation: "search_events",
      query: "Eternal Sunshine Oakland",
      offset: 20,
      beginDate: "2026-08-15",
      endDate: "2026-08-31",
    },
  );
  assertCatalogError(
    () =>
      parseCatalogRequest({
        operation: "search_events",
        query: "Fixture concert",
        beginDate: "2026-02-30",
      }),
    "invalid_request",
  );
  assertCatalogError(
    () =>
      parseCatalogRequest({
        operation: "search_events",
        query: "Fixture concert",
        beginDate: "2026-08-31",
        endDate: "2026-08-15",
      }),
    "invalid_request",
  );
});

Deno.test("resolve rejects non-MusicBrainz UUIDs", () => {
  assertCatalogError(
    () =>
      parseCatalogRequest({
        operation: "resolve",
        entity: "song",
        musicBrainzId: "00000000-0000-0000-0000-000000000000",
      }),
    "invalid_request",
  );
});

Deno.test("search request rejects unknown fields, short queries, and misplaced artist context", () => {
  assertCatalogError(
    () =>
      parseCatalogRequest({
        operation: "search",
        entity: "artist",
        query: "ok",
        limit: 99,
      }),
    "invalid_request",
  );
  assertCatalogError(
    () =>
      parseCatalogRequest({
        operation: "search",
        entity: "artist",
        query: "a",
      }),
    "invalid_request",
  );
  assertCatalogError(
    () =>
      parseCatalogRequest({
        operation: "search",
        entity: "place",
        query: "Fillmore",
        artistContextIds: ["11111111-1111-4111-8111-111111111111"],
      }),
    "invalid_request",
  );
});

Deno.test("resolve accepts only allow-listed kinds and UUID MBIDs", () => {
  assert.deepEqual(
    parseCatalogRequest({
      operation: "resolve",
      entity: "song",
      musicBrainzId: "66666666-6666-4666-8666-666666666666",
    }),
    {
      operation: "resolve",
      entity: "song",
      musicBrainzId: "66666666-6666-4666-8666-666666666666",
    },
  );
  assertCatalogError(
    () =>
      parseCatalogRequest({
        operation: "resolve",
        entity: "event",
        musicBrainzId: "66666666-6666-4666-8666-666666666666",
      }),
    "invalid_request",
  );
});

Deno.test("stored tunedIn IDs accept PostgreSQL UUID bits while MBIDs remain RFC-shaped", () => {
  const storedArea = {
    source: "tunedin",
    origin: "tunedin_custom",
    kind: "area",
    catalogId: "d3000000-0000-0000-0000-000000000101",
    musicBrainzId: null,
    displayName: "Fixture Area",
    sortName: "Fixture Area",
    disambiguation: null,
    subtitle: null,
    metadata: {
      areaType: null,
      countryCode: "US",
      subdivisionCode: null,
      parentAreaCatalogId: null,
      parentMusicBrainzId: null,
      parentName: null,
    },
  };
  assert.equal(decodeCatalogResult(storedArea).catalogId, storedArea.catalogId);
  assert.throws(
    () =>
      decodeCatalogResult({
        ...storedArea,
        source: "musicbrainz",
        origin: "musicbrainz",
        catalogId: null,
        musicBrainzId: "00000000-0000-0000-0000-000000000000",
      }),
    (error) => error instanceof CatalogError && error.code === "upstream_invalid_response",
  );
});

Deno.test("Lucene characters are escaped and the client cannot inject a field query", () => {
  assert.equal(
    escapeLucene('AC/DC + artist:(other) && "x"'),
    String.raw`AC\/DC \+ artist\:\(other\) \&\& \"x\"`,
  );
  assert.equal(
    buildLuceneQuery("artist", 'AC/DC + artist:(other) && "x"'),
    String.raw`artist:"AC\/DC \+ artist\:\(other\) \&\& \"x\""`,
  );
  assert.equal(
    buildLuceneQuery("tour", "In Rainbows"),
    'series:"In Rainbows" AND type:"Tour"',
  );
  assert.equal(
    buildLuceneQuery("song", "Creep", [{
      catalogId: "e1000000-0000-4000-8000-000000000001",
      musicBrainzId: "a74b1b7f-71a5-4011-9441-d0b5e4122711",
      name: "Radiohead",
    }]),
    'recording:"Creep" AND (arid:a74b1b7f-71a5-4011-9441-d0b5e4122711)',
  );
});

function assertCatalogError(action: () => unknown, code: string): void {
  assert.throws(
    action,
    (error) => error instanceof CatalogError && error.code === code,
  );
}
