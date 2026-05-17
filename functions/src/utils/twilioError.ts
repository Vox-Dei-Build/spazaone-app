// functions/src/utils/twilioError.ts
//
// PAS-WA-01 — Normalize Twilio send errors into a shape Pasella can
// persist and surface to support/UX, even when the provider returned
// little or nothing useful.
//
// The Twilio Node SDK throws a `RestException` with `.code`, `.status`,
// `.message`, `.moreInfo`, `.details`. Network/transport failures
// throw plain `Error` (or `AxiosError` when we use REST directly).
// We funnel both into the same `NormalizedSendError` so callers don't
// have to special-case anything downstream.
//
// Intentionally tiny / dependency-free: this file is imported by
// callable functions and webhooks, so keep it cold-start friendly.

export type SendChannel = "whatsapp" | "sms";

export interface NormalizedSendError {
  /** Channel that produced the error. */
  channel: SendChannel;
  /** Twilio numeric error code (as string) when present, else null. */
  providerCode: string | null;
  /** Twilio human-readable message when present, else null. */
  providerMessage: string | null;
  /** Twilio docs URL when present, else null. */
  providerMoreInfo: string | null;
  /** HTTP status from Twilio when present, else null. */
  providerStatus: number | null;
  /**
   * Pasella-side message safe to show to merchants/support. Always
   * populated, even when the provider gave us nothing useful — that
   * is the whole point of this normalizer per PAS-WA-01 AC.
   */
  pasellaMessage: string;
  /**
   * `true` when we had to synthesize the message because the provider
   * gave us no actionable detail. Useful for support filtering and for
   * driving "unknown — please retry" UI states without losing the
   * distinction from genuine provider rejections.
   */
  fallbackUsed: boolean;
  /** Raw stringified error for debugging. Bounded to avoid Firestore bloat. */
  rawSnippet: string;
}

const MAX_RAW = 500;

function pickString(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const s = typeof value === "string" ? value : String(value);
  const trimmed = s.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function pickNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const n = Number(value);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

/**
 * Build a stable, support-friendly error record from whatever the
 * Twilio SDK or transport layer threw. Always returns a value — never
 * throws — so it is safe to call from inside a catch block without
 * adding another try/catch around it.
 */
export function normalizeTwilioError(
  err: unknown,
  channel: SendChannel,
): NormalizedSendError {
  // Best-effort field extraction. Twilio's RestException puts the
  // useful bits at the top level; AxiosError nests them under
  // `.response.data`. Cover both without forcing a type cast that
  // would mislead readers about the shape we actually trust.
  const e = (err ?? {}) as Record<string, unknown>;
  const response = (e.response ?? {}) as Record<string, unknown>;
  const responseData = (response.data ?? {}) as Record<string, unknown>;

  const providerCode =
    pickString(e.code) ??
    pickString(responseData.code) ??
    pickString(responseData.error_code);
  // For AxiosError-shaped failures the top-level `message` is the
  // generic "Request failed with status code N" — the *actual*
  // Twilio explanation lives under `response.data.message`. Prefer
  // the nested one when it exists, falling back to the SDK-style
  // top-level message for `RestException`.
  const providerMessage =
    pickString(responseData.message) ??
    pickString(responseData.error_message) ??
    pickString(e.message);
  const providerMoreInfo =
    pickString(e.moreInfo) ??
    pickString(responseData.more_info);
  const providerStatus =
    pickNumber(e.status) ??
    pickNumber(response.status) ??
    pickNumber(responseData.status);

  let pasellaMessage: string;
  let fallbackUsed = false;

  if (providerMessage && providerCode) {
    pasellaMessage = `${channel === "whatsapp" ? "WhatsApp" : "SMS"} send failed (Twilio ${providerCode}): ${providerMessage}`;
  } else if (providerMessage) {
    pasellaMessage = `${channel === "whatsapp" ? "WhatsApp" : "SMS"} send failed: ${providerMessage}`;
  } else if (providerCode) {
    pasellaMessage = `${channel === "whatsapp" ? "WhatsApp" : "SMS"} send failed (Twilio ${providerCode}). No further detail returned by provider.`;
  } else {
    // Pure fallback path required by PAS-WA-01 AC #3. Provider gave
    // us nothing actionable, so we say so explicitly rather than
    // hiding it behind a generic "send failed".
    fallbackUsed = true;
    pasellaMessage =
      channel === "whatsapp"
        ? "WhatsApp template send failed and no provider error detail was returned. Treat as transient — retry, then contact support if it persists."
        : "SMS send failed and no provider error detail was returned. Treat as transient — retry, then contact support if it persists.";
  }

  let rawSnippet: string;
  try {
    rawSnippet = JSON.stringify(
      err,
      Object.getOwnPropertyNames(err ?? {}),
    ).slice(0, MAX_RAW);
  } catch {
    rawSnippet = String(err).slice(0, MAX_RAW);
  }

  return {
    channel,
    providerCode,
    providerMessage,
    providerMoreInfo,
    providerStatus,
    pasellaMessage,
    fallbackUsed,
    rawSnippet,
  };
}
