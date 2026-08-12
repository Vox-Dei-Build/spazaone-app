import axios from "axios";
import { FieldValue } from "firebase-admin/firestore";
import { createHash } from "crypto";
import { db, functions } from "../../config/main";
import { paystackSecret } from "../../config/environment";
import { authenticateFirebaseRequest } from "../../security/requestAuth";
import { assertStoreAccess, requireStoreId } from "../../stores/storeAccess";
import {
  campaignWalletRef,
  mutateCampaignCredits,
  resolveCampaignWallet,
} from "../../wallet/campaignCredits";
import { buildMoneySnapshot, requirePositiveMinorUnits } from "./domain";
import {
  createPaymentIntentV2,
  providerEventDocumentId,
  recordProviderEventV2,
} from "./financialCore";
import { paymentReadiness } from "./readiness";

export const CAMPAIGN_TOPUP_CHANNELS = ["eft", "capitec_pay", "qr"] as const;
export type CampaignTopupChannel = (typeof CAMPAIGN_TOPUP_CHANNELS)[number];

type FeePolicy = {
  rateBpsExVat: number;
  flatMinorExVat: number;
  flatWaiverBelowMinor: number | null;
  vatBps: number;
};

const MAX_CREDIT_MINOR = 10_000_000;
const FEE_POLICIES: Record<CampaignTopupChannel, FeePolicy> = {
  eft: {
    rateBpsExVat: 200,
    flatMinorExVat: 0,
    flatWaiverBelowMinor: null,
    vatBps: 1500,
  },
  capitec_pay: {
    rateBpsExVat: 200,
    flatMinorExVat: 0,
    flatWaiverBelowMinor: null,
    vatBps: 1500,
  },
  qr: {
    rateBpsExVat: 290,
    flatMinorExVat: 100,
    flatWaiverBelowMinor: 1000,
    vatBps: 1500,
  },
};

function isCampaignTopupChannel(value: unknown): value is CampaignTopupChannel {
  return CAMPAIGN_TOPUP_CHANNELS.includes(value as CampaignTopupChannel);
}

function ceilRational(numerator: number, denominator: number): number {
  if (!Number.isSafeInteger(numerator) || numerator < 0) {
    throw new Error("FEE_CALCULATION_OVERFLOW");
  }
  return Math.ceil(numerator / denominator);
}

/**
 * Current South African public Paystack tariff, calculated in cents only.
 * Card top-ups are deliberately excluded: a hosted card checkout cannot know
 * whether the eventual card is local (2.9%) or international (3.1%) before
 * charging, so it cannot promise an exact pass-through quote.
 */
export function campaignTopupProviderFeeMinor(input: {
  grossAmountMinor: number;
  channel: CampaignTopupChannel;
}): number {
  const gross = requirePositiveMinorUnits(
    input.grossAmountMinor,
    "gross_amount",
  );
  const policy = FEE_POLICIES[input.channel];
  if (!policy) throw new Error("TOPUP_CHANNEL_INVALID");
  const flat =
    policy.flatWaiverBelowMinor != null && gross < policy.flatWaiverBelowMinor
      ? 0
      : policy.flatMinorExVat;
  const feeExVatNumerator = gross * policy.rateBpsExVat + flat * 10_000;
  // Paystack's sandbox evidence rounds the processor fee to a cent before
  // calculating VAT, then rounds VAT to a cent as a separate component. Keep
  // those two provider-visible cent boundaries explicit: applying one final
  // rounding step underquoted a R10 EFT top-up by one cent (24c vs 25c).
  const feeExVatMinor = ceilRational(feeExVatNumerator, 10_000);
  const vatMinor = ceilRational(feeExVatMinor * policy.vatBps, 10_000);
  return feeExVatMinor + vatMinor;
}

export type CampaignTopupQuote = {
  currency: "ZAR";
  channel: CampaignTopupChannel;
  creditAmountMinor: number;
  providerFeeMinor: number;
  totalChargeMinor: number;
  platformFeeMinor: 0;
  feePolicy: FeePolicy & { source: "paystack_za_public_2026_08" };
};

export function quoteCampaignTopup(input: {
  creditAmountMinor: number;
  channel: CampaignTopupChannel;
}): CampaignTopupQuote {
  const credit = requirePositiveMinorUnits(
    input.creditAmountMinor,
    "credit_amount",
  );
  if (credit > MAX_CREDIT_MINOR) throw new Error("CREDIT_AMOUNT_TOO_LARGE");
  if (!isCampaignTopupChannel(input.channel)) {
    throw new Error("TOPUP_CHANNEL_INVALID");
  }

  // Find the smallest charge whose post-fee amount equals the selected
  // campaign credit exactly. The tariff is monotonic, so binary search is
  // deterministic and avoids floating-point gross-up errors.
  let low = credit;
  let high = credit + Math.max(10_000, Math.ceil(credit / 4));
  while (
    high -
      campaignTopupProviderFeeMinor({
        grossAmountMinor: high,
        channel: input.channel,
      }) <
    credit
  ) {
    high *= 2;
    if (!Number.isSafeInteger(high) || high > MAX_CREDIT_MINOR * 2) {
      throw new Error("TOPUP_GROSS_UP_INVALID");
    }
  }
  while (low < high) {
    const midpoint = Math.floor((low + high) / 2);
    const net =
      midpoint -
      campaignTopupProviderFeeMinor({
        grossAmountMinor: midpoint,
        channel: input.channel,
      });
    if (net < credit) low = midpoint + 1;
    else high = midpoint;
  }
  const calculatedFee = campaignTopupProviderFeeMinor({
    grossAmountMinor: low,
    channel: input.channel,
  });
  if (low - calculatedFee !== credit) {
    throw new Error("TOPUP_EXACT_GROSS_UP_UNAVAILABLE");
  }
  return {
    currency: "ZAR",
    channel: input.channel,
    creditAmountMinor: credit,
    providerFeeMinor: calculatedFee,
    totalChargeMinor: low,
    platformFeeMinor: 0,
    feePolicy: {
      ...FEE_POLICIES[input.channel],
      source: "paystack_za_public_2026_08",
    },
  };
}

function publicError(error: unknown): { status: number; message: string } {
  if (error instanceof functions.https.HttpsError) {
    const status =
      error.code === "unauthenticated"
        ? 401
        : error.code === "permission-denied"
          ? 403
          : error.code === "failed-precondition"
            ? 409
            : 400;
    return { status, message: error.message };
  }
  const code = error instanceof Error ? error.message : "";
  const known: Record<string, [number, string]> = {
    CREDIT_AMOUNT_INVALID: [400, "Enter a valid campaign credit amount."],
    CREDIT_AMOUNT_TOO_LARGE: [400, "Campaign credit amount is too large."],
    TOPUP_CHANNEL_INVALID: [400, "Choose an available payment method."],
    TOPUP_EXACT_GROSS_UP_UNAVAILABLE: [
      409,
      "That exact top-up is unavailable.",
    ],
    PAYMENT_CAPABILITY_DISABLED: [409, "Online top-ups are not available yet."],
    PAYMENT_INITIALIZATION_IN_PROGRESS: [
      409,
      "Payment setup is already in progress.",
    ],
  };
  const mapped = known[code];
  return mapped
    ? { status: mapped[0], message: mapped[1] }
    : { status: 500, message: "Payment setup failed." };
}

async function authenticatedQuote(req: functions.https.Request, res: any) {
  const uid = await authenticateFirebaseRequest(req, res);
  if (!uid) return null;
  const merchantId = requireStoreId(req.body?.storeId ?? req.body?.merchantId);
  await assertStoreAccess(uid, merchantId);
  const readiness = await paymentReadiness({
    merchantId,
    purpose: "campaign_credit",
  });
  if (!readiness.enabled) throw new Error("PAYMENT_CAPABILITY_DISABLED");
  const channel = String(req.body?.channel ?? "").trim();
  if (!isCampaignTopupChannel(channel))
    throw new Error("TOPUP_CHANNEL_INVALID");
  return {
    uid,
    merchantId,
    channel,
    quote: quoteCampaignTopup({
      creditAmountMinor: Number(req.body?.creditAmountMinor),
      channel,
    }),
  };
}

export const getCampaignTopupQuoteV2 = functions.https.onRequest(
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const result = await authenticatedQuote(req, res);
      if (!result) return;
      res.status(200).json(result.quote);
    } catch (error) {
      const response = publicError(error);
      res.status(response.status).json({ error: response.message });
    }
  },
);

function paymentReference(intentId: string): string {
  return `p2-${createHash("sha256").update(intentId).digest("hex").slice(0, 36)}`;
}

export const createCampaignTopupV2 = functions
  .runWith({ secrets: ["PAYSTACK_SECRET_KEY"] })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const prepared = await authenticatedQuote(req, res);
      if (!prepared) return;
      const email = String(req.body?.email ?? "")
        .trim()
        .toLowerCase();
      if (!/^\S+@\S+\.\S+$/.test(email)) {
        res.status(400).json({ error: "Enter a valid email address." });
        return;
      }
      const idempotencyKey = String(req.body?.idempotencyKey ?? "").trim();
      if (!/^[A-Za-z0-9:_-]{12,180}$/.test(idempotencyKey)) {
        res.status(400).json({ error: "A valid payment attempt is required." });
        return;
      }
      const wallet = await resolveCampaignWallet(prepared.merchantId);
      const money = buildMoneySnapshot({
        grossAmountMinor: prepared.quote.totalChargeMinor,
        platformFeeMinor: 0,
        providerFeeMinor: prepared.quote.providerFeeMinor,
      });
      const created = await createPaymentIntentV2({
        merchantId: prepared.merchantId,
        purpose: "campaign_credit",
        idempotencyKey,
        expectedAmountMinor: prepared.quote.totalChargeMinor,
        businessBinding: {
          type: "campaign_wallet",
          id: wallet.walletStoreId,
        },
        money,
        initiatedBy: prepared.uid,
      });
      const intentRef = db.doc(`paymentIntents/${created.intentId}`);
      const reference = paymentReference(created.intentId);
      const claimId = createHash("sha256")
        .update(`${created.intentId}:${Date.now()}:${prepared.uid}`)
        .digest("hex");
      const claim = await db.runTransaction(async (tx) => {
        const intent = await tx.get(intentRef);
        const data = intent.data() ?? {};
        if (data.status === "initialized") {
          return {
            initialized: true,
            authorizationUrl: String(data.authorizationUrl ?? ""),
            reference: String(data.providerReference ?? ""),
          };
        }
        const leaseUntilMs = Number(data.initializationLeaseUntilMs ?? 0);
        if (
          data.initializationState === "processing" &&
          leaseUntilMs > Date.now()
        ) {
          throw new Error("PAYMENT_INITIALIZATION_IN_PROGRESS");
        }
        tx.update(intentRef, {
          initializationState: "processing",
          initializationClaimId: claimId,
          initializationLeaseUntilMs: Date.now() + 45_000,
          initializationAttempts: FieldValue.increment(1),
          selectedChannel: prepared.channel,
          campaignCreditAmountMinor: prepared.quote.creditAmountMinor,
          campaignWalletStoreId: wallet.walletStoreId,
          campaignWalletShared: wallet.shared,
          feePolicy: prepared.quote.feePolicy,
          updatedAt: FieldValue.serverTimestamp(),
        });
        return { initialized: false, authorizationUrl: "", reference };
      });
      if (claim.initialized) {
        if (!claim.authorizationUrl || !claim.reference) {
          throw new Error("PAYMENT_INITIALIZATION_INVALID");
        }
        res.status(200).json({
          authorizationUrl: claim.authorizationUrl,
          reference: claim.reference,
          intentId: created.intentId,
          quote: prepared.quote,
          deduped: true,
        });
        return;
      }

      try {
        const response = await axios.post(
          "https://api.paystack.co/transaction/initialize",
          {
            email,
            amount: prepared.quote.totalChargeMinor,
            currency: "ZAR",
            channels: [prepared.channel],
            reference,
            ...(process.env.PAYSTACK_CALLBACK_URL
              ? { callback_url: process.env.PAYSTACK_CALLBACK_URL }
              : {}),
            metadata: {
              schemaVersion: 2,
              purpose: "campaign_credit",
              intentId: created.intentId,
              merchantId: prepared.merchantId,
              walletStoreId: wallet.walletStoreId,
              creditAmountMinor: prepared.quote.creditAmountMinor,
              selectedChannel: prepared.channel,
              initiatedBy: prepared.uid,
            },
          },
          {
            headers: { Authorization: `Bearer ${paystackSecret()}` },
            timeout: 15_000,
          },
        );
        const authorizationUrl = String(
          response.data?.data?.authorization_url ?? "",
        ).trim();
        const providerReference = String(
          response.data?.data?.reference ?? "",
        ).trim();
        if (!authorizationUrl || providerReference !== reference) {
          throw new Error("PAYSTACK_INITIALIZE_RESPONSE_INVALID");
        }
        await db.runTransaction(async (tx) => {
          const intent = await tx.get(intentRef);
          const data = intent.data() ?? {};
          if (
            data.status === "initialized" &&
            data.providerReference === reference
          ) {
            return;
          }
          if (data.initializationClaimId !== claimId) {
            throw new Error("PAYMENT_INITIALIZATION_CLAIM_LOST");
          }
          tx.update(intentRef, {
            status: "initialized",
            previousStatus: "created",
            provider: "paystack",
            providerReference: reference,
            authorizationUrl,
            initializationState: "completed",
            initializationLeaseUntilMs: 0,
            initializedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
        });
        res.status(200).json({
          authorizationUrl,
          reference,
          intentId: created.intentId,
          quote: prepared.quote,
          deduped: created.deduped,
        });
      } catch (error) {
        await intentRef.set(
          {
            initializationState: "retryable",
            initializationLeaseUntilMs: 0,
            initializationErrorCode: "provider_initialization_failed",
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        throw error;
      }
    } catch (error) {
      console.error("[payments-v2] campaign top-up initialization failed", {
        code: error instanceof Error ? error.message : "unknown",
      });
      const response = publicError(error);
      res.status(response.status).json({ error: response.message });
    }
  });

function providerEventId(transaction: Record<string, unknown>): string {
  const id = String(transaction.id ?? "").trim();
  return id ? `charge-${id}` : "";
}

/** Applies an independently verified Paystack charge exactly once. */
export async function applyVerifiedCampaignTopupV2(
  transaction: Record<string, any>,
  rawBody: Buffer,
): Promise<{ deduped: boolean; intentId: string }> {
  const metadata = transaction.metadata ?? {};
  const intentId = String(metadata.intentId ?? "").trim();
  if (!/^pi_[a-f0-9]{64}$/.test(intentId)) throw new Error("INTENT_ID_INVALID");
  const reference = String(transaction.reference ?? "").trim();
  const amountMinor = requirePositiveMinorUnits(
    transaction.amount,
    "provider_amount",
  );
  const providerFeeMinor = Number(transaction.fees ?? 0);
  if (!Number.isSafeInteger(providerFeeMinor) || providerFeeMinor < 0) {
    throw new Error("PROVIDER_FEE_INVALID");
  }
  const channel = String(transaction.channel ?? "").trim();
  if (!isCampaignTopupChannel(channel))
    throw new Error("TOPUP_CHANNEL_MISMATCH");
  const eventInput = {
    provider: "paystack" as const,
    ...(providerEventId(transaction)
      ? { providerEventId: providerEventId(transaction) }
      : {}),
    eventType: "charge.success",
    reference,
    rawBody,
    intentId,
  };
  const recorded = await recordProviderEventV2(eventInput);
  const eventRef = db.doc(
    `paymentEvents/${providerEventDocumentId(eventInput)}`,
  );
  const intentRef = db.doc(`paymentIntents/${intentId}`);
  const intentSnapshot = await intentRef.get();
  if (!intentSnapshot.exists) throw new Error("INTENT_NOT_FOUND");
  const initial = intentSnapshot.data() ?? {};
  const merchantId = requireStoreId(initial.merchantId);
  const wallet = await resolveCampaignWallet(merchantId);
  const walletStoreId = requireStoreId(initial.businessBinding?.id);
  if (
    initial.purpose !== "campaign_credit" ||
    initial.businessBinding?.type !== "campaign_wallet" ||
    wallet.walletStoreId !== walletStoreId ||
    String(initial.providerReference ?? "") !== reference ||
    String(initial.selectedChannel ?? "") !== channel ||
    Number(initial.expectedAmountMinor) !== amountMinor ||
    String(metadata.merchantId ?? "") !== merchantId ||
    String(metadata.walletStoreId ?? "") !== walletStoreId
  ) {
    throw new Error("CAMPAIGN_TOPUP_BINDING_MISMATCH");
  }
  const creditAmountMinor = requirePositiveMinorUnits(
    initial.campaignCreditAmountMinor,
    "credit_amount",
  );
  if (Number(metadata.creditAmountMinor) !== creditAmountMinor) {
    throw new Error("CAMPAIGN_TOPUP_CREDIT_MISMATCH");
  }
  const purchaseRef = db.doc(`campaignCreditPurchases/${intentId}`);
  let deduped = recorded.deduped;
  await db.runTransaction(async (tx) => {
    const [intent, event, purchase] = await Promise.all([
      tx.get(intentRef),
      tx.get(eventRef),
      tx.get(purchaseRef),
    ]);
    if (!intent.exists || !event.exists)
      throw new Error("PAYMENT_CORE_MISSING");
    const data = intent.data() ?? {};
    const applied = Array.isArray(data.appliedProviderEventIds)
      ? data.appliedProviderEventIds.map(String)
      : [];
    if (purchase.exists || applied.includes(eventRef.id)) {
      if (
        !purchase.exists ||
        Number(purchase.get("creditAmountMinor")) !== creditAmountMinor
      ) {
        throw new Error("CAMPAIGN_TOPUP_IDEMPOTENCY_COLLISION");
      }
      deduped = true;
      return;
    }
    if (!["initialized", "pending"].includes(String(data.status ?? ""))) {
      throw new Error("CAMPAIGN_TOPUP_STATUS_INVALID");
    }
    const result = await mutateCampaignCredits(
      tx,
      wallet,
      creditAmountMinor / 100,
      {
        id: `paystack-v2:${intentId}`,
        kind: "paystack-topup",
        initiatedBy: String(metadata.initiatedBy ?? "") || undefined,
        metadata: {
          source: "paystack_v2",
          intentId,
          reference,
          grossAmountMinor: amountMinor,
          providerFeeMinor,
          creditAmountMinor,
          channel,
        },
      },
    );
    const now = FieldValue.serverTimestamp();
    tx.create(purchaseRef, {
      purchaseId: intentId,
      intentId,
      merchantId,
      walletStoreId,
      creditAmountMinor,
      grossAmountMinor: amountMinor,
      quotedProviderFeeMinor: Number(data.money?.providerFeeMinor ?? 0),
      actualProviderFeeMinor: providerFeeMinor,
      refundedCreditMinor: 0,
      reference,
      channel,
      source: "paystack_v2",
      currency: "ZAR",
      schemaVersion: 2,
      createdAt: now,
      updatedAt: now,
    });
    tx.update(intentRef, {
      status: "paid",
      previousStatus: String(data.status),
      providerAmountMinor: amountMinor,
      providerFeeMinor,
      appliedProviderEventIds: FieldValue.arrayUnion(eventRef.id),
      paidAt: now,
      updatedAt: now,
    });
    tx.update(eventRef, {
      processingState: "applied",
      attemptCount: FieldValue.increment(1),
      processedAt: now,
      updatedAt: now,
    });
    tx.create(db.doc(`users/${merchantId}/topUpTransactions/${reference}`), {
      reference,
      intentId,
      source: "paystack_v2",
      amount: creditAmountMinor / 100,
      creditAmountMinor,
      grossAmountMinor: amountMinor,
      providerFeeMinor,
      balanceAfter: result.balance,
      currency: "ZAR",
      status: "success",
      provider: "paystack",
      channel,
      createdAt: now,
    });
  });
  return { deduped, intentId };
}

export function campaignTopupWalletRef(walletStoreId: string) {
  return campaignWalletRef(walletStoreId);
}
