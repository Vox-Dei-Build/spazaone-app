import { functions } from "../../config/main";

const DEFAULT_RECENT_AUTH_SECONDS = 5 * 60;
const MAX_CLOCK_SKEW_SECONDS = 60;

export type PaymentAdminAccessInput = {
  authenticated: boolean;
  spazaAdmin: boolean;
  appCheckVerified: boolean;
  appCheckAlreadyConsumed: boolean;
  email: unknown;
  emailVerified: unknown;
  signInProvider: unknown;
  authTimeSeconds: unknown;
  nowSeconds: number;
  origin: unknown;
  allowedEmails: string[];
  allowedOrigins: string[];
  requireRecentAuth: boolean;
  recentAuthSeconds?: number;
};

export type PaymentAdminAccessDecision =
  | { allowed: true }
  | {
      allowed: false;
      code: "unauthenticated" | "permission-denied" | "failed-precondition";
      reason: string;
    };

function normalizedEmail(value: unknown): string {
  return String(value ?? "")
    .trim()
    .toLowerCase();
}

function normalizedOrigin(value: unknown): string {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  try {
    return new URL(raw).origin.toLowerCase();
  } catch (_) {
    return "";
  }
}

function configuredList(value: string | undefined): string[] {
  return String(value ?? "")
    .split(",")
    .map((entry) => entry.trim().toLowerCase())
    .filter(Boolean);
}

export function paymentAdminAccessDecision(
  input: PaymentAdminAccessInput,
): PaymentAdminAccessDecision {
  if (!input.authenticated) {
    return {
      allowed: false,
      code: "unauthenticated",
      reason: "PAYMENT_ADMIN_AUTH_REQUIRED",
    };
  }
  if (!input.appCheckVerified) {
    return {
      allowed: false,
      code: "failed-precondition",
      reason: "PAYMENT_ADMIN_APP_CHECK_REQUIRED",
    };
  }
  if (input.appCheckAlreadyConsumed) {
    return {
      allowed: false,
      code: "permission-denied",
      reason: "PAYMENT_ADMIN_APP_CHECK_REPLAYED",
    };
  }
  if (!input.spazaAdmin) {
    return {
      allowed: false,
      code: "permission-denied",
      reason: "PAYMENT_ADMIN_CLAIM_REQUIRED",
    };
  }

  const allowedEmails = input.allowedEmails
    .map(normalizedEmail)
    .filter(Boolean);
  const email = normalizedEmail(input.email);
  if (
    allowedEmails.length === 0 ||
    input.emailVerified !== true ||
    !email ||
    !allowedEmails.includes(email)
  ) {
    return {
      allowed: false,
      code: "permission-denied",
      reason: "PAYMENT_ADMIN_EMAIL_NOT_ALLOWED",
    };
  }
  if (String(input.signInProvider ?? "") !== "google.com") {
    return {
      allowed: false,
      code: "permission-denied",
      reason: "PAYMENT_ADMIN_GOOGLE_SIGN_IN_REQUIRED",
    };
  }

  const allowedOrigins = input.allowedOrigins
    .map(normalizedOrigin)
    .filter(Boolean);
  const origin = normalizedOrigin(input.origin);
  if (
    allowedOrigins.length === 0 ||
    !origin ||
    !allowedOrigins.includes(origin)
  ) {
    return {
      allowed: false,
      code: "permission-denied",
      reason: "PAYMENT_ADMIN_ORIGIN_NOT_ALLOWED",
    };
  }

  if (input.requireRecentAuth) {
    const authTimeSeconds = Number(input.authTimeSeconds);
    const maximumAge = input.recentAuthSeconds ?? DEFAULT_RECENT_AUTH_SECONDS;
    const age = input.nowSeconds - authTimeSeconds;
    if (
      !Number.isSafeInteger(authTimeSeconds) ||
      age < -MAX_CLOCK_SKEW_SECONDS ||
      age > maximumAge
    ) {
      return {
        allowed: false,
        code: "failed-precondition",
        reason: "PAYMENT_ADMIN_RECENT_AUTH_REQUIRED",
      };
    }
  }

  return { allowed: true };
}

export function requirePaymentAdmin(
  context: functions.https.CallableContext,
  options: { requireRecentAuth?: boolean } = {},
): string {
  const authentication = context.auth;
  const token = authentication?.token;
  const firebaseClaim = token?.firebase as
    | { sign_in_provider?: unknown }
    | undefined;
  const decision = paymentAdminAccessDecision({
    authenticated: Boolean(authentication),
    spazaAdmin: token?.spazaAdmin === true,
    appCheckVerified: Boolean(context.app),
    appCheckAlreadyConsumed: context.app?.alreadyConsumed === true,
    email: token?.email,
    emailVerified: token?.email_verified,
    signInProvider: firebaseClaim?.sign_in_provider,
    authTimeSeconds: token?.auth_time,
    nowSeconds: Math.floor(Date.now() / 1000),
    origin: context.rawRequest.get("origin"),
    allowedEmails: configuredList(process.env.PAYMENT_ADMIN_ALLOWED_EMAILS),
    allowedOrigins: configuredList(process.env.PAYMENT_ADMIN_ALLOWED_ORIGINS),
    requireRecentAuth: options.requireRecentAuth !== false,
  });
  if (!decision.allowed) {
    console.warn("[payments-v2] payment admin access rejected", {
      reason: decision.reason,
      appCheck: Boolean(context.app),
      originPresent: Boolean(context.rawRequest.get("origin")),
    });
    throw new functions.https.HttpsError(
      decision.code,
      decision.reason === "PAYMENT_ADMIN_RECENT_AUTH_REQUIRED"
        ? "Sign in with Google again before approving a payment change."
        : "Payment administration access was denied.",
    );
  }
  if (!authentication) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Payment administration access was denied.",
    );
  }
  return authentication.uid;
}
