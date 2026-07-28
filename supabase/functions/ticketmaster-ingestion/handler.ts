import { IngestionError, safeError, safeErrorBody } from "./errors.ts";
import { TicketmasterIngestionService } from "./service.ts";
import { parseIngestionRequest } from "./validation.ts";

const MAX_REQUEST_BYTES = 4_096;
const HEADERS = {
  "Cache-Control": "no-store",
  "Content-Type": "application/json; charset=utf-8",
};

export function createTicketmasterIngestionHandler(
  service: TicketmasterIngestionService,
  serviceRoleKey: string,
): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    try {
      if (request.method !== "POST") {
        throw new IngestionError("method_not_allowed", 405, "Use POST for ingestion requests.");
      }
      if (request.headers.get("authorization") !== `Bearer ${serviceRoleKey}`) {
        throw new IngestionError("authentication_required", 401, "Server authorization required.");
      }
      const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
      if (!contentType.startsWith("application/json")) {
        throw new IngestionError("invalid_request", 400, "Ingestion requests must use JSON.");
      }
      const parsed = parseIngestionRequest(await readBoundedRequestJson(request));
      const response = await service.execute(parsed.operation, parsed.runId);
      return new Response(JSON.stringify(response), { status: 200, headers: HEADERS });
    } catch (unknownError) {
      const error = safeError(unknownError);
      const headers = new Headers(HEADERS);
      if (error.status === 405) headers.set("Allow", "POST");
      return new Response(JSON.stringify(safeErrorBody(error)), {
        status: error.status,
        headers,
      });
    }
  };
}

async function readBoundedRequestJson(request: Request): Promise<unknown> {
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (declaredLength > MAX_REQUEST_BYTES) throw invalidRequest();
  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > MAX_REQUEST_BYTES || text.length === 0) {
    throw invalidRequest();
  }
  try {
    return JSON.parse(text);
  } catch {
    throw invalidRequest();
  }
}

function invalidRequest(): IngestionError {
  return new IngestionError("invalid_request", 400, "The ingestion request is invalid.");
}
