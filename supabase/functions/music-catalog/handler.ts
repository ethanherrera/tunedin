import { CatalogError, safeErrorBody, toSafeError } from "./errors.ts";
import { MusicCatalogService } from "./service.ts";
import { parseCatalogRequest } from "./validation.ts";

const MAX_REQUEST_BYTES = 16_384;
const JSON_HEADERS = {
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Origin": "*",
  "Cache-Control": "no-store",
  "Content-Type": "application/json; charset=utf-8",
};

export interface SafeRequestEvent {
  event: "music_catalog_request";
  operation: "search" | "resolve" | "unknown";
  outcome: "success" | "failure";
  errorCode: string | null;
  durationMs: number;
}

interface HandlerOptions {
  service: MusicCatalogService;
  log?: (event: SafeRequestEvent) => void;
  now?: () => number;
}

export function createMusicCatalogHandler(
  options: HandlerOptions,
): (request: Request) => Promise<Response> {
  const now = options.now ?? performance.now.bind(performance);
  const log = options.log ?? (() => {});

  return async (request: Request): Promise<Response> => {
    const startedAt = now();
    let operation: SafeRequestEvent["operation"] = "unknown";
    try {
      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: JSON_HEADERS });
      }
      if (request.method !== "POST") {
        throw new CatalogError(
          "method_not_allowed",
          405,
          "Use POST for catalog requests.",
        );
      }
      const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
      if (!contentType.startsWith("application/json")) {
        throw new CatalogError(
          "invalid_request",
          400,
          "Catalog requests must use JSON.",
        );
      }
      const authorization = request.headers.get("authorization") ?? "";
      if (authorization === "") {
        throw new CatalogError(
          "authentication_required",
          401,
          "Sign in to use the tunedIn catalog.",
        );
      }

      const body = await readBoundedRequestJson(request);
      const catalogRequest = parseCatalogRequest(body);
      operation = catalogRequest.operation;
      const response = catalogRequest.operation === "search"
        ? await options.service.search(catalogRequest, authorization)
        : await options.service.resolve(catalogRequest, authorization);
      log({
        event: "music_catalog_request",
        operation,
        outcome: "success",
        errorCode: null,
        durationMs: Math.max(0, Math.round(now() - startedAt)),
      });
      return new Response(JSON.stringify(response), { status: 200, headers: JSON_HEADERS });
    } catch (unknownError) {
      const error = toSafeError(unknownError);
      log({
        event: "music_catalog_request",
        operation,
        outcome: "failure",
        errorCode: error.code,
        durationMs: Math.max(0, Math.round(now() - startedAt)),
      });
      const headers = new Headers(JSON_HEADERS);
      if (error.retryAfterSeconds !== null) {
        headers.set("Retry-After", String(error.retryAfterSeconds));
      }
      if (error.status === 405) headers.set("Allow", "POST, OPTIONS");
      return new Response(JSON.stringify(safeErrorBody(error)), {
        status: error.status,
        headers,
      });
    }
  };
}

async function readBoundedRequestJson(request: Request): Promise<unknown> {
  const declaredLength = request.headers.get("content-length");
  if (declaredLength !== null && Number(declaredLength) > MAX_REQUEST_BYTES) {
    throw new CatalogError("invalid_request", 400, "The catalog request is too large.");
  }
  const reader = request.body?.getReader();
  if (reader === undefined) {
    throw new CatalogError("invalid_request", 400, "The catalog request is invalid.");
  }
  const chunks: Uint8Array[] = [];
  let byteCount = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    byteCount += value.byteLength;
    if (byteCount > MAX_REQUEST_BYTES) {
      await reader.cancel();
      throw new CatalogError("invalid_request", 400, "The catalog request is too large.");
    }
    chunks.push(value);
  }
  if (byteCount === 0) {
    throw new CatalogError("invalid_request", 400, "The catalog request is invalid.");
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
    throw new CatalogError("invalid_request", 400, "The catalog request is invalid.");
  }
}
