import type { SafeErrorBody } from "./types.ts";

export class CatalogError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    message: string,
    readonly retryable = false,
    readonly retryAfterSeconds: number | null = null,
  ) {
    super(message);
    this.name = "CatalogError";
  }
}

export function invalidRequest(message = "The catalog request is invalid."): CatalogError {
  return new CatalogError("invalid_request", 400, message);
}

export function toSafeError(error: unknown): CatalogError {
  if (error instanceof CatalogError) {
    return error;
  }
  return new CatalogError(
    "internal_error",
    500,
    "The catalog request could not be completed.",
    true,
  );
}

export function safeErrorBody(error: CatalogError): SafeErrorBody {
  return {
    error: {
      code: error.code,
      message: publicErrorMessage(error),
      retryable: error.retryable,
      retryAfterSeconds: error.retryAfterSeconds,
    },
  };
}

function publicErrorMessage(error: CatalogError): string {
  switch (error.code) {
    case "upstream_timeout":
      return "Search took too long. Please try again.";
    case "upstream_rate_limited":
    case "queue_timeout":
      return "Search is busy. Please try again shortly.";
    case "upstream_unavailable":
      return "Search is temporarily unavailable.";
    case "upstream_invalid_response":
      return "Search returned an unexpected response. Please try again.";
    default:
      return error.message.toLocaleLowerCase("en-US").includes("musicbrainz")
        ? "Search could not be completed. Please try again."
        : error.message;
  }
}
