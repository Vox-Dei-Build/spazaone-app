// functions/src/http/verifyPaystackTransaction.ts
import { functions, db } from "../../config/main";
import * as admin from "firebase-admin";
import axios from "axios";
import * as path from "path";
import * as dotenv from "dotenv";

/**
 * Paystack webhook (recommended path: /verifyPaystackTransaction).
 * Expects JSON body from Paystack. Handles only `charge.success`.
 *
 * Behavior:
 * - Verifies with Paystack /transaction/verify/:reference
 * - Uses provider-reported `fees` if present; else falls back to local formula
 * - Marks sale paid (purpose='sale'), writes ledger, increments wallet.salesVirtualBalance
 * - Idempotent by (provider, reference)
 */
export const verifyPaystackTransaction = functions.https.onRequest(
  async (req, res) => {
    try {
      dotenv.config({ path: path.join(process.cwd(), ".env.local") });
      dotenv.config({ path: path.join(process.cwd(), ".env") });

      const PAYSTACK_SECRET_KEY =
        process.env.PAYSTACK_SECRET_KEY ||
        process.env.PAYSTACK_TEST_SECRET_KEY ||
        (functions.config().paystack?.secret as string | undefined);

      if (!PAYSTACK_SECRET_KEY) {
        res.status(500).json({ error: "Missing PAYSTACK_SECRET_KEY" });
        return;
      }

      const { event, data } = req.body || {};
      if (event !== "charge.success") {
        res.status(400).json({ error: "Unsupported event" });
        return;
      }

      const reference: string | undefined = data?.reference;
      const meta = data?.metadata || {};
      const purpose = (meta?.purpose || "").toLowerCase(); // 'sale' | 'topup'
      const merchantId: string | undefined = meta?.merchantId;
      const saleId: string | undefined = meta?.saleId || undefined;

      if (!reference || !merchantId || !purpose) {
        res.status(400).json({ error: "Missing transaction details" });
        return;
      }

      // Cross-check with Paystack
      const verify = await axios.get(
        `https://api.paystack.co/transaction/verify/${reference}`,
        {
          headers: { Authorization: `Bearer ${PAYSTACK_SECRET_KEY}` },
          timeout: 15000,
        },
      );

      const v = verify?.data?.data || {};
      const success = verify?.data?.status && v?.status === "success";
      if (!success) {
        res.status(400).json({ error: "Transaction not successful" });
        return;
      }

      // Amounts
      const amount = Number(v?.amount || 0) / 100; // ZAR
      const VAT = 0.15;

      // Prefer provider-reported fee, else compute
      let feeInclVat = Number.isFinite(v?.fees) ? Number(v.fees) / 100 : NaN;

      // Derive method used from channel (card/qr/eft/ussd/etc.)
      const channel = String(v?.channel || "").toLowerCase();
      let methodUsed: "local_card" | "eft" | "international" = "local_card";
      if (channel === "eft") methodUsed = "eft";
      // (International vs local can't be perfectly inferred; assume 'local_card' for ZAR unless you add extra checks.)

      if (!Number.isFinite(feeInclVat)) {
        // Fallback fee calc
        const R1 = 1.0;
        const pct = methodUsed === "eft" ? 0.02 : 0.029; // 'international' -> 0.031 if you add detection
        const flat = methodUsed === "eft" ? 0 : R1;
        const exVat = amount * pct + flat;
        feeInclVat = exVat * (1 + VAT);
      }

      const feeExVat = feeInclVat / (1 + VAT);
      const netToMerchant = amount - feeInclVat;

      // Idempotency guard
      const processedRef = db
        .collection("payments")
        .doc("paystack")
        .collection("processed")
        .doc(reference);
      const processedSnap = await processedRef.get();
      if (processedSnap.exists) {
        res.status(200).json({ success: true, deduped: true });
        return;
      }

      const now = admin.firestore.FieldValue.serverTimestamp();

      if (purpose === "sale") {
        if (!saleId) {
          res.status(400).json({ error: "Missing saleId for sale payment" });
          return;
        }

        const saleRef = db
          .collection("users")
          .doc(merchantId)
          .collection("sales")
          .doc(saleId);
        const walletRef = db
          .collection("users")
          .doc(merchantId)
          .collection("wallet")
          .doc("current");

        const saleSnap = await saleRef.get();
        if (!saleSnap.exists) {
          res.status(404).json({ error: "Sale not found" });
          return;
        }

        const alreadyPaid =
          String(saleSnap.get("paymentStatus") || "").toLowerCase() ===
            "paid" ||
          String(saleSnap.get("status") || "").toLowerCase() === "paid";

        const batch = db.batch();

        if (!alreadyPaid) {
          batch.update(saleRef, {
            paymentMethod: "Online",
            paymentStatus: "paid",
            status: "paid",
            paymentReference: reference,
            paidAt: now,
            updatedAt: now,
            channelUsed: channel,
            methodUsed,
          });
        }

        const ledgerRef = db
          .collection("users")
          .doc(merchantId)
          .collection("salesLedger")
          .doc(reference);
        batch.set(ledgerRef, {
          saleId,
          reference,
          amount, // customer paid
          feeInclVat, // provider fee incl VAT
          feeExVat, // derived
          netAmount: netToMerchant,
          currency: "ZAR",
          provider: "paystack",
          channel: channel,
          method: methodUsed,
          createdAt: now,
        });

        batch.set(
          walletRef,
          {
            salesVirtualBalance:
              admin.firestore.FieldValue.increment(netToMerchant),
            updatedAt: now,
          },
          { merge: true },
        );

        batch.set(processedRef, {
          provider: "paystack",
          purpose: "sale",
          merchantId,
          saleId,
          reference,
          amount,
          feeInclVat,
          netAmount: netToMerchant,
          method: methodUsed,
          channel,
          createdAt: now,
        });

        await batch.commit();
        res.status(200).json({ success: true });
        return;
      }

      if (purpose === "topup") {
        const walletRef = db
          .collection("users")
          .doc(merchantId)
          .collection("wallet")
          .doc("current");
        const txRef = db
          .collection("users")
          .doc(merchantId)
          .collection("topUpTransactions")
          .doc(reference);

        await db.runTransaction(async (t) => {
          const w = await t.get(walletRef);
          const current = (w.data()?.virtualBalance || 0) as number;
          t.set(
            walletRef,
            { virtualBalance: current + netToMerchant, updatedAt: now },
            { merge: true },
          );
          t.set(txRef, {
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
          t.set(processedRef, {
            provider: "paystack",
            purpose: "topup",
            merchantId,
            reference,
            amount,
            feeInclVat,
            netAmount: netToMerchant,
            method: methodUsed,
            channel,
            createdAt: now,
          });
        });

        res.status(200).json({ success: true });
        return;
      }

      res.status(400).json({ error: "Unknown purpose" });
    } catch (err: any) {
      console.error("verifyPaystackTransaction error:", err?.message || err);
      res.status(500).json({ error: "Transaction verification failed" });
    }
  },
);
