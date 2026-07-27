import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { parseDiscoveryRequest } from "../validation.ts";

Deno.test("discover request accepts bounded location, dates, genre, and page", () => {
  const request = parseDiscoveryRequest({
    operation: "discover",
    location: { city: "San Francisco", stateCode: "CA", countryCode: "US" },
    startDateTime: "2026-08-01T00:00:00Z",
    endDateTime: "2026-08-08T00:00:00Z",
    genre: "R&B",
    page: 0,
  });
  assertEquals(request.operation, "discover");
  if (request.operation !== "discover") throw new Error("Expected discover request.");
  assertEquals(request.genre, "R&B");
});

Deno.test("discover request treats omitted Swift optional fields as null", () => {
  const request = parseDiscoveryRequest({
    operation: "discover",
    location: { city: "Paris", countryCode: "FR" },
    startDateTime: "2026-08-01T00:00:00Z",
    endDateTime: "2026-08-08T00:00:00Z",
    page: 0,
  });
  assertEquals(request.operation, "discover");
  if (request.operation !== "discover") throw new Error("Expected discover request.");
  assertEquals(request.genre, null);
  assertEquals(request.location.stateCode, null);
});

Deno.test("resolve request rejects provider IDs with path syntax", () => {
  assertThrows(() =>
    parseDiscoveryRequest({
      operation: "resolve",
      eventId: "../event",
    })
  );
});
