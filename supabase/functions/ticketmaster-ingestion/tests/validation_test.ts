import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { parseIngestionRequest, parseTasks } from "../validation.ts";

Deno.test("ingestion request accepts only the three bounded operations", () => {
  assertEquals(parseIngestionRequest({ operation: "run" }), {
    operation: "run",
    runId: null,
  });
  assertEquals(
    parseIngestionRequest({
      operation: "status",
      runId: "A5000000-0000-4000-8000-000000000001",
    }),
    {
      operation: "status",
      runId: "a5000000-0000-4000-8000-000000000001",
    },
  );
  assertThrows(() => parseIngestionRequest({ operation: "run", runId: crypto.randomUUID() }));
  assertThrows(() => parseIngestionRequest({ operation: "delete" }));
  assertThrows(() => parseIngestionRequest({ operation: "status", unexpected: true }));
});

Deno.test("claimed queue tasks are parsed into the fixed MVP scope", () => {
  assertEquals(
    parseTasks([{
      message_id: 42,
      read_count: 1,
      run_id: "a5000000-0000-4000-8000-000000000001",
      page: 0,
      city: "San Francisco",
      state_code: "CA",
      country_code: "US",
      coverage_starts_at: "2026-08-01T07:00:00Z",
      coverage_ends_at: "2026-08-15T07:00:00Z",
    }]),
    [{
      messageId: 42,
      readCount: 1,
      runId: "a5000000-0000-4000-8000-000000000001",
      page: 0,
      city: "San Francisco",
      stateCode: "CA",
      countryCode: "US",
      coverageStartsAt: "2026-08-01T07:00:00Z",
      coverageEndsAt: "2026-08-15T07:00:00Z",
    }],
  );
  assertThrows(() =>
    parseTasks([{
      message_id: 42,
      read_count: 1,
      run_id: "a5000000-0000-4000-8000-000000000001",
      page: 0,
      city: "Oakland",
      state_code: "CA",
      country_code: "US",
      coverage_starts_at: "2026-08-01T07:00:00Z",
      coverage_ends_at: "2026-08-15T07:00:00Z",
    }])
  );
});
