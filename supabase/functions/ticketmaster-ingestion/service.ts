import type { DiscoverRequest } from "../event-discovery/types.ts";
import type { TicketmasterRejectionReason } from "../event-discovery/ticketmaster.ts";
import { IngestionError, safeError } from "./errors.ts";
import type {
  CompletionInput,
  IngestionOperation,
  IngestionRunResponse,
  IngestionTask,
  JsonValue,
} from "./types.ts";

const MAX_PAGES_PER_INVOCATION = 10;
const MAX_RUNTIME_MS = 60_000;

export interface IngestionBackendPort {
  startRun(): Promise<string>;
  claimTasks(limit?: number): Promise<IngestionTask[]>;
  completePage(input: CompletionInput): Promise<void>;
  failTask(messageId: number, code: string, retryable: boolean): Promise<void>;
  status(runId: string | null): Promise<JsonValue>;
  reserveUpstreamSlot(): Promise<void>;
}

export interface TicketmasterPort {
  discover(request: DiscoverRequest): Promise<{
    events: CompletionInput["events"];
    rawEventCount: number;
    rejectedEventCount: number;
    totalElements: number;
    totalPages: number;
    hasMore: boolean;
    rejectionReasons: Record<TicketmasterRejectionReason, number>;
  }>;
}

export class TicketmasterIngestionService {
  constructor(
    private readonly backend: IngestionBackendPort,
    private readonly ticketmaster: TicketmasterPort,
    private readonly now: () => number = Date.now,
  ) {}

  async execute(operation: IngestionOperation, requestedRunId: string | null) {
    if (operation === "status") {
      return {
        operation,
        runId: requestedRunId,
        processedPages: 0,
        rejectionReasons: emptyRejectionReasons(),
        status: await this.backend.status(requestedRunId),
      } satisfies IngestionRunResponse;
    }

    const runId = operation === "run" ? await this.backend.startRun() : null;
    const startedAt = this.now();
    let processedPages = 0;
    const rejectionReasons = emptyRejectionReasons();

    while (
      processedPages < MAX_PAGES_PER_INVOCATION &&
      this.now() - startedAt < MAX_RUNTIME_MS
    ) {
      const [task] = await this.backend.claimTasks(1);
      if (task === undefined) break;
      try {
        await this.backend.reserveUpstreamSlot();
        const page = await this.ticketmaster.discover(requestForTask(task));
        mergeRejectionReasons(rejectionReasons, page.rejectionReasons);
        await this.backend.completePage({
          task,
          events: page.events,
          rawEventCount: page.rawEventCount,
          rejectedEventCount: page.rejectedEventCount,
          totalElements: page.totalElements,
          totalPages: page.totalPages,
          hasMore: page.hasMore,
        });
        processedPages += 1;
      } catch (unknownError) {
        const error = ingestionError(unknownError);
        await this.backend.failTask(task.messageId, error.code, error.retryable);
        break;
      }
    }

    return {
      operation,
      runId,
      processedPages,
      rejectionReasons,
      status: await this.backend.status(runId),
    } satisfies IngestionRunResponse;
  }
}

function emptyRejectionReasons(): Record<TicketmasterRejectionReason, number> {
  return {
    event_shape: 0,
    event_dates: 0,
    venue: 0,
    lineup: 0,
    source_url: 0,
  };
}

function mergeRejectionReasons(
  target: Record<TicketmasterRejectionReason, number>,
  source: Record<TicketmasterRejectionReason, number>,
): void {
  for (const reason of Object.keys(target) as TicketmasterRejectionReason[]) {
    target[reason] += source[reason];
  }
}

function requestForTask(task: IngestionTask): DiscoverRequest {
  return {
    operation: "discover",
    location: {
      city: task.city,
      stateCode: task.stateCode,
      countryCode: task.countryCode,
    },
    startDateTime: task.coverageStartsAt,
    endDateTime: task.coverageEndsAt,
    genre: null,
    page: task.page,
  };
}

function ingestionError(error: unknown): IngestionError {
  if (
    error !== null &&
    typeof error === "object" &&
    "code" in error &&
    "retryable" in error &&
    typeof error.code === "string" &&
    typeof error.retryable === "boolean"
  ) {
    return new IngestionError(
      /^[a-z][a-z0-9_]{0,63}$/.test(error.code) ? error.code : "upstream_error",
      503,
      "Ticketmaster ingestion could not process an upstream page.",
      error.retryable,
    );
  }
  return safeError(error);
}
