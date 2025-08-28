// functions/src/http/createPaystackTransaction.ts
import { functions } from "../../config/main";
import axios from "axios";
import * as path from "path";
import * as dotenv from "dotenv";

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

      const { merchantId, email, purpose, saleId } = req.body || {};
      const { amount, method } = req.body || {};

      if (!merchantId || !email || !amount || !purpose) {
        res
          .status(400)
          .json({ error: "merchantId, email, amount, purpose are required" });
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

      // Amount is passed in RANDS, convert to cents
      const amountCents = Math.round(Number(amount) * 100);
      if (!Number.isFinite(amountCents) || amountCents <= 0) {
        res.status(400).json({ error: "amount must be > 0 (ZAR rands)" });
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
          email,
          amount: amountCents,
          currency: "ZAR",
          channels,
          callback_url: callbackUrl,
          metadata: {
            merchantId,
            saleId: saleId || null,
            purpose,
            method: payMethod,
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
      res.status(500).json({ error: "Failed to create transaction" });
    }
  },
);
