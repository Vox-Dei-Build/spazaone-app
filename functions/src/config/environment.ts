import * as functions from "firebase-functions";

export type SpazaEnvironment = "local" | "development" | "production";
export type ProviderMode = "disabled" | "stub" | "test" | "live";

export const API_CONTRACT_VERSION = "2026-08-12";
export const FIRESTORE_SCHEMA_VERSION = 2;

function value(name: string): string {
  return String(process.env[name] || "").trim();
}

export function firebaseProjectId(): string {
  return (
    value("GCLOUD_PROJECT") ||
    value("GOOGLE_CLOUD_PROJECT") ||
    value("SPAZAONE_FIREBASE_PROJECT_ID")
  );
}

export function resolveEnvironment(input?: {
  environment?: string;
  projectId?: string;
}): SpazaEnvironment {
  const configured = String(input?.environment ?? value("SPAZAONE_ENVIRONMENT"))
    .trim()
    .toLowerCase();
  const projectId = String(input?.projectId ?? firebaseProjectId()).trim();

  // Unit tests and the local emulator may not expose a cloud project env var.
  // Deployed Functions always do, so absence is safe to interpret as local
  // only when there is also no project identity to cross accidentally.
  const environment = (configured ||
    (!projectId ? "local" : "")) as SpazaEnvironment;
  if (!["local", "development", "production"].includes(environment)) {
    throw new Error("SPAZAONE_ENVIRONMENT_MISSING_OR_INVALID");
  }

  assertProjectMatchesEnvironment(environment, projectId || "demo-spazaone");
  return environment;
}

export function assertProjectMatchesEnvironment(
  environment: SpazaEnvironment,
  projectId: string,
): void {
  const normalized = projectId.trim();
  if (environment === "local" && !normalized.startsWith("demo-")) {
    throw new Error("LOCAL_FIREBASE_PROJECT_INVALID");
  }
  if (
    environment === "development" &&
    normalized !== "spazaone-dev" &&
    normalized !== "spazaone-dev-za"
  ) {
    throw new Error("DEVELOPMENT_FIREBASE_PROJECT_INVALID");
  }
  if (environment === "production" && normalized !== "pasella-ledger") {
    throw new Error("PRODUCTION_FIREBASE_PROJECT_INVALID");
  }
}

export function paystackProviderMode(): ProviderMode {
  const environment = resolveEnvironment();
  const configured = value("PAYSTACK_PROVIDER_MODE").toLowerCase();
  const allowed: ProviderMode[] = ["disabled", "stub", "test", "live"];
  const inferred = environment === "local" && !configured ? "test" : configured;
  if (!allowed.includes(inferred as ProviderMode)) {
    throw new Error("PAYSTACK_PROVIDER_MODE_INVALID");
  }
  const mode = inferred as ProviderMode;
  if (environment === "development" && mode !== "test") {
    throw new Error("DEVELOPMENT_PAYSTACK_MUST_USE_TEST_MODE");
  }
  if (environment === "production" && !["disabled", "live"].includes(mode)) {
    throw new Error("PRODUCTION_PAYSTACK_MODE_INVALID");
  }
  return mode;
}

export function paystackSecret(): string {
  const secret =
    value("PAYSTACK_SECRET_KEY") ||
    value("PAYSTACK_TEST_SECRET_KEY") ||
    (functions.config().paystack?.secret as string | undefined) ||
    "";
  if (!secret) throw new Error("PAYSTACK_SECRET_MISSING");
  const mode = paystackProviderMode();
  if (mode === "disabled" || mode === "stub") {
    throw new Error("PAYSTACK_PROVIDER_DISABLED");
  }
  if (mode === "test" && !secret.startsWith("sk_test_")) {
    throw new Error("PAYSTACK_TEST_KEY_REQUIRED");
  }
  if (mode === "live" && !secret.startsWith("sk_live_")) {
    throw new Error("PAYSTACK_LIVE_KEY_REQUIRED");
  }
  return secret;
}

function providerMode(name: string, fallback: ProviderMode): ProviderMode {
  const configured = value(name).toLowerCase();
  return (["disabled", "stub", "test", "live"] as string[]).includes(configured)
    ? (configured as ProviderMode)
    : fallback;
}

export function publicEnvironmentInfo(): Record<string, unknown> {
  const environment = resolveEnvironment();
  const projectId = firebaseProjectId() || "demo-spazaone";
  return {
    product: "SpazaOne",
    environment,
    firebaseProjectId: projectId,
    apiContractVersion: API_CONTRACT_VERSION,
    firestoreSchemaVersion: FIRESTORE_SCHEMA_VERSION,
    buildCommit: value("BUILD_COMMIT") || value("K_REVISION") || "unknown",
    providerModes: {
      paystack: paystackProviderMode(),
      cj: process.env.CJ_SANDBOX_MODE === "false" ? "live" : "test",
      botpress: providerMode("BOTPRESS_PROVIDER_MODE", "disabled"),
      twilio: providerMode("TWILIO_PROVIDER_MODE", "disabled"),
    },
  };
}

export const getEnvironmentInfo = functions.https.onCall(async () => {
  return publicEnvironmentInfo();
});
