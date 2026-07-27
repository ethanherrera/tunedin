import { assertEquals } from "jsr:@std/assert@1";
import { DiscoveryBackend } from "../backend.ts";

Deno.test("Ticketmaster backend accepts successful void RPC responses", async () => {
  const requests: Request[] = [];
  const backend = new DiscoveryBackend({
    supabaseURL: new URL("https://fixture.supabase.co/"),
    anonymousKey: "publishable-fixture",
    serviceRoleKey: "service-role-fixture",
    fetch: (input, init) => {
      requests.push(new Request(input, init));
      return Promise.resolve(new Response(null, { status: 204 }));
    },
  });

  await backend.consumeQuota("10000000-0000-4000-8000-000000000001");
  assertEquals(requests.length, 1);
  assertEquals(
    new URL(requests[0].url).pathname,
    "/rest/v1/rpc/consume_ticketmaster_discovery_quota",
  );
});
