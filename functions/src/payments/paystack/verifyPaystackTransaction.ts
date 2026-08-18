// Paystack webhook: validates the provider signature and uses only metadata
// returned by Paystack's verification API before crediting a store.
import { functions, db } from "../../config/main";
import { FieldValue } from "firebase-admin/firestore";
import axios from "axios";
import * as path from "path";
import * as dotenv from "dotenv";
import { createHash } from "crypto";
import {
  paystackCanaryIntentBindingValid,
  paystackProviderMode,
} from "../../config/environment";
import {
  centsFromRands,
  normalizePaystackSecret,
  verifyPaystackSignature,
} from "./paystackSecurity";
import { requireStoreId } from "../../stores/storeAccess";
import {
  campaignWalletRef,
  mutateCampaignCredits,
  resolveCampaignWallet,
} from "../../wallet/campaignCredits";
import { applyVerifiedCommercePayment } from "../../commerce/payment";
import { applyVerifiedCampaignTopupV2 } from "../v2/campaignTopup";
import { applyVerifiedOwnedOrderPaymentV2 } from "../v2/ownedOrders";
import { applyVerifiedSupplierPaymentV2 } from "../v2/supplierOrders";
import {
  handlePaystackRefundEventV2,
  quarantineVerifiedChargeV2,
} from "../v2/refunds";
import { applyVerifiedAccountSettlementV2 } from "../v2/accountSettlements";

type PaymentPurpose = "sale" | "topup";

const PAYMENT_V2_PURPOSES = new Set([
  "campaign_credit",
  "merchant_order",
  "supplier_order",
  "account_settlement",
  "repayment_installment",
]);

// These errors mean Paystack has confirmed that money moved, but the charge
// can no longer be safely applied to the immutable business intent. They are
// customer-money failures, not retryable infrastructure failures.
const PAYMENT_V2_QUARANTINE_ERRORS = new Set([
  "PROVIDER_CURRENCY_MISMATCH",
  "PROVIDER_AMOUNT_MISMATCH",
  "CAMPAIGN_TOPUP_BINDING_MISMATCH",
  "CAMPAIGN_TOPUP_CREDIT_MISMATCH",
  "CAMPAIGN_TOPUP_STATUS_INVALID",
  "TOPUP_CHANNEL_MISMATCH",
  "OWNED_ORDER_PAYMENT_BINDING_MISMATCH",
  "ORDER_CHANNEL_INVALID",
  "SALE_ALREADY_PAID",
  "SUPPLIER_PAYMENT_BINDING_MISMATCH",
  "SUPPLIER_ACTUAL_MARGIN_BELOW_SAFETY",
  "ACCOUNT_PAYMENT_BINDING_MISMATCH",
  "ACCOUNT_PAYMENT_PURPOSE_MISMATCH",
  "REPAYMENT_PLAN_NOT_ACTIVE",
]);

function paymentV2Purpose(transaction: Record<string, any>): string {
  return String(transaction.metadata?.purpose ?? "").toLowerCase();
}

function isQuarantinableV2Charge(
  transaction: Record<string, any>,
  code: string,
): boolean {
  return (
    PAYMENT_V2_PURPOSES.has(paymentV2Purpose(transaction)) &&
    /^pi_[a-f0-9]{64}$/.test(
      String(transaction.metadata?.intentId ?? "").trim(),
    ) &&
    PAYMENT_V2_QUARANTINE_ERRORS.has(code)
  );
}

export const verifyPaystackTransaction = functions
  .runWith({
    secrets: ["PAYSTACK_SECRET_KEY", "BOTPRESS_PAYMENT_REQUEST_WEBHOOK_SECRET"],
  })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }

    try {
      dotenv.config({ path: path.join(process.cwd(), ".env.local") });
      dotenv.config({ path: path.join(process.cwd(), ".env") });

      const secret = normalizePaystackSecret(
        process.env.PAYSTACK_SECRET_KEY ||
          process.env.PAYSTACK_TEST_SECRET_KEY ||
          (functions.config().paystack?.secret as string | undefined),
      );
      if (!secret) {
        res.status(500).json({ error: "Missing PAYSTACK_SECRET_KEY" });
        return;
      }

      const rawBody =
        req.rawBody ?? Buffer.from(JSON.stringify(req.body ?? {}));
      if (
        !verifyPaystackSignature(
          rawBody,
          req.get("x-paystack-signature"),
          secret,
        )
      ) {
        console.warn("[paystack] rejected webhook with invalid signature");
        res.status(401).json({ error: "Invalid webhook signature" });
        return;
      }

      const eventType = String(req.body?.event ?? "").toLowerCase();
      if (eventType.startsWith("refund.")) {
        const result = await handlePaystackRefundEventV2(req.body ?? {});
        res.status(200).json({
          ok: true,
          purpose: "refund",
          event: eventType,
          matched: result.matched,
        });
        return;
      }
      if (eventType !== "charge.success") {
        // Acknowledge valid events that this endpoint does not process so the
        // provider does not retry them indefinitely.
        res.status(200).json({ ignored: true });
        return;
      }

      const reference = String(req.body?.data?.reference ?? "").trim();
      if (!reference) {
        res.status(400).json({ error: "Missing transaction reference" });
        return;
      }

      const verify = await axios.get(
        `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
        {
          headers: { Authorization: `Bearer ${secret}` },
          timeout: 15000,
        },
      );
      const transaction = verify?.data?.data ?? {};
      if (
        verify?.data?.status !== true ||
        transaction.status !== "success" ||
        String(transaction.reference ?? "") !== reference
      ) {
        res.status(400).json({ error: "Transaction not successful" });
        return;
      }

      // Security boundary: never trust metadata from the webhook request.
      // Paystack's independently verified transaction is the source of truth.
      const metadata = transaction.metadata ?? {};
      if (paystackProviderMode() === "disabled") {
        const intentId = String(metadata.intentId ?? "").trim();
        const intent = /^pi_[a-f0-9]{64}$/.test(intentId)
          ? await db.doc(`paymentIntents/${intentId}`).get()
          : null;
        if (
          !intent?.exists ||
          !paystackCanaryIntentBindingValid({
            metadataMerchantId: metadata.merchantId,
            metadataPurpose: metadata.purpose,
            intentMerchantId: intent.get("merchantId"),
            intentPurpose: intent.get("purpose"),
            intentProviderMode: intent.get("providerMode"),
            intentActivationScope: intent.get("activationScope"),
          })
        ) {
          console.error(
            "[paystack] blocked verified charge outside disabled-provider canary",
            {
              purpose: String(metadata.purpose ?? "unknown"),
              hasBoundIntent: intent?.exists === true,
            },
          );
          res.status(409).json({ error: "Payment provider unavailable" });
          return;
        }
      }
      if (String(transaction.currency ?? "").toUpperCase() !== "ZAR") {
        if (
          isQuarantinableV2Charge(transaction, "PROVIDER_CURRENCY_MISMATCH")
        ) {
          const quarantined = await quarantineVerifiedChargeV2({
            transaction,
            rawBody,
            reason: "PROVIDER_CURRENCY_MISMATCH",
          });
          res.status(200).json({
            ok: true,
            purpose: paymentV2Purpose(transaction),
            intentId: quarantined.intentId,
            refundCaseId: quarantined.refundCaseId,
            refundPending: true,
            deduped: quarantined.deduped,
          });
          return;
        }
        res.status(400).json({ error: "Unsupported transaction currency" });
        return;
      }

      try {
        if (
          String(metadata.purpose ?? "").toLowerCase() === "campaign_credit"
        ) {
          const result = await applyVerifiedCampaignTopupV2(
            transaction,
            rawBody,
          );
          res.status(200).json({
            ok: true,
            purpose: "campaign_credit",
            intentId: result.intentId,
            deduped: result.deduped,
          });
          return;
        }
        if (String(metadata.purpose ?? "").toLowerCase() === "merchant_order") {
          const result = await applyVerifiedOwnedOrderPaymentV2(
            transaction,
            rawBody,
          );
          res.status(200).json({
            ok: true,
            purpose: "merchant_order",
            intentId: result.intentId,
            deduped: result.deduped,
          });
          return;
        }
        if (String(metadata.purpose ?? "").toLowerCase() === "supplier_order") {
          const result = await applyVerifiedSupplierPaymentV2(
            transaction,
            rawBody,
          );
          res.status(200).json({
            ok: true,
            purpose: "supplier_order",
            intentId: result.intentId,
            orderId: result.orderId,
            deduped: result.deduped,
          });
          return;
        }
        if (
          ["account_settlement", "repayment_installment"].includes(
            String(metadata.purpose ?? "").toLowerCase(),
          )
        ) {
          const result = await applyVerifiedAccountSettlementV2(
            transaction,
            rawBody,
          );
          res.status(200).json({
            ok: true,
            purpose: String(metadata.purpose).toLowerCase(),
            intentId: result.intentId,
            transactionId: result.transactionId ?? null,
            deduped: result.deduped,
          });
          return;
        }
      } catch (error: unknown) {
        const code =
          error instanceof Error ? error.message : String(error ?? "");
        if (!isQuarantinableV2Charge(transaction, code)) throw error;
        const quarantined = await quarantineVerifiedChargeV2({
          transaction,
          rawBody,
          reason: code,
        });
        res.status(200).json({
          ok: true,
          purpose: paymentV2Purpose(transaction),
          intentId: quarantined.intentId,
          refundCaseId: quarantined.refundCaseId,
          refundPending: true,
          deduped: quarantined.deduped,
        });
        return;
      }
      if (String(metadata.purpose ?? "").toLowerCase() === "commerce_order") {
        // Compatibility dispatcher only: commerce uses its own order,
        // snapshot and idempotency transaction and never reaches wallet or
        // legacy Sales mutation below. This lets an existing Paystack account
        // keep its single configured webhook URL during the MVP rollout.
        const result = await applyVerifiedCommercePayment(transaction);
        res.status(200).json({
          ok: true,
          purpose: "commerce_order",
          deduped: result.deduped,
        });
        return;
      }
      const merchantId = requireStoreId(metadata.merchantId);
      const purpose = String(
        metadata.purpose ?? "",
      ).toLowerCase() as PaymentPurpose;
      const saleId = String(metadata.saleId ?? "").trim();
      if (!(["sale", "topup"] as string[]).includes(purpose)) {
        res.status(400).json({ error: "Unknown payment purpose" });
        return;
      }

      const amountCents = Number(transaction.amount);
      if (!Number.isSafeInteger(amountCents) || amountCents <= 0) {
        res.status(400).json({ error: "Invalid transaction amount" });
        return;
      }
      const amount = amountCents / 100;
      const feeCents = Number(transaction.fees);
      const channel = String(transaction.channel ?? "").toLowerCase();
      const methodUsed: "local_card" | "eft" =
        channel === "eft" ? "eft" : "local_card";
      const feeInclVat = Number.isFinite(feeCents)
        ? feeCents / 100
        : (amount * (methodUsed === "eft" ? 0.02 : 0.029) +
            (methodUsed === "eft" ? 0 : 1)) *
          1.15;
      const feeExVat = feeInclVat / 1.15;
      const netToMerchant = amount - feeInclVat;
      if (!Number.isFinite(netToMerchant) || netToMerchant <= 0) {
        res.status(400).json({ error: "Invalid transaction fees" });
        return;
      }

      const processedRef = db.doc(`payments/paystack/processed/${reference}`);
      const campaignWallet =
        purpose === "topup"
          ? await resolveCampaignWallet(merchantId)
          : {
              storeId: merchantId,
              walletStoreId: merchantId,
              shared: false,
            };
      const walletRef =
        purpose === "sale"
          ? db.doc(`users/${merchantId}/wallet/current`)
          : campaignWalletRef(campaignWallet.walletStoreId);
      const now = FieldValue.serverTimestamp();
      let deduped = false;

      await db.runTransaction(async (tx) => {
        const processed = await tx.get(processedRef);
        if (processed.exists) {
          deduped = true;
          return;
        }

        if (purpose === "sale") {
          if (!saleId) throw new Error("MISSING_SALE_ID");
          const saleRef = db.doc(`users/${merchantId}/sales/${saleId}`);
          const sale = await tx.get(saleRef);
          if (!sale.exists) throw new Error("SALE_NOT_FOUND");
          const saleData = sale.data() ?? {};
          const expectedCents = centsFromRands(
            saleData.amount ?? saleData.total ?? 0,
          );
          if (expectedCents !== amountCents) throw new Error("AMOUNT_MISMATCH");

          const alreadyPaid = [saleData.paymentStatus, saleData.status]
            .map((value) => String(value ?? "").toLowerCase())
            .includes("paid");
          if (
            alreadyPaid &&
            String(saleData.paymentReference ?? "") !== reference
          ) {
            throw new Error("SALE_ALREADY_PAID");
          }

          if (!alreadyPaid) {
            tx.update(saleRef, {
              paymentMethod: "Online",
              paymentStatus: "paid",
              status: "paid",
              paymentReference: reference,
              paidAt: now,
              updatedAt: now,
              channelUsed: channel,
              methodUsed,
            });
            tx.set(
              walletRef,
              {
                salesVirtualBalance: FieldValue.increment(netToMerchant),
                updatedAt: now,
              },
              { merge: true },
            );
          }
          tx.set(db.doc(`users/${merchantId}/salesLedger/${reference}`), {
            saleId,
            reference,
            amount,
            feeInclVat,
            feeExVat,
            netAmount: netToMerchant,
            currency: "ZAR",
            provider: "paystack",
            channel,
            method: methodUsed,
            createdAt: now,
          });
        } else {
          await mutateCampaignCredits(tx, campaignWallet, netToMerchant, {
            id: `paystack:${createHash("sha256")
              .update(reference)
              .digest("hex")}`,
            kind: "paystack-topup",
            initiatedBy: String(metadata.initiatedBy ?? "") || undefined,
            metadata: {
              reference,
              amount,
              feeInclVat,
              method: methodUsed,
            },
          });
          tx.set(db.doc(`users/${merchantId}/topUpTransactions/${reference}`), {
            reference,
            amount,
            feeInclVat,
            feeExVat,
            netAmount: netToMerchant,
            currency: "ZAR",
            status: "success",
            provider: "paystack",
            channel,
            method: methodUsed,
            createdAt: now,
          });
        }

        tx.create(processedRef, {
          provider: "paystack",
          purpose,
          merchantId,
          walletStoreId:
            purpose === "topup" ? campaignWallet.walletStoreId : merchantId,
          sharedCampaignCredits:
            purpose === "topup" ? campaignWallet.shared : false,
          ...(purpose === "sale" ? { saleId } : {}),
          reference,
          amount,
          feeInclVat,
          netAmount: netToMerchant,
          method: methodUsed,
          channel,
          verifiedMetadata: true,
          createdAt: now,
        });
      });

      res
        .status(200)
        .json({ success: true, ...(deduped ? { deduped: true } : {}) });
    } catch (error: unknown) {
      const code = error instanceof Error ? error.message : String(error ?? "");
      const known: Record<string, [number, string]> = {
        MISSING_SALE_ID: [400, "Missing saleId for sale payment"],
        SALE_NOT_FOUND: [404, "Sale not found"],
        AMOUNT_MISMATCH: [409, "Paid amount does not match sale"],
        SALE_ALREADY_PAID: [409, "Sale is already paid"],
      };
      const mapped = known[code];
      if (mapped) {
        res.status(mapped[0]).json({ error: mapped[1] });
        return;
      }
      console.error("verifyPaystackTransaction error:", code || error);
      res.status(500).json({ error: "Transaction verification failed" });
    }
  });
