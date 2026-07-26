import assert from "node:assert/strict";
import { CatalogError, safeErrorBody } from "../errors.ts";
import { createMusicCatalogHandler, type SafeRequestEvent } from "../handler.ts";
import { MusicCatalogService } from "../service.ts";
import type {
  ArtistSearchContext,
  AuthenticatedProfile,
  CatalogBackend,
  CatalogKind,
  CatalogResult,
  JsonValue,
  MusicBrainzEventInput,
  UpsertMusicBrainzInput,
  UpstreamTransport,
} from "../types.ts";

Deno.test("handler returns the typed authentication and validation envelopes", async () => {
  const handler = createMusicCatalogHandler({ service: fixtureService() });
  const unauthenticated = await handler(jsonRequest({
    operation: "search",
    entity: "artist",
    query: "Radiohead",
  }, false));
  assert.equal(unauthenticated.status, 401);
  assert.deepEqual(await unauthenticated.json(), {
    error: {
      code: "authentication_required",
      message: "Sign in to use the tunedIn catalog.",
      retryable: false,
      retryAfterSeconds: null,
    },
  });

  const invalid = await handler(jsonRequest({
    operation: "search",
    entity: "artist",
    query: "Radiohead",
    rawName: "must not be accepted",
  }));
  assert.equal(invalid.status, 400);
  assert.equal((await invalid.json()).error.code, "invalid_request");
});

Deno.test("public gateway errors never identify the catalog provider", () => {
  const unavailable = safeErrorBody(
    new CatalogError(
      "upstream_unavailable",
      503,
      "MusicBrainz is temporarily unavailable.",
      true,
    ),
  );
  assert.equal(unavailable.error.message, "Search is temporarily unavailable.");
  assert.equal(
    JSON.stringify(unavailable).toLocaleLowerCase("en-US").includes("musicbrainz"),
    false,
  );

  const futureProviderError = safeErrorBody(
    new CatalogError("future_error", 500, "MusicBrainz returned something new.", true),
  );
  assert.equal(
    futureProviderError.error.message,
    "Search could not be completed. Please try again.",
  );
});

Deno.test("handler streams and rejects chunked oversized bodies before buffering the remainder", async () => {
  let canceled = false;
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new Uint8Array(10_000));
      controller.enqueue(new Uint8Array(10_000));
      controller.enqueue(new Uint8Array(10_000));
    },
    cancel() {
      canceled = true;
    },
  });
  const handler = createMusicCatalogHandler({ service: fixtureService() });
  const response = await handler(
    new Request("http://localhost/functions/v1/music-catalog", {
      method: "POST",
      headers: { Authorization: "Bearer fixture-token", "Content-Type": "application/json" },
      body: stream,
      // Required by the Fetch implementation for a streaming request body.
      duplex: "half",
    } as RequestInit),
  );
  assert.equal(response.status, 400);
  assert.equal((await response.json()).error.code, "invalid_request");
  assert.equal(canceled, true);
});

Deno.test("safe request events never contain queries, result text, MBIDs, tokens, or user IDs", async () => {
  const events: SafeRequestEvent[] = [];
  const handler = createMusicCatalogHandler({
    service: fixtureService(),
    log: (event) => events.push(event),
  });
  const query = "private Radiohead query";
  const authorization = "Bearer fixture-token";
  const response = await handler(
    new Request("http://localhost/functions/v1/music-catalog", {
      method: "POST",
      headers: { Authorization: authorization, "Content-Type": "application/json" },
      body: JSON.stringify({ operation: "search", entity: "artist", query }),
    }),
  );
  assert.equal(response.status, 200);
  const serialized = JSON.stringify(events);
  for (
    const forbidden of [
      query,
      "Fixture Artist",
      "11111111-1111-4111-8111-111111111111",
      authorization,
      "d1000000-0000-4000-8000-000000000001",
    ]
  ) {
    assert.equal(serialized.includes(forbidden), false);
  }
  assert.deepEqual(
    events.map(({ operation, outcome, errorCode }) => ({ operation, outcome, errorCode })),
    [{
      operation: "search",
      outcome: "success",
      errorCode: null,
    }],
  );
});

function jsonRequest(body: unknown, includeAuthorization = true): Request {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (includeAuthorization) headers.set("Authorization", "Bearer fixture-token");
  return new Request("http://localhost/functions/v1/music-catalog", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function fixtureService(): MusicCatalogService {
  return new MusicCatalogService({
    backend: new HandlerBackend(),
    upstream: new HandlerUpstream(),
  });
}

class HandlerBackend implements CatalogBackend {
  authenticate(authorization: string): Promise<AuthenticatedProfile> {
    assert.equal(authorization, "Bearer fixture-token");
    return Promise.resolve({
      id: "d1000000-0000-4000-8000-000000000001",
      authorization,
    });
  }

  searchLocal(): Promise<CatalogResult[]> {
    return Promise.resolve([]);
  }

  getArtistSearchContext(): Promise<ArtistSearchContext[]> {
    return Promise.resolve([]);
  }

  consumeSearchQuota(): Promise<void> {
    return Promise.resolve();
  }

  getCache(): Promise<JsonValue> {
    return Promise.resolve(null);
  }

  putCache(): Promise<void> {
    return Promise.resolve();
  }

  claimRequest(): Promise<boolean> {
    return Promise.resolve(true);
  }

  releaseRequest(): Promise<void> {
    return Promise.resolve();
  }

  reserveRequestSlot(): Promise<Date> {
    return Promise.resolve(new Date());
  }

  upsertMusicBrainz(_input: UpsertMusicBrainzInput): Promise<CatalogResult> {
    return Promise.resolve(fixtureResult());
  }

  upsertMusicBrainzEvent(_input: MusicBrainzEventInput): Promise<string> {
    return Promise.resolve("e1000000-0000-4000-8000-000000000001");
  }
}

class HandlerUpstream implements UpstreamTransport {
  search(
    _kind: CatalogKind,
    _query: string,
    _offset: number,
    _artistContext: ArtistSearchContext[],
  ): Promise<{ results: CatalogResult[]; hasMore: boolean }> {
    return Promise.resolve({ results: [fixtureResult()], hasMore: false });
  }

  lookup(): Promise<CatalogResult> {
    return Promise.resolve(fixtureResult());
  }

  searchEvents(
    _query: string,
    _offset: number,
    _beginDate: string | null,
    _endDate: string | null,
  ): Promise<{ results: MusicBrainzEventInput[]; hasMore: boolean }> {
    return Promise.resolve({ results: [], hasMore: false });
  }
}

function fixtureResult(): CatalogResult {
  return {
    source: "musicbrainz",
    origin: "musicbrainz",
    kind: "artist",
    catalogId: null,
    musicBrainzId: "11111111-1111-4111-8111-111111111111",
    displayName: "Fixture Artist",
    sortName: "Fixture Artist",
    disambiguation: null,
    subtitle: "Group",
    metadata: {
      artistType: "Group",
      countryCode: null,
      areaCatalogId: null,
      areaMusicBrainzId: null,
      areaName: null,
      lifeSpanBegin: null,
      lifeSpanEnd: null,
      ended: false,
    },
  };
}
