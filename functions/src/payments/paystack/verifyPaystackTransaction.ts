// functions/src/http/verifyPaystackTransaction.ts
import { functions, db } from "../../config/main";
import * as admin from "firebase-admin";
import axios from "axios";
import * as path from "path";
import * as dotenv from "dotenv";
// import * as crypto from "crypto"; // (optional) signature verification

export const verifyPaystackTransaction = functions.https.onRequest(
  async (req, res) => {
    try {
      // --- env / secrets
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

      // (Optional) validate signature:
      // const signature = req.headers["x-paystack-signature"] as string | undefined;
      // const computed = crypto
      //   .createHmac("sha512", PAYSTACK_SECRET_KEY)
      //   .update(JSON.stringify(req.body))
      //   .digest("hex");
      // if (!signature || signature !== computed) {
      //   res.status(401).json({ error: "Invalid signature" });
      //   return;
      // }

      const { event, data } = req.body || {};
      if (event !== "charge.success") {
        res.status(400).json({ error: "Unsupported event" });
        return;
      }

      const reference: string | undefined = data?.reference;
      const metadata = data?.metadata || {};
      const purpose = (metadata?.purpose || "").toLowerCase(); // 'sale' | 'topup'
      const merchantId: string | undefined = metadata?.merchantId;
      const saleId: string | undefined = metadata?.saleId || undefined;
      const method = (metadata?.method || "local_card") as
        | "local_card"
        | "eft"
        | "international";

      const amountMinor: number = data?.amount ?? 0; // cents/kobo
      const amount = amountMinor / 100; // ZAR

      if (!reference || !merchantId || !purpose) {
        res.status(400).json({ error: "Missing transaction details" });
        return;
      }

      // Cross-check with Paystack
      const verify = await axios.get(
        `https://api.paystack.co/transaction/verify/${reference}`,
        { headers: { Authorization: `Bearer ${PAYSTACK_SECRET_KEY}` } },
      );
      const success =
        verify.data?.status && verify.data?.data?.status === "success";
      if (!success) {
        res.status(400).json({ error: "Transaction not successful" });
        return;
      }

      // --- fee calculation
      const VAT = 0.15;
      const R1 = 1.0;
      let pct = 0;
      let flat = 0;

      switch (method) {
        case "local_card":
          pct = 0.029;
          flat = R1;
          break;
        case "eft":
          pct = 0.02;
          flat = 0;
          break;
        case "international":
          pct = 0.031;
          flat = R1;
          break;
        default:
          pct = 0.029;
          flat = R1;
      }

      const feeExVat = amount * pct + flat;
      const vat = feeExVat * VAT;
      const feeInclVat = feeExVat + vat;
      const totalFeesInclVat = feeInclVat;
      const netToMerchant = amount - totalFeesInclVat;

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
          (saleSnap.get("paymentStatus") || "").toLowerCase() === "paid" ||
          (saleSnap.get("status") || "").toLowerCase() === "paid";

        const batch = db.batch();

        // a) Mark the sale paid (only if not paid yet)
        if (!alreadyPaid) {
          batch.update(saleRef, {
            paymentMethod: "Online",
            paymentStatus: "paid",
            status: "paid",
            paymentReference: reference,
            paidAt: now,
            updatedAt: now,
          });
        }

        // b) Record a sales ledger entry
        const ledgerRef = db
          .collection("users")
          .doc(merchantId)
          .collection("salesLedger")
          .doc(reference);

        batch.set(ledgerRef, {
          saleId,
          reference,
          amount,
          currency: "ZAR",
          provider: "paystack",
          type: "CREDIT",
          purpose: "sale",
          fee: feeInclVat,
          netAmount: netToMerchant,
          method,
          createdAt: now,
        });

        // c) Increment wallet.salesVirtualBalance (create field if missing)
        //    Do NOT touch wallet.virtualBalance for sales.
        batch.set(
          walletRef,
          {
            salesVirtualBalance:
              admin.firestore.FieldValue.increment(netToMerchant),
            updatedAt: now,
          },
          { merge: true },
        );

        // d) Mark this reference as processed for idempotency
        batch.set(processedRef, {
          provider: "paystack",
          purpose: "sale",
          merchantId,
          saleId,
          reference,
          amount,
          fee: feeInclVat,
          netAmount: netToMerchant,
          method,
          createdAt: now,
        });

        await batch.commit();
        res.status(200).json({ success: true });
        return;
      }

      if (purpose === "topup") {
        // Top-ups still credit wallet.virtualBalance (app balance)
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
          const current = w.data()?.virtualBalance || 0;
          t.set(
            walletRef,
            {
              virtualBalance: current + netToMerchant,
              updatedAt: now,
            },
            { merge: true },
          );
          t.set(txRef, {
            reference,
            amount,
            fee: feeInclVat,
            netAmount: netToMerchant,
            currency: "ZAR",
            status: "success",
            provider: "paystack",
            method,
            createdAt: now,
          });
          t.set(processedRef, {
            provider: "paystack",
            purpose: "topup",
            merchantId,
            reference,
            amount,
            fee: feeInclVat,
            netAmount: netToMerchant,
            method,
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
