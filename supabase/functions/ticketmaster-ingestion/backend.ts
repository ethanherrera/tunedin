import { IngestionError } from "./errors.ts";
import type { CompletionInput, JsonValue } from "./types.ts";
import { parseTasks } from "./validation.ts";

const MAX_DATABASE_RESPONSE_BYTES = 2_000_000;

export class IngestionBackend {
  readonly #supabaseURL: URL;
  readonly #serviceRoleKey: string;
  readonly #fetch: typeof fetch;

  constructor(options: {
    supabaseURL: URL;
    serviceRoleKey: string;
    fetch?: typeof fetch;
  }) {
    this.#supabaseURL = options.supabaseURL;
    this.#serviceRoleKey = options.serviceRoleKey;
    this.#fetch = options.fetch ?? fetch;
  }

  async startRun(): Promise<string> {
    const value = await this.#rpc("start_ticketmaster_ingestion", {});
    if (typeof value !== "string") throw databaseFailure();
    return value;
  }

  async claimTasks(limit = 1): Promise<ReturnType<typeof parseTasks>> {
    return parseTasks(
      await this.#rpc("claim_ticketmaster_ingestion_tasks", {
        p_limit: limit,
        p_visibility_seconds: 120,
      }),
    );
  }

  async completePage(input: CompletionInput): Promise<void> {
    await this.#rpc("complete_ticketmaster_ingestion_page", {
      p_message_id: input.task.messageId,
      p_run_id: input.task.runId,
      p_page_number: input.task.page,
      p_events: input.events.map(eventPayload),
      p_raw_event_count: input.rawEventCount,
      p_rejected_event_count: input.rejectedEventCount,
      p_total_elements: input.totalElements,
      p_total_pages: input.totalPages,
      p_has_more: input.hasMore,
    });
  }

  async failTask(
    messageId: number,
    code: string,
    retryable: boolean,
  ): Promise<void> {
    await this.#rpc("fail_ticketmaster_ingestion_task", {
      p_message_id: messageId,
      p_error_code: /^[a-z][a-z0-9_]{0,63}$/.test(code) ? code : "internal_error",
      p_retryable: retryable,
    });
  }

  async status(runId: string | null): Promise<JsonValue> {
    return await this.#rpc("get_ticketmaster_ingestion_status", { p_run_id: runId });
  }

  async reserveUpstreamSlot(): Promise<void> {
    const reservedAt = await this.#rpc("reserve_ticketmaster_request_slot", {});
    if (typeof reservedAt !== "string") throw databaseFailure();
    const wait = Date.parse(reservedAt) - Date.now();
    if (!Number.isFinite(wait) || wait > 5_000) throw databaseFailure();
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
  }

  async #rpc(name: string, body: Record<string, unknown>): Promise<JsonValue> {
    const url = new URL(`rest/v1/rpc/${name}`, this.#supabaseURL);
    let response: Response;
    try {
      response = await this.#fetch(url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${this.#serviceRoleKey}`,
          apikey: this.#serviceRoleKey,
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });
    } catch {
      throw databaseFailure();
    }
    const text = await response.text();
    if (new TextEncoder().encode(text).byteLength > MAX_DATABASE_RESPONSE_BYTES) {
      throw databaseFailure();
    }
    if (!response.ok) throw databaseFailure();
    if (response.status === 204 || text === "") return null;
    try {
      return JSON.parse(text) as JsonValue;
    } catch {
      throw databaseFailure();
    }
  }
}

function eventPayload(event: CompletionInput["events"][number]): Record<string, unknown> {
  return {
    event_id: event.id,
    title: event.name,
    event_date: event.localDate,
    local_start_time: event.localTime,
    starts_at: event.dateTime,
    time_zone: event.timeZone ?? "America/Los_Angeles",
    status: event.status,
    source_url: event.ticketURL,
    image_url: null,
    source_updated_at: null,
    venue: {
      id: event.venue.id,
      name: event.venue.name,
      url: event.venue.url,
      address: event.venue.address,
      latitude: event.venue.latitude,
      longitude: event.venue.longitude,
      area: {
        city: event.venue.city,
        state_code: event.venue.stateCode,
        country_code: event.venue.countryCode,
      },
    },
    artists: event.artists.map((artist, index) => ({
      id: artist.id,
      name: artist.name,
      url: artist.url,
      is_headliner: index === 0,
    })),
  };
}

function databaseFailure(): IngestionError {
  return new IngestionError(
    "database_error",
    503,
    "Ticketmaster ingestion storage is temporarily unavailable.",
    true,
  );
}
