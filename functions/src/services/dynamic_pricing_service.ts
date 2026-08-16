import * as admin from "firebase-admin";

export type RemoteConfigTemplateLike = {
  parameters?: Record<string, unknown>;
  parameterGroups?: Record<string, { parameters?: Record<string, unknown> }>;
};

export type MessagingPricingSnapshotV1 = {
  schemaVersion: 1;
  currency: "ZAR";
  smsCustomerMinor: number;
  smsPaymentMinor: number;
  whatsappUtilityMinor: number;
  whatsappPromotionMinor: number;
};

export class MessagingPricingUnavailableError extends Error {
  constructor(message = "Messaging pricing is unavailable.") {
    super(message);
    this.name = "MessagingPricingUnavailableError";
  }
}

function parameter(template: RemoteConfigTemplateLike, key: string): unknown {
  const direct = template.parameters?.[key];
  if (direct) return direct;
  for (const group of Object.values(template.parameterGroups ?? {})) {
    const grouped = group.parameters?.[key];
    if (grouped) return grouped;
  }
  return undefined;
}

function numberValue(
  template: RemoteConfigTemplateLike,
  key: string,
  { allowZero = false }: { allowZero?: boolean } = {},
): number {
  const raw = (
    parameter(template, key) as
      | { defaultValue?: { value?: unknown; defaultValue?: unknown } }
      | undefined
  )?.defaultValue;
  const candidate = raw?.value ?? raw?.defaultValue;
  const value = Number(candidate);
  const lowerBoundOk = allowZero ? value >= 0 : value > 0;
  if (!Number.isFinite(value) || !lowerBoundOk) {
    throw new MessagingPricingUnavailableError(
      `Required messaging price input ${key} is missing or invalid.`,
    );
  }
  return value;
}

function priceMinor(
  template: RemoteConfigTemplateLike,
  usdKey: string,
  markupKey: string,
): number {
  const usd = numberValue(template, usdKey);
  const markup = numberValue(template, markupKey, { allowZero: true });
  const exchangeRate = numberValue(template, "USD_ZAR_EXCHANGE_RATE");
  const minor = Math.round(usd * exchangeRate * (1 + markup / 100) * 100);
  if (!Number.isSafeInteger(minor) || minor <= 0) {
    throw new MessagingPricingUnavailableError();
  }
  return minor;
}

/**
 * Builds the only buyer-safe messaging pricing projection exposed to clients.
 * Missing, malformed and zero provider inputs fail closed instead of turning
 * a paid send into a free message.
 */
export function messagingPricingSnapshotV1(
  template: RemoteConfigTemplateLike,
): MessagingPricingSnapshotV1 {
  return {
    schemaVersion: 1,
    currency: "ZAR",
    smsCustomerMinor: priceMinor(
      template,
      "USD_SMS_REMINDER_PRICE",
      "MARKUP_SMS_PERCENTAGE",
    ),
    smsPaymentMinor: priceMinor(
      template,
      "USD_SMS_PAYMENT_PRICE",
      "MARKUP_SMS_PERCENTAGE",
    ),
    whatsappUtilityMinor: priceMinor(
      template,
      "USD_WHATSAPP_UTILITY_PRICE",
      "MARKUP_WHATSAPP_PERCENTAGE",
    ),
    whatsappPromotionMinor: priceMinor(
      template,
      "USD_WHATSAPP_PROMOTIONAL_PRICE",
      "MARKUP_PROMOTIONAL_PERCENTAGE",
    ),
  };
}

/** Server-side pricing authority shared by send paths and the app projection. */
export class DynamicPricingService {
  private readonly snapshot: MessagingPricingSnapshotV1;

  private constructor(template: admin.remoteConfig.RemoteConfigTemplate) {
    this.snapshot = messagingPricingSnapshotV1(template);
  }

  static async initialize(): Promise<DynamicPricingService> {
    const template = await admin.remoteConfig().getTemplate();
    return new DynamicPricingService(template);
  }

  get buyerSafeSnapshot(): MessagingPricingSnapshotV1 {
    return { ...this.snapshot };
  }

  get smsReminderTemplatePrice(): number {
    return this.snapshot.smsCustomerMinor / 100;
  }

  get smsPaymentTemplatePrice(): number {
    return this.snapshot.smsPaymentMinor / 100;
  }

  get whatsappUtilityPrice(): number {
    return this.snapshot.whatsappUtilityMinor / 100;
  }

  get whatsappPromotionPrice(): number {
    return this.snapshot.whatsappPromotionMinor / 100;
  }
}
