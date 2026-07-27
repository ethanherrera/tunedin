import { DiscoveryError, safeError, safeErrorBody } from "./errors.ts";
import { EventDiscoveryService } from "./service.ts";
import { parseDiscoveryRequest } from "./validation.ts";

const MAX_REQUEST_BYTES = 16_384;
const HEADERS = {
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Origin": "*",
  "Cache-Control": "no-store",
  "Content-Type": "application/json; charset=utf-8",
};

export function createEventDiscoveryHandler(
  service: EventDiscoveryService,
): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    try {
      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: HEADERS });
      }
      if (request.method !== "POST") {
        throw new DiscoveryError(
          "method_not_allowed",
          405,
          "Use POST for discovery requests.",
        );
      }
      const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
      if (!contentType.startsWith("application/json")) {
        throw new DiscoveryError(
          "invalid_request",
          400,
          "Discovery requests must use JSON.",
        );
      }
      const authorization = request.headers.get("authorization") ?? "";
      if (authorization === "") {
        throw new DiscoveryError(
          "authentication_required",
          401,
          "Sign in to discover concerts.",
        );
      }
      const parsed = parseDiscoveryRequest(await readBoundedRequestJson(request));
      const response = parsed.operation === "discover"
        ? await service.discover(parsed, authorization)
        : await service.resolve(parsed, authorization);
      return new Response(JSON.stringify(response), { status: 200, headers: HEADERS });
    } catch (unknownError) {
      const error = safeError(unknownError);
      const headers = new Headers(HEADERS);
      if (error.retryAfterSeconds !== null) {
        headers.set("Retry-After", String(error.retryAfterSeconds));
      }
      if (error.status === 405) headers.set("Allow", "POST, OPTIONS");
      return new Response(JSON.stringify(safeErrorBody(error)), { status: error.status, headers });
    }
  };
}

async function readBoundedRequestJson(request: Request): Promise<unknown> {
  const declaredLength = request.headers.get("content-length");
  if (declaredLength !== null && Number(declaredLength) > MAX_REQUEST_BYTES) {
    throw invalidRequest("The discovery request is too large.");
  }
  const reader = request.body?.getReader();
  if (reader === undefined) {
    throw invalidRequest("The discovery request is invalid.");
  }
  const chunks: Uint8Array[] = [];
  let byteCount = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    byteCount += value.byteLength;
    if (byteCount > MAX_REQUEST_BYTES) {
      await reader.cancel();
      throw invalidRequest("The discovery request is too large.");
    }
    chunks.push(value);
  }
  if (byteCount === 0) {
    throw invalidRequest("The discovery request is invalid.");
  }
  const bytes = new Uint8Array(byteCount);
  let cursor = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, cursor);
    cursor += chunk.byteLength;
  }
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    throw invalidRequest("The discovery request is invalid.");
  }
}

function invalidRequest(message: string): DiscoveryError {
  return new DiscoveryError("invalid_request", 400, message);
}
