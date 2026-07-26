import type {
  CatalogBackend,
  EventArtworkScheduler,
  MusicBrainzEventArtworkCandidate,
  MusicBrainzEventCover,
} from "./types.ts";
import { isPlainObject, parseMusicBrainzUuid } from "./validation.ts";

const MAX_RESPONSE_BYTES = 1_000_000;
const REQUEST_TIMEOUT_MS = 8_000;
const EVENT_ART_PRIORITY = 1;
const TOUR_ART_PRIORITY = 2;
const ARTIST_ART_PRIORITY = 3;
const ALBUM_ART_PRIORITY = 4;
const EVENT_ART_PROVIDER = "MusicBrainz Event Art Archive";
const ALBUM_ART_PROVIDER = "Cover Art Archive";

export interface MusicBrainzEventArtworkSchedulerOptions {
  backend: CatalogBackend;
  musicBrainzBaseUrl: URL;
  musicBrainzUserAgent: string;
  defer(task: Promise<void>): void;
  waitForMusicBrainzSlot(): Promise<void>;
  fetch?: typeof fetch;
  eventArtBaseUrl?: URL;
  coverArtBaseUrl?: URL;
  wikidataBaseUrl?: URL;
  commonsApiUrl?: URL;
}

/**
 * Resolves remote artwork only after the search response is sent. Event Art
 * Archive is exact-event artwork; MusicBrainz does not provide a comparable
 * tour image archive, so the tour tier is intentionally skipped until an
 * approved provider supplies an exact tour asset.
 */
export class MusicBrainzEventArtworkScheduler implements EventArtworkScheduler {
  readonly #backend: CatalogBackend;
  readonly #musicBrainzBaseUrl: URL;
  readonly #musicBrainzUserAgent: string;
  readonly #defer: (task: Promise<void>) => void;
  readonly #waitForMusicBrainzSlot: () => Promise<void>;
  readonly #fetch: typeof fetch;
  readonly #eventArtBaseUrl: URL;
  readonly #coverArtBaseUrl: URL;
  readonly #wikidataBaseUrl: URL;
  readonly #commonsApiUrl: URL;

  constructor(options: MusicBrainzEventArtworkSchedulerOptions) {
    this.#backend = options.backend;
    this.#musicBrainzBaseUrl = options.musicBrainzBaseUrl;
    this.#musicBrainzUserAgent = options.musicBrainzUserAgent;
    this.#defer = options.defer;
    this.#waitForMusicBrainzSlot = options.waitForMusicBrainzSlot;
    this.#fetch = options.fetch ?? fetch;
    this.#eventArtBaseUrl = options.eventArtBaseUrl ?? new URL("https://coverartarchive.org/");
    this.#coverArtBaseUrl = options.coverArtBaseUrl ?? new URL("https://coverartarchive.org/");
    this.#wikidataBaseUrl = options.wikidataBaseUrl ?? new URL("https://www.wikidata.org/");
    this.#commonsApiUrl = options.commonsApiUrl ??
      new URL("https://commons.wikimedia.org/w/api.php");
  }

  schedule(candidates: MusicBrainzEventArtworkCandidate[]): void {
    if (candidates.length === 0) return;
    this.#defer(
      this.#resolve(candidates).catch(() => {
        // A search must never fail because best-effort media enrichment failed.
      }),
    );
  }

  async #resolve(candidates: MusicBrainzEventArtworkCandidate[]): Promise<void> {
    const claimed = await Promise.all(candidates.map(async (candidate) => {
      try {
        return await this.#backend.claimMusicBrainzEventArtwork(candidate.eventId)
          ? candidate
          : null;
      } catch {
        return null;
      }
    }));
    const pending = claimed.filter((candidate): candidate is MusicBrainzEventArtworkCandidate =>
      candidate !== null
    );

    const withoutExactArtwork: MusicBrainzEventArtworkCandidate[] = [];
    await mapWithConcurrency(pending, 4, async (candidate) => {
      try {
        const cover = await this.#exactEventArtwork(candidate.event.event_mbid);
        if (cover === null) {
          withoutExactArtwork.push(candidate);
          return;
        }
        await this.#backend.completeMusicBrainzEventArtwork(
          candidate.eventId,
          cover,
          EVENT_ART_PRIORITY,
        );
      } catch {
        await this.#fail(candidate.eventId);
      }
    });

    // A single artist image lookup can serve every unillustrated event in the
    // page for that headliner, avoiding duplicate MusicBrainz/Wikidata calls.
    const byHeadliner = new Map<string, MusicBrainzEventArtworkCandidate[]>();
    for (const candidate of withoutExactArtwork) {
      const headliner = candidate.event.artists.find((artist) => artist.is_headliner) ??
        candidate.event.artists[0];
      const entries = byHeadliner.get(headliner.mbid) ?? [];
      entries.push(candidate);
      byHeadliner.set(headliner.mbid, entries);
    }

    for (const entries of byHeadliner.values()) {
      const headliner = entries[0].event.artists.find((artist) => artist.is_headliner) ??
        entries[0].event.artists[0];
      try {
        const artistCover = await this.#artistArtwork(headliner.mbid);
        if (artistCover !== null) {
          await this.#completeAll(entries, artistCover, ARTIST_ART_PRIORITY);
          continue;
        }

        // Tier 2 is reserved for a provider-authenticated, tour-specific asset.
        // MusicBrainz supplies no such asset, so never borrow a poster from a
        // different tour stop. Album art is deliberately the final fallback.
        const albumCover = await this.#albumArtwork(headliner.mbid);
        await this.#completeAll(
          entries,
          albumCover,
          albumCover === null ? null : ALBUM_ART_PRIORITY,
        );
      } catch {
        await Promise.all(entries.map((entry) => this.#fail(entry.eventId)));
      }
    }
  }

  async #completeAll(
    entries: MusicBrainzEventArtworkCandidate[],
    cover: MusicBrainzEventCover | null,
    priority: number | null,
  ): Promise<void> {
    await Promise.all(entries.map(async (entry) => {
      try {
        await this.#backend.completeMusicBrainzEventArtwork(entry.eventId, cover, priority);
      } catch {
        await this.#fail(entry.eventId);
      }
    }));
  }

  async #fail(eventId: string): Promise<void> {
    try {
      await this.#backend.failMusicBrainzEventArtwork(eventId);
    } catch {
      // The short lease expires even if recording the transient failure fails.
    }
  }

  async #exactEventArtwork(eventMbid: string): Promise<MusicBrainzEventCover | null> {
    parseMusicBrainzUuid(eventMbid, "MusicBrainz event ID");
    const payload = await this.#requestJson(
      new URL(`event/${eventMbid}`, this.#eventArtBaseUrl),
    );
    const imageUrl = artworkImageUrl(payload);
    if (imageUrl === null) return null;
    return {
      source: "provider",
      remote_url: imageUrl,
      provider_name: EVENT_ART_PROVIDER,
      attribution: null,
      source_page_url: `https://coverartarchive.org/event/${eventMbid}`,
      license_name: null,
      license_url: null,
    };
  }

  async #artistArtwork(artistMbid: string): Promise<MusicBrainzEventCover | null> {
    const wikidataId = await this.#artistWikidataId(artistMbid);
    if (wikidataId === null) return null;
    const entity = await this.#requestJson(
      new URL(`wiki/Special:EntityData/${wikidataId}.json`, this.#wikidataBaseUrl),
    );
    const imageName = wikidataImageName(entity, wikidataId);
    if (imageName === null) return null;
    return await this.#commonsArtwork(imageName);
  }

  async #artistWikidataId(artistMbid: string): Promise<string | null> {
    parseMusicBrainzUuid(artistMbid, "MusicBrainz artist ID");
    await this.#waitForMusicBrainzSlot();
    const url = new URL(`artist/${artistMbid}`, this.#musicBrainzBaseUrl);
    url.searchParams.set("fmt", "json");
    url.searchParams.set("inc", "url-rels");
    const payload = await this.#requestJson(url);
    const root = object(payload);
    const relations = Array.isArray(root.relations) ? root.relations : [];
    for (const relation of relations) {
      if (
        !isPlainObject(relation) || relation.type !== "wikidata" || !isPlainObject(relation.url)
      ) {
        continue;
      }
      const resource = relation.url.resource;
      if (typeof resource !== "string") continue;
      const matched = /^https:\/\/www\.wikidata\.org\/wiki\/(Q\d+)$/.exec(resource);
      if (matched !== null) return matched[1];
    }
    return null;
  }

  async #commonsArtwork(imageName: string): Promise<MusicBrainzEventCover | null> {
    const url = new URL(this.#commonsApiUrl);
    url.searchParams.set("action", "query");
    url.searchParams.set("format", "json");
    url.searchParams.set("prop", "imageinfo");
    url.searchParams.set("iiprop", "url|extmetadata");
    url.searchParams.set("iiurlwidth", "1200");
    url.searchParams.set("titles", `File:${imageName}`);
    const payload = await this.#requestJson(url);
    const pages = object(object(object(payload).query).pages);
    const page = Object.values(pages).find(isPlainObject);
    if (page === undefined || !Array.isArray(page.imageinfo) || !isPlainObject(page.imageinfo[0])) {
      return null;
    }
    const image = page.imageinfo[0];
    const remoteUrl = httpsUrl(image.thumburl) ?? httpsUrl(image.url);
    const sourcePageUrl = httpsUrl(image.descriptionurl);
    const metadata = isPlainObject(image.extmetadata) ? image.extmetadata : {};
    const attribution = plainMetadataText(metadata.Artist) ?? plainMetadataText(metadata.Credit);
    const licenseName = plainMetadataText(metadata.LicenseShortName);
    const licenseUrl = metadataUrl(metadata.LicenseUrl);
    if (
      remoteUrl === null || sourcePageUrl === null || attribution === null ||
      licenseName === null ||
      licenseUrl === null
    ) return null;
    return {
      source: "wikimedia",
      remote_url: remoteUrl,
      provider_name: null,
      attribution,
      source_page_url: sourcePageUrl,
      license_name: licenseName,
      license_url: licenseUrl,
    };
  }

  async #albumArtwork(artistMbid: string): Promise<MusicBrainzEventCover | null> {
    await this.#waitForMusicBrainzSlot();
    const browseUrl = new URL("release-group", this.#musicBrainzBaseUrl);
    browseUrl.searchParams.set("artist", artistMbid);
    browseUrl.searchParams.set("fmt", "json");
    browseUrl.searchParams.set("limit", "10");
    const browsePayload = await this.#requestJson(browseUrl);
    const releaseGroupValue = object(browsePayload)["release-groups"];
    const releaseGroups: unknown[] = Array.isArray(releaseGroupValue) ? releaseGroupValue : [];
    const ids = releaseGroups
      .filter(isPlainObject)
      .filter((group) => group["primary-type"] === "Album" || group["primary-type"] === "EP")
      .map((group) => typeof group.id === "string" ? group.id : null)
      .filter((id): id is string => id !== null)
      .slice(0, 5);
    for (const releaseGroupMbid of ids) {
      parseMusicBrainzUuid(releaseGroupMbid, "MusicBrainz release group ID");
      const payload = await this.#requestJson(
        new URL(`release-group/${releaseGroupMbid}`, this.#coverArtBaseUrl),
      );
      const imageUrl = artworkImageUrl(payload);
      if (imageUrl !== null) {
        return {
          source: "provider",
          remote_url: imageUrl,
          provider_name: ALBUM_ART_PROVIDER,
          attribution: null,
          source_page_url: `https://coverartarchive.org/release-group/${releaseGroupMbid}`,
          license_name: null,
          license_url: null,
        };
      }
    }
    return null;
  }

  async #requestJson(url: URL): Promise<unknown> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    let response: Response;
    try {
      response = await this.#fetch(url, {
        headers: {
          Accept: "application/json",
          "User-Agent": this.#musicBrainzUserAgent,
        },
        signal: controller.signal,
      });
    } catch {
      throw new Error("Artwork source unavailable");
    } finally {
      clearTimeout(timeout);
    }
    if (response.status === 404) return {};
    if (!response.ok) throw new Error("Artwork source unavailable");
    const text = await readBoundedText(response);
    try {
      return JSON.parse(text);
    } catch {
      throw new Error("Artwork source returned invalid JSON");
    }
  }
}

function artworkImageUrl(payload: unknown): string | null {
  const images = object(payload).images;
  if (!Array.isArray(images)) return null;
  const image = images.find((item) => isPlainObject(item) && item.front === true) ??
    images.find(isPlainObject);
  if (image === undefined) return null;
  const thumbnails = isPlainObject(image.thumbnails) ? image.thumbnails : {};
  return httpsUrl(thumbnails["500"]) ?? httpsUrl(image.image);
}

function wikidataImageName(payload: unknown, wikidataId: string): string | null {
  const entities = object(payload).entities;
  const entity = isPlainObject(entities) && isPlainObject(entities[wikidataId])
    ? entities[wikidataId]
    : null;
  const claims = entity === null || !isPlainObject(entity.claims) ? null : entity.claims;
  const statements = claims === null || !Array.isArray(claims.P18) ? [] : claims.P18;
  const first = isPlainObject(statements[0]) && isPlainObject(statements[0].mainsnak)
    ? statements[0].mainsnak
    : null;
  const datavalue = first === null || !isPlainObject(first.datavalue)
    ? null
    : first.datavalue.value;
  return typeof datavalue === "string" && datavalue.length > 0 && datavalue.length <= 240
    ? datavalue
    : null;
}

function plainMetadataText(value: unknown): string | null {
  if (!isPlainObject(value) || typeof value.value !== "string") return null;
  const text = value.value.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
  const hasControlCharacter = Array.from(text).some((character) => {
    const codePoint = character.codePointAt(0) ?? 0;
    return codePoint <= 31 || codePoint === 127;
  });
  return text.length > 0 && text.length <= 500 && !hasControlCharacter ? text : null;
}

function metadataUrl(value: unknown): string | null {
  return isPlainObject(value) ? httpsUrl(value.value) : null;
}

function httpsUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 2048) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" ? url.href : null;
  } catch {
    return null;
  }
}

function object(value: unknown): Record<string, unknown> {
  return isPlainObject(value) ? value : {};
}

async function readBoundedText(response: Response): Promise<string> {
  const reader = response.body?.getReader();
  if (reader === undefined) throw new Error("Artwork source returned no body");
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > MAX_RESPONSE_BYTES) {
      await reader.cancel();
      throw new Error("Artwork source response is too large");
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
}

async function mapWithConcurrency<T>(
  values: T[],
  concurrency: number,
  operation: (value: T) => Promise<void>,
): Promise<void> {
  let nextIndex = 0;
  await Promise.all(Array.from({ length: Math.min(concurrency, values.length) }, async () => {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= values.length) return;
      await operation(values[index]);
    }
  }));
}

export const eventArtworkPriorities = {
  event: EVENT_ART_PRIORITY,
  tour: TOUR_ART_PRIORITY,
  artist: ARTIST_ART_PRIORITY,
  album: ALBUM_ART_PRIORITY,
} as const;
