import { SupabaseCatalogBackend } from "./backend.ts";
import { CatalogError, safeErrorBody } from "./errors.ts";
import { createMusicCatalogHandler } from "./handler.ts";
import { MusicBrainzClient } from "./musicbrainz.ts";
import { MusicCatalogService } from "./service.ts";

type TunedInEnvironment = "Local" | "Development" | "Staging" | "Production";

interface RuntimeConfiguration {
  environment: TunedInEnvironment;
  supabaseUrl: URL;
  anonymousKey: string;
  serviceRoleKey: string;
  musicBrainzBaseUrl: URL;
  musicBrainzUserAgent: string;
}

export function runtimeConfiguration(
  environment: Record<string, string | undefined>,
): RuntimeConfiguration {
  const tunedInEnvironment = environment.TUNEDIN_ENVIRONMENT;
  if (!isTunedInEnvironment(tunedInEnvironment)) throw configurationFailure();

  const supabaseUrl = requiredUrl(environment.SUPABASE_URL);
  const anonymousKey = requiredValue(environment.SUPABASE_ANON_KEY);
  const serviceRoleKey = requiredValue(environment.SUPABASE_SERVICE_ROLE_KEY);
  const configuredBaseUrl = environment.MUSICBRAINZ_BASE_URL ?? "https://musicbrainz.org/ws/2/";
  const musicBrainzBaseUrl = requiredUrl(configuredBaseUrl);
  const musicBrainzUserAgent = environment.MUSICBRAINZ_USER_AGENT ??
    "tunedIn/local (mailto:fixture-only@tunedin.invalid)";

  if (tunedInEnvironment === "Local") {
    if (!isLocalSupabaseUrl(supabaseUrl) || !isLocalMusicBrainzUrl(musicBrainzBaseUrl)) {
      throw configurationFailure();
    }
  } else {
    if (
      supabaseUrl.protocol !== "https:" || !supabaseUrl.hostname.endsWith(".supabase.co") ||
      supabaseUrl.pathname !== "/" || supabaseUrl.search !== "" || supabaseUrl.hash !== ""
    ) {
      throw configurationFailure();
    }
    if (musicBrainzBaseUrl.href !== "https://musicbrainz.org/ws/2/") {
      throw configurationFailure();
    }
    if (!isContactableUserAgent(musicBrainzUserAgent)) throw configurationFailure();
  }

  return {
    environment: tunedInEnvironment,
    supabaseUrl,
    anonymousKey,
    serviceRoleKey,
    musicBrainzBaseUrl,
    musicBrainzUserAgent,
  };
}

export function buildRuntimeHandler(
  environment: Record<string, string | undefined>,
): (request: Request) => Promise<Response> {
  const configuration = runtimeConfiguration(environment);
  const backend = new SupabaseCatalogBackend({
    supabaseUrl: configuration.supabaseUrl,
    anonymousKey: configuration.anonymousKey,
    serviceRoleKey: configuration.serviceRoleKey,
  });
  const serviceReference: { current?: MusicCatalogService } = {};
  const upstream = new MusicBrainzClient({
    baseUrl: configuration.musicBrainzBaseUrl,
    userAgent: configuration.musicBrainzUserAgent,
    beforeRedirect: () => {
      if (serviceReference.current === undefined) throw configurationFailure();
      return serviceReference.current.waitForAdditionalUpstreamSlot();
    },
  });
  const service = new MusicCatalogService({ backend, upstream });
  serviceReference.current = service;
  return createMusicCatalogHandler({ service });
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

function requiredValue(value: string | undefined): string {
  if (value === undefined || value.length === 0 || value.length > 16_384) {
    throw configurationFailure();
  }
  return value;
}

function requiredUrl(value: string | undefined): URL {
  if (value === undefined) throw configurationFailure();
  try {
    const url = new URL(value);
    if (url.username !== "" || url.password !== "") throw configurationFailure();
    return url;
  } catch {
    throw configurationFailure();
  }
}

function isTunedInEnvironment(value: unknown): value is TunedInEnvironment {
  return value === "Local" || value === "Development" || value === "Staging" ||
    value === "Production";
}

function isLocalSupabaseUrl(url: URL): boolean {
  const allowedHost = url.hostname === "127.0.0.1" || url.hostname === "localhost" ||
    url.hostname === "[::1]" || url.hostname === "kong";
  const allowedPort = url.port === "" || url.port === "54321" || url.port === "8000";
  return url.protocol === "http:" && allowedHost && allowedPort && url.pathname === "/" &&
    url.search === "" && url.username === "" && url.password === "" && url.hash === "";
}

function isLocalMusicBrainzUrl(url: URL): boolean {
  const allowedHost = url.hostname === "127.0.0.1" || url.hostname === "localhost" ||
    url.hostname === "[::1]" || url.hostname === "host.docker.internal";
  const numericPort = Number(url.port);
  const allowedPort = Number.isInteger(numericPort) && numericPort >= 1_024 &&
    numericPort <= 65_535;
  return url.protocol === "http:" && allowedHost && allowedPort && url.pathname === "/ws/2/" &&
    url.search === "" && url.username === "" && url.password === "" && url.hash === "";
}

function isContactableUserAgent(value: string): boolean {
  if (value.length > 240 || value.endsWith(".invalid)") || /["'\\#\r\n]/.test(value)) return false;
  return /^tunedIn\/[A-Za-z0-9][A-Za-z0-9._-]{0,63} \((?:https:\/\/[^\s)]+|mailto:[^@\s)]+@[^.\s)]+\.[^\s)]+)\)$/
    .test(
      value,
    );
}

function configurationFailure(): CatalogError {
  return new CatalogError(
    "configuration_error",
    503,
    "The music catalog is not configured.",
    true,
  );
}
