import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { buildRuntimeHandler } from "../index.ts";

Deno.test("hosted worker requires the default secret API key", () => {
  const handler = buildRuntimeHandler({
    TUNEDIN_ENVIRONMENT: "Development",
    SUPABASE_URL: "https://abcdefghijklmnopqrst.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "legacy-internal-database-key",
    SUPABASE_SECRET_KEYS: '{"default":"sb_secret_fixture-operator-key"}',
    TICKETMASTER_DISCOVERY_API_KEY: "fixture-ticketmaster-key",
  });
  assertEquals(typeof handler, "function");

  assertThrows(() =>
    buildRuntimeHandler({
      TUNEDIN_ENVIRONMENT: "Development",
      SUPABASE_URL: "https://abcdefghijklmnopqrst.supabase.co",
      SUPABASE_SERVICE_ROLE_KEY: "legacy-internal-database-key",
      SUPABASE_SECRET_KEYS: '{"default":"legacy-service-role-key"}',
      TICKETMASTER_DISCOVERY_API_KEY: "fixture-ticketmaster-key",
    })
  );
});

Deno.test("Local accepts only the explicit fixture secret-key fallback", () => {
  const handler = buildRuntimeHandler({
    TUNEDIN_ENVIRONMENT: "Local",
    SUPABASE_URL: "http://kong:8000",
    SUPABASE_SERVICE_ROLE_KEY: "fixture-internal-database-key",
    SUPABASE_SECRET_KEY: "sb_secret_fixture-local-operator",
    TICKETMASTER_DISCOVERY_API_KEY: "fixture-ticketmaster-key",
    TICKETMASTER_DISCOVERY_BASE_URL: "http://host.docker.internal:8080",
  });
  assertEquals(typeof handler, "function");
});
