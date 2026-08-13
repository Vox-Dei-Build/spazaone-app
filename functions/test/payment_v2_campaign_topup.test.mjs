import assert from "node:assert/strict";
import test from "node:test";
import {
  CAMPAIGN_TOPUP_CHANNELS,
  campaignTopupProviderFeeMinor,
  quoteCampaignTopup,
  publicCampaignTopupStatus,
} from "../lib/payments/v2/campaignTopup.js";

test("campaign top-up quote credits the exact selected value", () => {
  for (const channel of CAMPAIGN_TOPUP_CHANNELS) {
    for (const creditAmountMinor of [100, 999, 1_000, 7_500, 10_000, 999_999]) {
      const quote = quoteCampaignTopup({ creditAmountMinor, channel });
      assert.equal(quote.platformFeeMinor, 0);
      assert.equal(
        quote.totalChargeMinor - quote.providerFeeMinor,
        creditAmountMinor,
      );
      assert.equal(
        campaignTopupProviderFeeMinor({
          grossAmountMinor: quote.totalChargeMinor,
          channel,
        }),
        quote.providerFeeMinor,
      );
    }
  }
});

test("EFT and Capitec use 2% excluding VAT with no flat fee", () => {
  assert.equal(
    campaignTopupProviderFeeMinor({
      grossAmountMinor: 10_000,
      channel: "eft",
    }),
    230,
  );
  assert.equal(
    campaignTopupProviderFeeMinor({
      grossAmountMinor: 10_000,
      channel: "capitec_pay",
    }),
    230,
  );
  assert.equal(
    campaignTopupProviderFeeMinor({
      grossAmountMinor: 1_025,
      channel: "eft",
    }),
    25,
  );
  assert.deepEqual(
    quoteCampaignTopup({ creditAmountMinor: 1_000, channel: "eft" }),
    {
      currency: "ZAR",
      channel: "eft",
      creditAmountMinor: 1_000,
      providerFeeMinor: 25,
      totalChargeMinor: 1_025,
      platformFeeMinor: 0,
      feePolicy: {
        rateBpsExVat: 200,
        flatMinorExVat: 0,
        flatWaiverBelowMinor: null,
        vatBps: 1500,
        source: "paystack_za_public_2026_08",
      },
    },
  );
});

test("QR applies the public local tariff and waives R1 below R10", () => {
  assert.equal(
    campaignTopupProviderFeeMinor({ grossAmountMinor: 999, channel: "qr" }),
    34,
  );
  assert.equal(
    campaignTopupProviderFeeMinor({ grossAmountMinor: 1_000, channel: "qr" }),
    149,
  );
});

test("card top-ups fail closed because local versus international is unknown", () => {
  assert.throws(
    () => quoteCampaignTopup({ creditAmountMinor: 10_000, channel: "card" }),
    /TOPUP_CHANNEL_INVALID/,
  );
});

test("top-up status celebrates only after the webhook business projection exists", () => {
  assert.equal(
    publicCampaignTopupStatus({ intentStatus: "paid", purchaseExists: false }),
    "checking",
  );
  assert.equal(
    publicCampaignTopupStatus({ intentStatus: "paid", purchaseExists: true }),
    "paid",
  );
  assert.equal(
    publicCampaignTopupStatus({
      intentStatus: "refund_pending",
      purchaseExists: true,
    }),
    "refund_pending",
  );
  assert.equal(
    publicCampaignTopupStatus({
      intentStatus: "refunded",
      purchaseExists: true,
    }),
    "refunded",
  );
});
