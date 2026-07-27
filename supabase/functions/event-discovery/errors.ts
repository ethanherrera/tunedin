export class DiscoveryError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    message: string,
    readonly retryable = false,
    readonly retryAfterSeconds: number | null = null,
  ) {
    super(message);
  }
}

export function safeError(error: unknown): DiscoveryError {
  if (error instanceof DiscoveryError) return error;
  return new DiscoveryError(
    "internal_error",
    500,
    "Event discovery could not be completed.",
    true,
  );
}

export function safeErrorBody(error: DiscoveryError): object {
  return {
    error: {
      code: error.code,
      message: error.message,
      retryable: error.retryable,
      retryAfterSeconds: error.retryAfterSeconds,
    },
  };
}
