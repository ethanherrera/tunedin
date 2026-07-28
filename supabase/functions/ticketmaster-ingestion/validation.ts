import { IngestionError } from "./errors.ts";
import type { IngestionRequest, IngestionTask, JsonValue } from "./types.ts";

export function parseIngestionRequest(value: unknown): IngestionRequest {
  if (!isObject(value)) throw invalidRequest();
  const keys = Object.keys(value);
  if (!keys.every((key) => key === "operation" || key === "runId")) throw invalidRequest();
  if (value.operation !== "run" && value.operation !== "resume" && value.operation !== "status") {
    throw invalidRequest();
  }
  const runId = value.runId === undefined || value.runId === null ? null : parseUuid(value.runId);
  if (value.operation !== "status" && runId !== null) throw invalidRequest();
  return { operation: value.operation, runId };
}

export function parseTasks(value: JsonValue): IngestionTask[] {
  if (!Array.isArray(value) || value.length > 10) throw databaseFailure();
  return value.map((task) => {
    if (
      !isObject(task) ||
      !Number.isSafeInteger(task.message_id) ||
      !Number.isSafeInteger(task.read_count) ||
      !Number.isSafeInteger(task.page) ||
      typeof task.city !== "string" ||
      typeof task.state_code !== "string" ||
      typeof task.country_code !== "string" ||
      typeof task.coverage_starts_at !== "string" ||
      typeof task.coverage_ends_at !== "string"
    ) {
      throw databaseFailure();
    }
    const page = task.page as number;
    const messageId = task.message_id as number;
    const readCount = task.read_count as number;
    if (
      messageId < 1 ||
      readCount < 1 ||
      page < 0 ||
      page > 49 ||
      task.city !== "San Francisco" ||
      task.state_code !== "CA" ||
      task.country_code !== "US" ||
      !Number.isFinite(Date.parse(task.coverage_starts_at)) ||
      !Number.isFinite(Date.parse(task.coverage_ends_at))
    ) {
      throw databaseFailure();
    }
    return {
      messageId,
      readCount,
      runId: parseUuid(task.run_id),
      page,
      city: task.city,
      stateCode: task.state_code,
      countryCode: task.country_code,
      coverageStartsAt: task.coverage_starts_at,
      coverageEndsAt: task.coverage_ends_at,
    };
  });
}

export function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function parseUuid(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    )
  ) {
    throw invalidRequest();
  }
  return value.toLowerCase();
}

function invalidRequest(): IngestionError {
  return new IngestionError("invalid_request", 400, "The ingestion request is invalid.");
}

function databaseFailure(): IngestionError {
  return new IngestionError(
    "database_error",
    503,
    "Ticketmaster ingestion storage is temporarily unavailable.",
    true,
  );
}
