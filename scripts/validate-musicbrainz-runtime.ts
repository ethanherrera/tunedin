import { runtimeConfiguration } from "../supabase/functions/music-catalog/index.ts";

const environment = Deno.args[0];
if (environment !== "Development" && environment !== "Staging" && environment !== "Production") {
  throw new Error("Usage: validate-musicbrainz-runtime.ts <Development|Staging|Production>");
}

runtimeConfiguration({
  TUNEDIN_ENVIRONMENT: environment,
  SUPABASE_URL: "https://abcdefghijklmnopqrst.supabase.co",
  SUPABASE_ANON_KEY: "validation-only-anonymous-key",
  SUPABASE_SERVICE_ROLE_KEY: "validation-only-service-key",
  MUSICBRAINZ_USER_AGENT: Deno.env.get("MUSICBRAINZ_USER_AGENT"),
});

console.log(`${environment} MusicBrainz runtime configuration verified.`);
