import { assertEquals } from "jsr:@std/assert@1";
import { DiscoveryError } from "../../event-discovery/errors.ts";
import type { DiscoverRequest, DiscoveryCandidate } from "../../event-discovery/types.ts";
import { createTicketmasterIngestionHandler } from "../handler.ts";
import {
  type IngestionBackendPort,
  TicketmasterIngestionService,
  type TicketmasterPort,
} from "../service.ts";
import type { CompletionInput, IngestionTask, JsonValue } from "../types.ts";

const RUN_ID = "a5000000-0000-4000-8000-000000000001";
const TASK: IngestionTask = {
  messageId: 42,
  readCount: 1,
  runId: RUN_ID,
  page: 0,
  city: "San Francisco",
  stateCode: "CA",
  countryCode: "US",
  coverageStartsAt: "2026-08-01T07:00:00Z",
  coverageEndsAt: "2026-08-15T07:00:00Z",
};
const EVENT: DiscoveryCandidate = {
  id: "G5vYZbfixture",
  name: "Neon Orchard",
  localDate: "2026-08-01",
  localTime: "20:00:00",
  dateTime: "2026-08-02T03:00:00Z",
  timeZone: "America/Los_Angeles",
  status: "active",
  venue: {
    id: "KovZfixtureVenue",
    name: "Fixture Hall",
    url: "https://www.ticketmaster.com/venue/KovZfixtureVenue",
    address: "1 Fixture Way",
    city: "San Francisco",
    stateCode: "CA",
    countryCode: "US",
    latitude: "37.78",
    longitude: "-122.42",
  },
  artists: [{
    id: "K8vZfixtureArtist",
    name: "Neon Orchard",
    url: "https://www.ticketmaster.com/artist/K8vZfixtureArtist",
  }],
  genre: "Rock",
  imageURL: "https://example.com/ignored.jpg",
  ticketURL: "https://www.ticketmaster.com/event/G5vYZbfixture",
};

class FakeBackend implements IngestionBackendPort {
  tasks: IngestionTask[] = [TASK];
  completions: CompletionInput[] = [];
  failures: Array<{ messageId: number; code: string; retryable: boolean }> = [];
  reservations = 0;

  startRun(): Promise<string> {
    return Promise.resolve(RUN_ID);
  }

  claimTasks(): Promise<IngestionTask[]> {
    return Promise.resolve(this.tasks.splice(0, 1));
  }

  completePage(input: CompletionInput): Promise<void> {
    this.completions.push(input);
    return Promise.resolve();
  }

  failTask(messageId: number, code: string, retryable: boolean): Promise<void> {
    this.failures.push({ messageId, code, retryable });
    return Promise.resolve();
  }

  status(runId: string | null): Promise<JsonValue> {
    return Promise.resolve({ run_id: runId });
  }

  reserveUpstreamSlot(): Promise<void> {
    this.reservations += 1;
    return Promise.resolve();
  }
}

class FakeTicketmaster implements TicketmasterPort {
  requests: DiscoverRequest[] = [];

  discover(request: DiscoverRequest) {
    this.requests.push(request);
    return Promise.resolve({
      events: [EVENT],
      rawEventCount: 1,
      rejectedEventCount: 0,
      totalElements: 1,
      totalPages: 1,
      hasMore: false,
      rejectionReasons: {
        event_shape: 0,
        event_dates: 0,
        venue: 0,
        lineup: 0,
        source_url: 0,
      },
    });
  }
}

Deno.test("run starts, claims, paces, and completes a bounded ingestion page", async () => {
  const backend = new FakeBackend();
  const ticketmaster = new FakeTicketmaster();
  const service = new TicketmasterIngestionService(backend, ticketmaster, () => 1_000);

  const response = await service.execute("run", null);

  assertEquals(response, {
    operation: "run",
    runId: RUN_ID,
    processedPages: 1,
    rejectionReasons: {
      event_shape: 0,
      event_dates: 0,
      venue: 0,
      lineup: 0,
      source_url: 0,
    },
    status: { run_id: RUN_ID },
  });
  assertEquals(backend.reservations, 1);
  assertEquals(backend.completions.length, 1);
  assertEquals(ticketmaster.requests[0], {
    operation: "discover",
    location: { city: "San Francisco", stateCode: "CA", countryCode: "US" },
    startDateTime: "2026-08-01T07:00:00Z",
    endDateTime: "2026-08-15T07:00:00Z",
    genre: null,
    page: 0,
  });
});

Deno.test("upstream failures are safely classified for queue retry", async () => {
  const backend = new FakeBackend();
  const ticketmaster: TicketmasterPort = {
    discover: () =>
      Promise.reject(
        new DiscoveryError(
          "upstream_rate_limited",
          503,
          "provider detail must not escape",
          true,
        ),
      ),
  };
  const service = new TicketmasterIngestionService(backend, ticketmaster, () => 1_000);

  const response = await service.execute("resume", null);

  assertEquals(response.processedPages, 0);
  assertEquals(response.rejectionReasons, {
    event_shape: 0,
    event_dates: 0,
    venue: 0,
    lineup: 0,
    source_url: 0,
  });
  assertEquals(backend.failures, [{
    messageId: 42,
    code: "upstream_rate_limited",
    retryable: true,
  }]);
});

Deno.test("handler requires the exact operator API key", async () => {
  const service = new TicketmasterIngestionService(
    new FakeBackend(),
    new FakeTicketmaster(),
    () => 1_000,
  );
  const handler = createTicketmasterIngestionHandler(service, "operator-secret");

  const unauthorized = await handler(
    new Request("https://example.test/ticketmaster-ingestion", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: '{"operation":"status"}',
    }),
  );
  assertEquals(unauthorized.status, 401);

  const authorized = await handler(
    new Request("https://example.test/ticketmaster-ingestion", {
      method: "POST",
      headers: {
        apikey: "operator-secret",
        "Content-Type": "application/json",
      },
      body: '{"operation":"status"}',
    }),
  );
  assertEquals(authorized.status, 200);
});
