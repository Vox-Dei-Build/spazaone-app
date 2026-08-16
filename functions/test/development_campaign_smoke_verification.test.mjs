import assert from "node:assert/strict";
import test from "node:test";

import {
  validateCampaignSmokeVerificationOptions,
  validateCampaignTopupEvidence,
} from "../scripts/verify-development-campaign-topup-smoke.mjs";

test("campaign verification refuses production and non-absolute evidence", () => {
  assert.throws(() =>
    validateCampaignSmokeVerificationOptions([
      "--project",
      "pasella-ledger",
      "--handoff",
      "/tmp/evidence.json",
    ]),
  );
  assert.throws(() =>
    validateCampaignSmokeVerificationOptions([
      "--project",
      "spazaone-dev",
      "--handoff",
      "evidence.json",
    ]),
  );
});

test("campaign verification accepts one fully reconciled credit", () => {
  const intentId = `pi_${"a".repeat(64)}`;
  const reference = "p2-reference";
  const handoff = {
    intentId,
    reference,
    quote: {
      creditAmountMinor: 1000,
      totalChargeMinor: 1025,
      providerFeeMinor: 25,
    },
  };
  const verified = validateCampaignTopupEvidence({
    handoff,
    intent: {
      status: "paid",
      purpose: "campaign_credit",
      merchantId: "dev-seed-merchant",
      expectedAmountMinor: 1025,
      campaignCreditAmountMinor: 1000,
      money: { providerFeeMinor: 25 },
      providerReference: reference,
      appliedProviderEventIds: ["pe_event"],
    },
    event: {
      processingState: "applied",
      eventType: "charge.success",
      intentId,
      reference,
    },
    purchase: {
      intentId,
      creditAmountMinor: 1000,
      grossAmountMinor: 1025,
      reference,
      source: "paystack_v2",
      actualProviderFeeMinor: 25,
    },
    operation: {
      kind: "paystack-topup",
      delta: 10,
      balanceBefore: 250,
      balanceAfter: 260,
    },
    transaction: {
      intentId,
      reference,
      creditAmountMinor: 1000,
      grossAmountMinor: 1025,
      providerFeeMinor: 25,
      status: "success",
      source: "paystack_v2",
    },
    wallet: { virtualBalance: 260 },
    eventCount: 1,
    operatorExists: false,
    authUserExists: false,
  });
  assert.equal(verified.expectedCreditMinor, 1000);
  assert.equal(verified.eventCount, 1);
});

test("campaign verification stops on an unexplained provider-fee cent", () => {
  const intentId = `pi_${"a".repeat(64)}`;
  const reference = "p2-reference";
  assert.throws(
    () =>
      validateCampaignTopupEvidence({
        handoff: {
          intentId,
          reference,
          quote: {
            creditAmountMinor: 1000,
            totalChargeMinor: 1024,
            providerFeeMinor: 24,
          },
        },
        intent: {
          status: "paid",
          purpose: "campaign_credit",
          merchantId: "dev-seed-merchant",
          expectedAmountMinor: 1024,
          campaignCreditAmountMinor: 1000,
          money: { providerFeeMinor: 24 },
          providerReference: reference,
          appliedProviderEventIds: ["pe_event"],
        },
        event: {
          processingState: "applied",
          eventType: "charge.success",
          intentId,
          reference,
        },
        purchase: {
          intentId,
          creditAmountMinor: 1000,
          grossAmountMinor: 1024,
          reference,
          source: "paystack_v2",
          actualProviderFeeMinor: 25,
        },
        operation: {
          kind: "paystack-topup",
          delta: 10,
          balanceBefore: 250,
          balanceAfter: 260,
        },
        transaction: {
          intentId,
          reference,
          creditAmountMinor: 1000,
          grossAmountMinor: 1024,
          providerFeeMinor: 25,
          status: "success",
          source: "paystack_v2",
        },
        wallet: { virtualBalance: 260 },
        eventCount: 1,
        operatorExists: false,
        authUserExists: false,
      }),
    /PROVIDER_FEE_VARIANCE,TOPUP_NET_PROCEEDS_MISMATCH/,
  );
});

test("campaign verification rejects duplicate or incomplete evidence", () => {
  assert.throws(
    () =>
      validateCampaignTopupEvidence({
        handoff: {
          intentId: `pi_${"a".repeat(64)}`,
          reference: "p2-reference",
          quote: {
            creditAmountMinor: 1000,
            totalChargeMinor: 1024,
            providerFeeMinor: 24,
          },
        },
        intent: { status: "initialized", appliedProviderEventIds: [] },
        event: {},
        purchase: {},
        operation: {},
        transaction: {},
        wallet: {},
        eventCount: 2,
        operatorExists: true,
        authUserExists: true,
      }),
    /INTENT_NOT_PAID/,
  );
});
