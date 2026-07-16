// functions/src/http/createPaystackTransaction.ts
import { functions, db } from "../../config/main";
import axios from "axios";
import * as path from "path";
import * as dotenv from "dotenv";
import { authenticateFirebaseRequest } from "../../security/requestAuth";
import { assertStoreAccess, requireStoreId } from "../../stores/storeAccess";

const MAX_TRANSACTION_RANDS = 100_000;

function publicError(error: unknown): { status: number; message: string } {
  if (error instanceof functions.https.HttpsError) {
    const status =
      error.code === "unauthenticated"
        ? 401
        : error.code === "permission-denied"
          ? 403
          : error.code === "not-found"
            ? 404
            : 400;
    return { status, message: error.message };
  }
  return { status: 500, message: "Failed to create transaction" };
}

/**
 * Initialize a Paystack transaction.
 *
 * Body (JSON):
 * - merchantId: string (required)
 * - email: string (required)
 * - amount: number (required, ZAR *rands*, NOT cents)  ← we convert to cents server-side
 * - purpose: 'sale' | 'topup' (required)
 * - saleId?: string (required when purpose === 'sale')
 * - method?: 'local_card' | 'eft' | 'international' (default 'local_card')
 *
 * Returns: { authorizationUrl: string, reference: string }
 */
export const createPaystackTransaction = functions.https.onRequest(
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
      }

      const uid = await authenticateFirebaseRequest(req, res);
      if (!uid) return;

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

      const { email, purpose, saleId } = req.body || {};
      const merchantId = requireStoreId(
        req.body?.storeId ?? req.body?.merchantId,
      );
      const { amount, method } = req.body || {};

      if (!merchantId || !email || !amount || !purpose) {
        res
          .status(400)
          .json({ error: "merchantId, email, amount, purpose are required" });
        return;
      }
      await assertStoreAccess(uid, merchantId);
      const normalizedEmail = String(email).trim().toLowerCase();
      if (!/^\S+@\S+\.\S+$/.test(normalizedEmail)) {
        res.status(400).json({ error: "A valid email is required" });
        return;
      }
      if (purpose === "sale" && !saleId) {
        res
          .status(400)
          .json({ error: "saleId is required for purpose 'sale'" });
        return;
      }
      if (purpose !== "sale" && purpose !== "topup") {
        res.status(400).json({ error: "purpose must be 'sale' or 'topup'" });
        return;
      }

      const payMethod =
        typeof method === "string" && method ? method : "local_card";

      let amountRands = Number(amount);
      if (purpose === "sale") {
        const sale = await db
          .doc(`users/${merchantId}/sales/${String(saleId).trim()}`)
          .get();
        if (!sale.exists) {
          res.status(404).json({ error: "Sale not found" });
          return;
        }
        const status = String(sale.data()?.status ?? "").toLowerCase();
        if (["paid", "cancelled"].includes(status)) {
          res.status(409).json({ error: "Sale is not payable" });
          return;
        }
        // The client cannot choose the charge for an existing sale.
        amountRands = Number(sale.data()?.amount ?? sale.data()?.total ?? 0);
      }

      // Amount is passed in RANDS, convert to cents.
      const amountCents = Math.round(amountRands * 100);
      if (!Number.isFinite(amountCents) || amountCents <= 0) {
        res.status(400).json({ error: "amount must be > 0 (ZAR rands)" });
        return;
      }
      if (amountRands > MAX_TRANSACTION_RANDS) {
        res.status(400).json({ error: "amount exceeds the transaction limit" });
        return;
      }

      // Restrict channels to the user's chosen method
      const channels =
        payMethod === "eft"
          ? ["eft"]
          : payMethod === "international"
            ? ["card"] // Paystack uses 'card'; can't force intl-only here
            : ["card", "qr"]; // local card + Scan to Pay

      const callbackUrl = process.env.PAYSTACK_CALLBACK_URL || undefined;

      const init = await axios.post(
        "https://api.paystack.co/transaction/initialize",
        {
          email: normalizedEmail,
          amount: amountCents,
          currency: "ZAR",
          channels,
          callback_url: callbackUrl,
          metadata: {
            merchantId,
            saleId: saleId || null,
            purpose,
            method: payMethod,
            initiatedBy: uid,
            schemaVersion: 2,
          },
        },
        {
          headers: { Authorization: `Bearer ${PAYSTACK_SECRET_KEY}` },
          timeout: 15000,
        },
      );

      const authorizationUrl =
        init.data?.data?.authorization_url || init.data?.authorizationUrl;
      const reference = init.data?.data?.reference || init.data?.reference;

      if (!authorizationUrl || !reference) {
        res
          .status(502)
          .json({ error: "Invalid response from Paystack initialize" });
        return;
      }

      res.status(200).json({ authorizationUrl, reference });
    } catch (err: any) {
      console.error("createPaystackTransaction error:", err?.message || err);
      const response = publicError(err);
      res.status(response.status).json({ error: response.message });
    }
  },
);
