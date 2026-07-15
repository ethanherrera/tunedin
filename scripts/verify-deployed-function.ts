export interface VerifiedDeployedFunction {
  slug: string;
  status: "ACTIVE";
  version: number;
}

const functionSlugPattern = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

export function verifyDeployedFunction(
  functionsJson: string,
  expectedSlug: string,
): VerifiedDeployedFunction {
  if (!functionSlugPattern.test(expectedSlug)) {
    throw new Error("The expected function slug is invalid.");
  }

  let decoded: unknown;
  try {
    decoded = JSON.parse(functionsJson);
  } catch {
    throw new Error("The deployed function list is not valid JSON.");
  }

  if (!Array.isArray(decoded)) {
    throw new Error("The deployed function list must be a JSON array.");
  }

  const matches = decoded.filter((entry) => isRecord(entry) && entry.slug === expectedSlug);
  if (matches.length === 0) {
    throw new Error(
      `The deployed function list does not contain ${expectedSlug}.`,
    );
  }
  if (matches.length !== 1) {
    throw new Error(
      `The deployed function list contains duplicate ${expectedSlug} entries.`,
    );
  }

  const deployed = matches[0];
  if (!isRecord(deployed)) {
    throw new Error(`The deployed ${expectedSlug} record is invalid.`);
  }

  if (deployed.status !== "ACTIVE") {
    throw new Error(`The deployed ${expectedSlug} function is not active.`);
  }
  if (
    typeof deployed.version !== "number" ||
    !Number.isSafeInteger(deployed.version) ||
    deployed.version <= 0
  ) {
    throw new Error(
      `The deployed ${expectedSlug} function has an invalid version.`,
    );
  }

  return {
    slug: expectedSlug,
    status: "ACTIVE",
    version: deployed.version,
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

if (import.meta.main) {
  const expectedSlug = Deno.args[0];
  if (Deno.args.length !== 1 || expectedSlug === undefined) {
    console.error("Usage: verify-deployed-function.ts <function-slug>");
    Deno.exit(1);
  }

  try {
    const functionsJson = await new Response(Deno.stdin.readable).text();
    const deployed = verifyDeployedFunction(functionsJson, expectedSlug);
    console.log(deployed.version);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Function verification failed.";
    console.error(message);
    Deno.exit(1);
  }
}
