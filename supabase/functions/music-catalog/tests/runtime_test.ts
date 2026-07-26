import assert from "node:assert/strict";
import { CatalogError } from "../errors.ts";
import { runtimeConfiguration } from "../index.ts";

const keys = {
  SUPABASE_ANON_KEY: "fixture-anon-key",
  SUPABASE_SERVICE_ROLE_KEY: "fixture-service-role-key",
};

Deno.test("hosted configuration accepts only official MusicBrainz and a contactable User-Agent", () => {
  const configuration = runtimeConfiguration({
    ...keys,
    TUNEDIN_ENVIRONMENT: "Development",
    SUPABASE_URL: "https://abcdefghijklmnopqrst.supabase.co",
    MUSICBRAINZ_USER_AGENT: "tunedIn/abc123 (mailto:catalog@example.com)",
  });
  assert.equal(configuration.musicBrainzBaseUrl.href, "https://musicbrainz.org/ws/2/");

  assert.throws(
    () =>
      runtimeConfiguration({
        ...keys,
        TUNEDIN_ENVIRONMENT: "Staging",
        SUPABASE_URL: "https://abcdefghijklmnopqrst.supabase.co",
        MUSICBRAINZ_BASE_URL: "https://example.com/ws/2/",
        MUSICBRAINZ_USER_AGENT: "tunedIn/abc123 (mailto:catalog@example.com)",
      }),
    isConfigurationError,
  );
  assert.throws(
    () =>
      runtimeConfiguration({
        ...keys,
        TUNEDIN_ENVIRONMENT: "Production",
        SUPABASE_URL: "https://abcdefghijklmnopqrst.supabase.co",
        MUSICBRAINZ_USER_AGENT: "tunedIn/prod (mailto:fixture@tunedin.invalid)",
      }),
    isConfigurationError,
  );
});

Deno.test("Local permits only the exact Docker gateway and fixture-stub hosts", () => {
  const dockerConfiguration = runtimeConfiguration({
    ...keys,
    TUNEDIN_ENVIRONMENT: "Local",
    SUPABASE_URL: "http://kong:8000",
    MUSICBRAINZ_BASE_URL: "http://host.docker.internal:18081/ws/2/",
    MUSICBRAINZ_ARTWORK_BASE_URL: "http://host.docker.internal:18081/",
  });
  assert.equal(dockerConfiguration.environment, "Local");

  const hostConfiguration = runtimeConfiguration({
    ...keys,
    TUNEDIN_ENVIRONMENT: "Local",
    SUPABASE_URL: "http://127.0.0.1:54321",
    MUSICBRAINZ_BASE_URL: "http://127.0.0.1:18081/ws/2/",
    MUSICBRAINZ_ARTWORK_BASE_URL: "http://127.0.0.1:18081/",
  });
  assert.equal(hostConfiguration.environment, "Local");

  assert.throws(
    () =>
      runtimeConfiguration({
        ...keys,
        TUNEDIN_ENVIRONMENT: "Local",
        SUPABASE_URL: "https://abcdefghijklmnopqrst.supabase.co",
        MUSICBRAINZ_BASE_URL: "http://host.docker.internal:18081/ws/2/",
        MUSICBRAINZ_ARTWORK_BASE_URL: "http://host.docker.internal:18081/",
      }),
    isConfigurationError,
  );
  assert.throws(
    () =>
      runtimeConfiguration({
        ...keys,
        TUNEDIN_ENVIRONMENT: "Local",
        SUPABASE_URL: "http://kong:8000",
        MUSICBRAINZ_BASE_URL: "http://example.com:18081/ws/2/",
        MUSICBRAINZ_ARTWORK_BASE_URL: "http://host.docker.internal:18081/",
      }),
    isConfigurationError,
  );
});

function isConfigurationError(error: unknown): boolean {
  return error instanceof CatalogError && error.code === "configuration_error";
}
