// Paystack webhook: validates the provider signature and uses only metadata
// returned by Paystack's verification API before crediting a store.
import { functions, db } from "../../config/main";
import * as admin from "firebase-admin";
import axios from "axios";
import * as path from "path";
import * as dotenv from "dotenv";
import { createHash } from "crypto";
import { centsFromRands, verifyPaystackSignature } from "./paystackSecurity";
import { requireStoreId } from "../../stores/storeAccess";
import {
  campaignWalletRef,
  mutateCampaignCredits,
  resolveCampaignWallet,
} from "../../wallet/campaignCredits";
import { applyVerifiedCommercePayment } from "../../commerce/payment";

type PaymentPurpose = "sale" | "topup";

export const verifyPaystackTransaction = functions.https.onRequest(
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }

    try {
      dotenv.config({ path: path.join(process.cwd(), ".env.local") });
      dotenv.config({ path: path.join(process.cwd(), ".env") });

      const secret =
        process.env.PAYSTACK_SECRET_KEY ||
        process.env.PAYSTACK_TEST_SECRET_KEY ||
        (functions.config().paystack?.secret as string | undefined);
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

      if (req.body?.event !== "charge.success") {
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
      if (String(transaction.currency ?? "").toUpperCase() !== "ZAR") {
        res.status(400).json({ error: "Unsupported transaction currency" });
        return;
      }

      // Security boundary: never trust metadata from the webhook request.
      // Paystack's independently verified transaction is the source of truth.
      const metadata = transaction.metadata ?? {};
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
      const now = admin.firestore.FieldValue.serverTimestamp();
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
                salesVirtualBalance:
                  admin.firestore.FieldValue.increment(netToMerchant),
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
  },
);
