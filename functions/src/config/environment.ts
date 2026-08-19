import * as functions from "firebase-functions";

export type SpazaEnvironment = "local" | "development" | "production";
export type ProviderMode = "disabled" | "stub" | "test" | "live";

export const PAYSTACK_ACCOUNT_PAYMENT_CANARY_SCOPE = "account_payment_canary";
export const PAYSTACK_MERCHANT_PAYMENT_CANARY_SCOPE = "merchant_payment_canary";

const PAYSTACK_MERCHANT_PAYMENT_CANARY_PURPOSES = new Set([
  "campaign_credit",
  "merchant_order",
  "supplier_order",
  "account_settlement",
  "repayment_installment",
]);

export type PaystackPaymentContext = {
  merchantId: string;
  purpose: string;
};

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

function configuredPaystackSecret(): string {
  const secret =
    value("PAYSTACK_SECRET_KEY") ||
    value("PAYSTACK_TEST_SECRET_KEY") ||
    (functions.config().paystack?.secret as string | undefined) ||
    "";
  if (!secret) throw new Error("PAYSTACK_SECRET_MISSING");
  return secret;
}

function assertPaystackSecretMatchesEnvironment(secret: string): void {
  const environment = resolveEnvironment();
  if (environment === "development" && !secret.startsWith("sk_test_")) {
    throw new Error("PAYSTACK_TEST_KEY_REQUIRED");
  }
  if (environment === "production" && !secret.startsWith("sk_live_")) {
    throw new Error("PAYSTACK_LIVE_KEY_REQUIRED");
  }
}

/**
 * Narrow production canary for merchant account-settlement links.
 *
 * This deliberately supports one exact merchant ID and one hard-coded payment
 * purpose. The separate boolean makes an accidentally populated merchant ID
 * inert, while production-only enforcement prevents this escape hatch from
 * weakening development or local environment boundaries.
 */
export function paystackAccountPaymentCanaryEnabled(
  input: PaystackPaymentContext,
): boolean {
  if (resolveEnvironment() !== "production") return false;
  if (
    value("PAYSTACK_ACCOUNT_PAYMENT_CANARY_ENABLED").toLowerCase() !== "true"
  ) {
    return false;
  }
  const configuredMerchantId = value(
    "PAYSTACK_ACCOUNT_PAYMENT_CANARY_MERCHANT_ID",
  );
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(configuredMerchantId)) return false;
  return (
    input.purpose === "account_settlement" &&
    input.merchantId === configuredMerchantId
  );
}

/**
 * Production-only, exact-merchant canary for every supported payment purpose.
 *
 * This is deliberately separate from the global provider and Payments V2
 * switches. Enabling it cannot make another merchant ready, and the normal
 * emergency suspension, merchant status and per-merchant capability checks
 * remain authoritative.
 */
export function paystackMerchantPaymentCanaryEnabled(
  input: PaystackPaymentContext,
): boolean {
  if (resolveEnvironment() !== "production") return false;
  if (
    value("PAYSTACK_MERCHANT_PAYMENT_CANARY_ENABLED").toLowerCase() !== "true"
  ) {
    return false;
  }
  const configuredMerchantId = value(
    "PAYSTACK_MERCHANT_PAYMENT_CANARY_MERCHANT_ID",
  );
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(configuredMerchantId)) return false;
  return (
    input.merchantId === configuredMerchantId &&
    PAYSTACK_MERCHANT_PAYMENT_CANARY_PURPOSES.has(input.purpose)
  );
}

/** Any narrow production payment canary that applies to this exact context. */
export function paystackPaymentCanaryEnabled(
  input: PaystackPaymentContext,
): boolean {
  return (
    paystackMerchantPaymentCanaryEnabled(input) ||
    paystackAccountPaymentCanaryEnabled(input)
  );
}

/** Immutable scope recorded on the intent before provider initialization. */
export function paystackPaymentActivationScope(
  input: PaystackPaymentContext,
): string {
  if (paystackMerchantPaymentCanaryEnabled(input)) {
    return PAYSTACK_MERCHANT_PAYMENT_CANARY_SCOPE;
  }
  if (paystackAccountPaymentCanaryEnabled(input)) {
    return PAYSTACK_ACCOUNT_PAYMENT_CANARY_SCOPE;
  }
  return "global";
}

/** Verifies the immutable intent binding before a disabled-mode webhook runs. */
export function paystackCanaryIntentBindingValid(input: {
  metadataMerchantId: unknown;
  metadataPurpose: unknown;
  intentMerchantId: unknown;
  intentPurpose: unknown;
  intentProviderMode: unknown;
  intentActivationScope: unknown;
}): boolean {
  const merchantId = String(input.metadataMerchantId ?? "").trim();
  const purpose = String(input.metadataPurpose ?? "")
    .trim()
    .toLowerCase();
  const activationScope = paystackPaymentActivationScope({
    merchantId,
    purpose,
  });
  return (
    activationScope !== "global" &&
    String(input.intentMerchantId ?? "") === merchantId &&
    String(input.intentPurpose ?? "") === purpose &&
    String(input.intentProviderMode ?? "") === "live" &&
    String(input.intentActivationScope ?? "") === activationScope
  );
}

/** Effective provider mode for a newly initialized payment intent. */
export function paystackPaymentProviderMode(
  input: PaystackPaymentContext,
): ProviderMode {
  const mode = paystackProviderMode();
  if (mode === "disabled" && paystackPaymentCanaryEnabled(input)) {
    return "live";
  }
  return mode;
}

/**
 * Fund-moving credential accessor for the global payment lane or the exact
 * account-payment canary. Read-only and settlement-verification endpoints use
 * their own accessors and are not affected by this gate.
 */
export function paystackPaymentSecret(input: PaystackPaymentContext): string {
  const secret = configuredPaystackSecret();
  const mode = paystackPaymentProviderMode(input);
  if (mode === "disabled" || mode === "stub") {
    throw new Error("PAYSTACK_PROVIDER_DISABLED");
  }
  assertPaystackSecretMatchesEnvironment(secret);
  if (mode === "test" && !secret.startsWith("sk_test_")) {
    throw new Error("PAYSTACK_TEST_KEY_REQUIRED");
  }
  if (mode === "live" && !secret.startsWith("sk_live_")) {
    throw new Error("PAYSTACK_LIVE_KEY_REQUIRED");
  }
  return secret;
}

/**
 * Provider credential for read-only catalogue requests.
 *
 * The production payment kill switch blocks charges and other fund-moving
 * operations. It must not break safe provider metadata needed to complete a
 * merchant's setup form. This accessor remains environment-bound and must
 * never be used for a financial operation.
 */
export function paystackReadOnlySecret(): string {
  const secret = configuredPaystackSecret();
  assertPaystackSecretMatchesEnvironment(secret);
  return secret;
}

/**
 * Provider credential for the separately governed settlement-verification
 * lane.
 *
 * These endpoints may validate a preauthorized bank account and stage or
 * activate its Paystack subaccount, but they never create a charge or move
 * funds. They remain protected by merchant access, App Check, an operations
 * authorization, attempt budgets, final operations review and the Firestore
 * settlement-verification suspension switch. The broader
 * PAYSTACK_PROVIDER_MODE kill switch therefore stays authoritative for every
 * payment, top-up, settlement, supplier-order and refund flow.
 */
export function paystackSettlementVerificationSecret(): string {
  const secret = configuredPaystackSecret();
  assertPaystackSecretMatchesEnvironment(secret);
  return secret;
}

export function paystackSecret(): string {
  const secret = configuredPaystackSecret();
  const mode = paystackProviderMode();
  if (mode === "disabled" || mode === "stub") {
    throw new Error("PAYSTACK_PROVIDER_DISABLED");
  }
  assertPaystackSecretMatchesEnvironment(secret);
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
