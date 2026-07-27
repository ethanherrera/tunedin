import { assertEquals } from "jsr:@std/assert@1";
import { createEventDiscoveryHandler } from "../handler.ts";
import { EventDiscoveryService } from "../service.ts";

const handler = createEventDiscoveryHandler(null as unknown as EventDiscoveryService);

Deno.test("event discovery handler rejects unauthenticated requests before service work", async () => {
  const response = await handler(jsonRequest("{}"));
  assertEquals(response.status, 401);
  assertEquals((await response.json()).error.code, "authentication_required");
});

Deno.test("event discovery handler returns a safe invalid JSON response", async () => {
  const response = await handler(jsonRequest("{", "Bearer fixture"));
  assertEquals(response.status, 400);
  assertEquals((await response.json()).error.code, "invalid_request");
});

Deno.test("event discovery handler requires JSON and advertises supported methods", async () => {
  const invalidContentType = await handler(
    new Request("http://localhost/functions/v1/event-discovery", {
      method: "POST",
      headers: { authorization: "Bearer fixture", "content-type": "text/plain" },
      body: "{}",
    }),
  );
  assertEquals(invalidContentType.status, 400);

  const invalidMethod = await handler(
    new Request("http://localhost/functions/v1/event-discovery", { method: "GET" }),
  );
  assertEquals(invalidMethod.status, 405);
  assertEquals(invalidMethod.headers.get("allow"), "POST, OPTIONS");
});

function jsonRequest(body: string, authorization?: string): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization !== undefined) headers.set("authorization", authorization);
  return new Request("http://localhost/functions/v1/event-discovery", {
    method: "POST",
    headers,
    body,
  });
}
