import { MusicBrainzClient } from "../supabase/functions/music-catalog/musicbrainz.ts";

const userAgent = Deno.env.get("MUSICBRAINZ_USER_AGENT");
if (userAgent === undefined || userAgent.length === 0) {
  throw new Error("Set a contactable MUSICBRAINZ_USER_AGENT before the opt-in live smoke.");
}

const client = new MusicBrainzClient({
  baseUrl: new URL("https://musicbrainz.org/ws/2/"),
  userAgent,
});
const scenarios = [
  ["artist", "Radiohead"],
  ["area", "San Francisco"],
  ["place", "The Fillmore"],
  ["song", "Creep"],
  ["tour", "In Rainbows Tour"],
] as const;

for (let index = 0; index < scenarios.length; index += 1) {
  const [kind, query] = scenarios[index];
  const result = await client.search(kind, query, 0, []);
  if (result.results.length === 0) {
    throw new Error(`The live ${kind} search returned no results.`);
  }
  console.log(`Live MusicBrainz ${kind} schema verified.`);
  if (index + 1 < scenarios.length) await new Promise((resolve) => setTimeout(resolve, 1_100));
}
