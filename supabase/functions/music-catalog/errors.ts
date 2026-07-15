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
      message: error.message,
      retryable: error.retryable,
      retryAfterSeconds: error.retryAfterSeconds,
    },
  };
}
