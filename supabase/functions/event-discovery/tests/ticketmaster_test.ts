import { assertEquals } from "jsr:@std/assert@1";
import { TicketmasterClient } from "../ticketmaster.ts";

Deno.test("Ticketmaster discovery sends source-safe filters and decodes music events", async () => {
  const fixture = await Deno.readTextFile(
    new URL("../fixtures/events.json", import.meta.url),
  );
  let requestedURL = "";
  const client = new TicketmasterClient({
    baseURL: new URL("https://app.ticketmaster.com/discovery/v2/"),
    apiKey: "fixture-secret",
    fetch: (input) => {
      requestedURL = String(input);
      return Promise.resolve(
        new Response(fixture, {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      );
    },
  });

  const response = await client.discover({
    operation: "discover",
    location: { city: "San Francisco", stateCode: "CA", countryCode: "US" },
    startDateTime: "2026-08-01T00:00:00Z",
    endDateTime: "2026-08-08T00:00:00Z",
    genre: "Rock",
    page: 0,
  });

  const query = new URL(requestedURL).searchParams;
  assertEquals(query.get("source"), "ticketmaster");
  assertEquals(query.get("segmentName"), "Music");
  assertEquals(query.get("apikey"), "fixture-secret");
  assertEquals(query.get("sort"), "date,asc");
  assertEquals(response.hasMore, false);
  assertEquals(response.pageNumber, 0);
  assertEquals(response.pageSize, 20);
  assertEquals(response.totalElements, 1);
  assertEquals(response.totalPages, 1);
  assertEquals(response.rawEventCount, 1);
  assertEquals(response.rejectedEventCount, 0);
  assertEquals(response.rejections, []);
  assertEquals(response.rejectionReasons, {
    event_shape: 0,
    event_dates: 0,
    venue: 0,
    lineup: 0,
    source_url: 0,
  });
  assertEquals(response.events[0]?.id, "G5vYZbfixture");
  assertEquals(response.events[0]?.venue.city, "San Francisco");
  assertEquals(response.events[0]?.artists[0]?.name, "Neon Orchard");
  assertEquals(response.events[0]?.genre, "Rock");
});

Deno.test("Ticketmaster discovery reports bounded rejection reasons without payload data", async () => {
  const fixture = JSON.parse(
    await Deno.readTextFile(new URL("../fixtures/events.json", import.meta.url)),
  );
  delete fixture._embedded.events[0]._embedded.attractions;
  const client = new TicketmasterClient({
    baseURL: new URL("https://app.ticketmaster.com/discovery/v2/"),
    apiKey: "fixture-secret",
    fetch: () =>
      Promise.resolve(
        new Response(JSON.stringify(fixture), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        }),
      ),
  });

  const response = await client.discover({
    operation: "discover",
    location: { city: "San Francisco", stateCode: "CA", countryCode: "US" },
    startDateTime: "2026-08-01T00:00:00Z",
    endDateTime: "2026-08-08T00:00:00Z",
    genre: null,
    page: 0,
  });

  assertEquals(response.events, []);
  assertEquals(response.rejectedEventCount, 1);
  assertEquals(response.rejections, [{
    rawPosition: 0,
    externalEventId: "G5vYZbfixture",
    eventName: "Neon Orchard Live",
    localDate: "2026-08-01",
    venueName: "The Fillmore",
    reason: "lineup",
    code: "attractions_missing",
    attractionCount: null,
    invalidAttractions: {
      attractionShape: 0,
      artistId: 0,
      artistName: 0,
      artistURL: 0,
    },
  }]);
  assertEquals(response.rejectionReasons, {
    event_shape: 0,
    event_dates: 0,
    venue: 0,
    lineup: 1,
    source_url: 0,
  });
});
