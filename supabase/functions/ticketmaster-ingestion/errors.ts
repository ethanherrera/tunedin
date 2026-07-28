export class IngestionError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    message: string,
    readonly retryable = false,
  ) {
    super(message);
  }
}

export function safeError(error: unknown): IngestionError {
  if (error instanceof IngestionError) return error;
  return new IngestionError(
    "internal_error",
    500,
    "Ticketmaster ingestion could not be completed.",
    true,
  );
}

export function safeErrorBody(error: IngestionError): {
  error: { code: string; message: string; retryable: boolean };
} {
  return {
    error: {
      code: error.code,
      message: error.message,
      retryable: error.retryable,
    },
  };
}
