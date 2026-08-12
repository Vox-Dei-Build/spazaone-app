import { createHash } from "crypto";

export const PAYMENT_PURPOSES = [
  "campaign_credit",
  "merchant_order",
  "supplier_order",
  "account_settlement",
  "repayment_installment",
] as const;

export type PaymentPurpose = (typeof PAYMENT_PURPOSES)[number];

export const PAYMENT_STATUSES = [
  "created",
  "initialized",
  "pending",
  "paid",
  "failed",
  "expired",
  "refund_pending",
  "refunded",
  "disputed",
] as const;

export type PaymentStatus = (typeof PAYMENT_STATUSES)[number];

export const MERCHANT_PAYMENT_STATUSES = [
  "not_started",
  "pending_review",
  "enabled",
  "suspended",
] as const;

export type MerchantPaymentStatus = (typeof MERCHANT_PAYMENT_STATUSES)[number];

export type FailureOutcome =
  | "no_charge"
  | "safely_retryable"
  | "paid_and_fulfilled"
  | "paid_refund_pending";

export type MoneySnapshot = {
  currency: "ZAR";
  grossAmountMinor: number;
  platformFeeMinor: number;
  providerFeeMinor: number;
  retainedCostMinor: number;
  platformGrossShareMinor: number;
  merchantGrossShareMinor: number;
  merchantNetProceedsMinor: number;
};

const ALLOWED_TRANSITIONS: Readonly<Record<PaymentStatus, PaymentStatus[]>> = {
  created: ["initialized", "pending", "paid", "failed", "expired"],
  initialized: ["pending", "paid", "failed", "expired"],
  pending: ["paid", "failed", "expired"],
  paid: ["refund_pending", "disputed"],
  failed: [],
  expired: [],
  refund_pending: ["refunded", "disputed"],
  refunded: [],
  disputed: ["refund_pending"],
};

export function requireMinorUnits(value: unknown, field: string): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error(`${field.toUpperCase()}_INVALID`);
  }
  return parsed;
}

export function requirePositiveMinorUnits(
  value: unknown,
  field: string,
): number {
  const parsed = requireMinorUnits(value, field);
  if (parsed <= 0) throw new Error(`${field.toUpperCase()}_INVALID`);
  return parsed;
}

export function isPaymentPurpose(value: unknown): value is PaymentPurpose {
  return PAYMENT_PURPOSES.includes(value as PaymentPurpose);
}

export function isPaymentStatus(value: unknown): value is PaymentStatus {
  return PAYMENT_STATUSES.includes(value as PaymentStatus);
}

export function calculatePlatformFeeMinor(input: {
  grossAmountMinor: number;
  rateBps?: number;
  minimumFeeMinor?: number;
}): number {
  const gross = requirePositiveMinorUnits(
    input.grossAmountMinor,
    "gross_amount",
  );
  const rateBps = requireMinorUnits(input.rateBps ?? 150, "rate_bps");
  const minimum = requireMinorUnits(input.minimumFeeMinor ?? 50, "minimum_fee");
  if (rateBps > 10_000) throw new Error("RATE_BPS_INVALID");
  return Math.max(minimum, Math.round((gross * rateBps) / 10_000));
}

export function buildMoneySnapshot(input: {
  grossAmountMinor: number;
  platformFeeMinor: number;
  providerFeeMinor: number;
  retainedCostMinor?: number;
}): MoneySnapshot {
  const gross = requirePositiveMinorUnits(
    input.grossAmountMinor,
    "gross_amount",
  );
  const platformFee = requireMinorUnits(input.platformFeeMinor, "platform_fee");
  const providerFee = requireMinorUnits(input.providerFeeMinor, "provider_fee");
  const retainedCost = requireMinorUnits(
    input.retainedCostMinor ?? 0,
    "retained_cost",
  );
  const platformGrossShare = platformFee + retainedCost;
  const merchantGrossShare = gross - platformGrossShare;
  const merchantNetProceeds = merchantGrossShare - providerFee;
  if (platformGrossShare > gross) throw new Error("SPLIT_EXCEEDS_GROSS");
  if (merchantNetProceeds < 0) throw new Error("MERCHANT_PROCEEDS_NEGATIVE");
  return {
    currency: "ZAR",
    grossAmountMinor: gross,
    platformFeeMinor: platformFee,
    providerFeeMinor: providerFee,
    retainedCostMinor: retainedCost,
    platformGrossShareMinor: platformGrossShare,
    merchantGrossShareMinor: merchantGrossShare,
    merchantNetProceedsMinor: merchantNetProceeds,
  };
}

export function assertMoneySnapshot(value: MoneySnapshot): void {
  const rebuilt = buildMoneySnapshot(value);
  for (const key of [
    "platformGrossShareMinor",
    "merchantGrossShareMinor",
    "merchantNetProceedsMinor",
  ] as const) {
    if (rebuilt[key] !== value[key]) throw new Error("MONEY_SNAPSHOT_INVALID");
  }
  if (value.currency !== "ZAR") throw new Error("CURRENCY_INVALID");
}

export function assertPaymentTransition(
  current: PaymentStatus,
  next: PaymentStatus,
): void {
  if (current === next) return;
  if (!ALLOWED_TRANSITIONS[current].includes(next)) {
    throw new Error(`PAYMENT_TRANSITION_INVALID:${current}:${next}`);
  }
}

export function failureOutcome(input: {
  charged: boolean;
  retryable: boolean;
  fulfilled: boolean;
  refundPending: boolean;
}): FailureOutcome {
  if (!input.charged) {
    return input.retryable ? "safely_retryable" : "no_charge";
  }
  if (input.fulfilled) return "paid_and_fulfilled";
  if (input.refundPending) return "paid_refund_pending";
  throw new Error("CHARGED_OUTCOME_UNACCOUNTED");
}

export function stableDocumentId(prefix: string, parts: string[]): string {
  const normalized = parts.map((part) => String(part).trim()).join("\u001f");
  if (!normalized.split("\u001f").join("")) throw new Error("ID_INPUT_EMPTY");
  const digest = createHash("sha256").update(normalized).digest("hex");
  return `${prefix}_${digest}`;
}
