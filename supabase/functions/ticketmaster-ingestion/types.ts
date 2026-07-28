import type { DiscoveryCandidate } from "../event-discovery/types.ts";
import type {
  TicketmasterRejectedEvent,
  TicketmasterRejectionReason,
} from "../event-discovery/ticketmaster.ts";

export type IngestionOperation = "run" | "resume" | "status";

export interface IngestionRequest {
  operation: IngestionOperation;
  runId: string | null;
}

export interface IngestionTask {
  messageId: number;
  readCount: number;
  runId: string;
  page: number;
  city: string;
  stateCode: string;
  countryCode: string;
  coverageStartsAt: string;
  coverageEndsAt: string;
}

export interface IngestionRunResponse {
  operation: IngestionOperation;
  runId: string | null;
  processedPages: number;
  rejectionReasons: Record<TicketmasterRejectionReason, number>;
  status: unknown;
}

export interface CompletionInput {
  task: IngestionTask;
  events: DiscoveryCandidate[];
  rejections: TicketmasterRejectedEvent[];
  rawEventCount: number;
  rejectedEventCount: number;
  totalElements: number;
  totalPages: number;
  hasMore: boolean;
}

export type JsonValue =
  | null
  | boolean
  | number
  | string
  | JsonValue[]
  | { [key: string]: JsonValue };
