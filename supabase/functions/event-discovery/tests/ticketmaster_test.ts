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
  assertEquals(response.events[0]?.id, "G5vYZbfixture");
  assertEquals(response.events[0]?.venue.city, "San Francisco");
  assertEquals(response.events[0]?.artists[0]?.name, "Neon Orchard");
  assertEquals(response.events[0]?.genre, "Rock");
});
