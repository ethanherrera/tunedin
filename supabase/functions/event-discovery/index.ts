import { DiscoveryBackend } from "./backend.ts";
import { DiscoveryError, safeErrorBody } from "./errors.ts";
import { createEventDiscoveryHandler } from "./handler.ts";
import { EventDiscoveryService } from "./service.ts";
import { TicketmasterClient } from "./ticketmaster.ts";

type TunedInEnvironment = "Local" | "Development" | "Staging" | "Production";

export function buildRuntimeHandler(
  environment: Record<string, string | undefined>,
): (request: Request) => Promise<Response> {
  const tunedInEnvironment = requiredEnvironment(environment.TUNEDIN_ENVIRONMENT);
  const supabaseURL = requiredURL(environment.SUPABASE_URL);
  const anonymousKey = required(environment.SUPABASE_ANON_KEY);
  const serviceRoleKey = required(environment.SUPABASE_SERVICE_ROLE_KEY);
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

  const backend = new DiscoveryBackend({
    supabaseURL,
    anonymousKey,
    serviceRoleKey,
  });
  const ticketmaster = new TicketmasterClient({ baseURL, apiKey });
  return createEventDiscoveryHandler(new EventDiscoveryService(backend, ticketmaster));
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
            "Access-Control-Allow-Origin": "*",
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
    value === "Local" || value === "Development" || value === "Staging" || value === "Production"
  ) {
    return value;
  }
  throw configurationFailure();
}

function isLocalURL(url: URL): boolean {
  return url.protocol === "http:" &&
    ["127.0.0.1", "localhost", "[::1]", "kong", "host.docker.internal"].includes(url.hostname);
}

function configurationFailure(): DiscoveryError {
  return new DiscoveryError(
    "configuration_error",
    503,
    "Ticketmaster discovery is not configured.",
    true,
  );
}
