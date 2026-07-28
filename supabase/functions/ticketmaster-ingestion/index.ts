import { TicketmasterClient } from "../event-discovery/ticketmaster.ts";
import { IngestionBackend } from "./backend.ts";
import { IngestionError, safeErrorBody } from "./errors.ts";
import { createTicketmasterIngestionHandler } from "./handler.ts";
import { TicketmasterIngestionService } from "./service.ts";

type TunedInEnvironment = "Local" | "Development" | "Staging" | "Production";

export function buildRuntimeHandler(
  environment: Record<string, string | undefined>,
): (request: Request) => Promise<Response> {
  const tunedInEnvironment = requiredEnvironment(environment.TUNEDIN_ENVIRONMENT);
  const supabaseURL = requiredURL(environment.SUPABASE_URL);
  const serviceRoleKey = required(environment.SUPABASE_SERVICE_ROLE_KEY);
  const operatorKey = requiredOperatorKey(
    environment.SUPABASE_SECRET_KEYS,
    environment.SUPABASE_SECRET_KEY,
    tunedInEnvironment,
  );
  const apiKey = required(environment.TICKETMASTER_DISCOVERY_API_KEY);
  const baseURL = requiredURL(
    environment.TICKETMASTER_DISCOVERY_BASE_URL ??
      "https://app.ticketmaster.com/discovery/v2/",
  );

  if (tunedInEnvironment === "Local") {
    if (!isLocalURL(supabaseURL) || !isLocalURL(baseURL)) throw configurationFailure();
  } else if (
    supabaseURL.protocol !== "https:" ||
    !supabaseURL.hostname.endsWith(".supabase.co") ||
    baseURL.href !== "https://app.ticketmaster.com/discovery/v2/"
  ) {
    throw configurationFailure();
  }

  const backend = new IngestionBackend({ supabaseURL, serviceRoleKey });
  const ticketmaster = new TicketmasterClient({ baseURL, apiKey });
  const service = new TicketmasterIngestionService(backend, ticketmaster);
  return createTicketmasterIngestionHandler(service, operatorKey);
}

if (import.meta.main) {
  let handler: (request: Request) => Promise<Response>;
  try {
    handler = buildRuntimeHandler(Deno.env.toObject());
  } catch {
    const error = configurationFailure();
    handler = () =>
      Promise.resolve(
        new Response(JSON.stringify(safeErrorBody(error)), {
          status: error.status,
          headers: {
            "Cache-Control": "no-store",
            "Content-Type": "application/json; charset=utf-8",
          },
        }),
      );
  }
  Deno.serve(handler);
}

function required(value: string | undefined): string {
  if (value === undefined || value.length < 1 || value.length > 16_384) {
    throw configurationFailure();
  }
  return value;
}

function requiredURL(value: string | undefined): URL {
  try {
    const url = new URL(required(value));
    if (url.username !== "" || url.password !== "" || url.search !== "" || url.hash !== "") {
      throw configurationFailure();
    }
    return url;
  } catch {
    throw configurationFailure();
  }
}

function requiredEnvironment(value: string | undefined): TunedInEnvironment {
  if (
    value === "Local" || value === "Development" || value === "Staging" ||
    value === "Production"
  ) {
    return value;
  }
  throw configurationFailure();
}

function requiredOperatorKey(
  encodedKeys: string | undefined,
  localKey: string | undefined,
  environment: TunedInEnvironment,
): string {
  let candidate: unknown;
  try {
    const parsed = JSON.parse(required(encodedKeys));
    if (
      parsed !== null &&
      typeof parsed === "object" &&
      !Array.isArray(parsed)
    ) {
      candidate = (parsed as Record<string, unknown>).default;
    }
  } catch {
    if (environment === "Local") candidate = localKey;
  }
  if (candidate === undefined && environment === "Local") candidate = localKey;
  if (
    typeof candidate !== "string" ||
    candidate.length > 512 ||
    !/^sb_secret_[A-Za-z0-9_-]+$/.test(candidate)
  ) {
    throw configurationFailure();
  }
  return candidate;
}

function isLocalURL(url: URL): boolean {
  return url.protocol === "http:" &&
    ["127.0.0.1", "localhost", "[::1]", "kong", "host.docker.internal"].includes(url.hostname);
}

function configurationFailure(): IngestionError {
  return new IngestionError(
    "configuration_error",
    503,
    "Ticketmaster ingestion is not configured.",
    true,
  );
}
