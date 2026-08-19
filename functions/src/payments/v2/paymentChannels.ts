import { PaymentPurpose } from "./domain";

export const PAYSTACK_PAYMENT_CHANNELS = [
  "card",
  "eft",
  "capitec_pay",
  "qr",
] as const;

export type PaystackPaymentChannel = (typeof PAYSTACK_PAYMENT_CHANNELS)[number];

const PRODUCTION_SAFE_DEFAULT_CHANNELS: readonly PaystackPaymentChannel[] = [
  "card",
  "qr",
];

function isPaymentChannel(value: unknown): value is PaystackPaymentChannel {
  return PAYSTACK_PAYMENT_CHANNELS.includes(value as PaystackPaymentChannel);
}

/**
 * Resolve provider-approved channels from the global payment configuration.
 *
 * EFT and Capitec Pay require a separate Paystack approval in South Africa.
 * A missing production configuration therefore fails closed to the two
 * channels that do not depend on that approval. Development and local test
 * environments retain every channel so provider sandboxes can exercise them.
 */
export function configuredPaystackChannels(input: {
  environment: string;
  configured: unknown;
}): PaystackPaymentChannel[] {
  const configuredValues = Array.isArray(input.configured)
    ? input.configured
    : input.configured && typeof input.configured === "object"
      ? Object.entries(input.configured as Record<string, unknown>)
          .filter(([, enabled]) => enabled === true)
          .map(([channel]) => channel)
      : null;
  const source =
    configuredValues ??
    (input.environment === "production"
      ? PRODUCTION_SAFE_DEFAULT_CHANNELS
      : PAYSTACK_PAYMENT_CHANNELS);
  const enabled = new Set(source.filter(isPaymentChannel));
  return PAYSTACK_PAYMENT_CHANNELS.filter((channel) => enabled.has(channel));
}

export function paymentChannelsForPurpose(
  purpose: PaymentPurpose,
  channels: readonly PaystackPaymentChannel[],
): PaystackPaymentChannel[] {
  // Card campaign top-ups are intentionally unsupported because the hosted
  // flow cannot quote the exact local/international card fee in advance.
  return channels.filter(
    (channel) => purpose !== "campaign_credit" || channel !== "card",
  );
}
