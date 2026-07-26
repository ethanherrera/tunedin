import assert from "node:assert/strict";
import { eventArtworkPriorities, MusicBrainzEventArtworkScheduler } from "../event_artwork.ts";
import type { CatalogBackend, MusicBrainzEventCover } from "../types.ts";

const event = {
  event_mbid: "f4000000-0000-4000-8000-000000000001",
  title: "Fixture Headliner at Fixture Hall",
  event_date: "2026-08-15",
  local_start_time: "20:00:00",
  venue: {
    mbid: "f4000000-0000-4000-8000-000000000003",
    name: "Fixture Hall",
    area_mbid: null,
    area_name: null,
  },
  artists: [{
    mbid: "f4000000-0000-4000-8000-000000000002",
    name: "Fixture Headliner",
    is_headliner: true,
  }],
  source_status: "active" as const,
  source_updated_at: null,
};

Deno.test("exact Event Art Archive artwork wins without consulting artist fallbacks", async () => {
  const backend = new ArtworkBackend();
  const urls: string[] = [];
  const scheduler = schedulerFor(backend, (url) => {
    urls.push(url.pathname);
    return json({
      images: [{
        front: true,
        image: "https://images.example.test/event.jpg",
        thumbnails: { "500": "https://images.example.test/event-500.jpg" },
      }],
    });
  });

  await scheduleAndWait(scheduler, backend);

  assert.deepEqual(urls, ["/event/f4000000-0000-4000-8000-000000000001"]);
  assert.equal(backend.completed[0].priority, eventArtworkPriorities.event);
  assert.deepEqual(backend.completed[0].cover, {
    source: "provider",
    remote_url: "https://images.example.test/event-500.jpg",
    provider_name: "MusicBrainz Event Art Archive",
    attribution: null,
    source_page_url: "https://eventartarchive.org/event/f4000000-0000-4000-8000-000000000001",
    license_name: null,
    license_url: null,
  });
});

Deno.test("Wikimedia artist artwork preserves the required attribution and license", async () => {
  const backend = new ArtworkBackend();
  const scheduler = schedulerFor(backend, (url) => {
    if (url.pathname.startsWith("/event/")) return json({ images: [] });
    if (url.pathname.startsWith("/ws/2/artist/")) {
      return json({
        relations: [{ type: "wikidata", url: { resource: "https://www.wikidata.org/wiki/Q42" } }],
      });
    }
    if (url.pathname === "/wiki/Special:EntityData/Q42.json") {
      return json({
        entities: {
          Q42: { claims: { P18: [{ mainsnak: { datavalue: { value: "Artist.jpg" } } }] } },
        },
      });
    }
    if (url.pathname === "/w/api.php") {
      return json({
        query: {
          pages: {
            "1": {
              imageinfo: [{
                thumburl: "https://upload.wikimedia.org/artist-1200.jpg",
                descriptionurl: "https://commons.wikimedia.org/wiki/File:Artist.jpg",
                extmetadata: {
                  Artist: { value: "<a>Fixture Photographer</a>" },
                  LicenseShortName: { value: "CC BY-SA 4.0" },
                  LicenseUrl: { value: "https://creativecommons.org/licenses/by-sa/4.0/" },
                },
              }],
            },
          },
        },
      });
    }
    throw new Error(`Unexpected URL ${url}`);
  });

  await scheduleAndWait(scheduler, backend);

  assert.equal(backend.completed[0].priority, eventArtworkPriorities.artist);
  assert.deepEqual(backend.completed[0].cover, {
    source: "wikimedia",
    remote_url: "https://upload.wikimedia.org/artist-1200.jpg",
    provider_name: null,
    attribution: "Fixture Photographer",
    source_page_url: "https://commons.wikimedia.org/wiki/File:Artist.jpg",
    license_name: "CC BY-SA 4.0",
    license_url: "https://creativecommons.org/licenses/by-sa/4.0/",
  });
});

Deno.test("album art is used only after exact and artist art are unavailable", async () => {
  const backend = new ArtworkBackend();
  const scheduler = schedulerFor(backend, (url) => {
    if (url.pathname.startsWith("/event/")) return json({ images: [] });
    if (url.pathname.startsWith("/ws/2/artist/")) return json({ relations: [] });
    if (url.pathname === "/ws/2/release-group") {
      return json({
        "release-groups": [{
          id: "f4000000-0000-4000-8000-000000000005",
          "primary-type": "Album",
        }],
      });
    }
    if (url.pathname === "/release-group/f4000000-0000-4000-8000-000000000005") {
      return json({ images: [{ image: "https://images.example.test/album.jpg" }] });
    }
    throw new Error(`Unexpected URL ${url}`);
  });

  await scheduleAndWait(scheduler, backend);

  assert.equal(backend.completed[0].priority, eventArtworkPriorities.album);
  assert.equal(backend.completed[0].cover?.provider_name, "Cover Art Archive");
});

function schedulerFor(
  backend: ArtworkBackend,
  fetch: (url: URL) => Response,
): MusicBrainzEventArtworkScheduler {
  return new MusicBrainzEventArtworkScheduler({
    backend: backend as unknown as CatalogBackend,
    musicBrainzBaseUrl: new URL("https://fixture.test/ws/2/"),
    musicBrainzUserAgent: "tunedIn/test (mailto:test@example.com)",
    eventArtBaseUrl: new URL("https://fixture.test/"),
    coverArtBaseUrl: new URL("https://fixture.test/"),
    wikidataBaseUrl: new URL("https://fixture.test/"),
    commonsApiUrl: new URL("https://fixture.test/w/api.php"),
    waitForMusicBrainzSlot: () => Promise.resolve(),
    defer: (task) => backend.deferred.push(task),
    fetch: (input) => Promise.resolve(fetch(new URL(String(input)))),
  });
}

async function scheduleAndWait(
  scheduler: MusicBrainzEventArtworkScheduler,
  backend: ArtworkBackend,
): Promise<void> {
  scheduler.schedule([{ eventId: "d4000000-0000-4000-8000-000000000001", event }]);
  await Promise.all(backend.deferred);
}

class ArtworkBackend {
  readonly deferred: Promise<void>[] = [];
  readonly completed: Array<{
    eventId: string;
    cover: MusicBrainzEventCover | null;
    priority: number | null;
  }> = [];

  claimMusicBrainzEventArtwork(): Promise<boolean> {
    return Promise.resolve(true);
  }

  completeMusicBrainzEventArtwork(
    eventId: string,
    cover: MusicBrainzEventCover | null,
    priority: number | null,
  ): Promise<void> {
    this.completed.push({ eventId, cover, priority });
    return Promise.resolve();
  }

  failMusicBrainzEventArtwork(): Promise<void> {
    return Promise.resolve();
  }
}

function json(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    headers: { "content-type": "application/json" },
  });
}
