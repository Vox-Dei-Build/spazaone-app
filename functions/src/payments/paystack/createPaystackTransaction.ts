// functions/src/http/createPaystackTransaction.ts
import { functions } from "../../config/main";
import axios from "axios";
import * as path from "path";
import * as dotenv from "dotenv";

/**
 * Initialize a Paystack transaction for either:
 *  - purpose: 'sale'  (requires saleId)
 *  - purpose: 'topup' (no saleId)
 *
 * BODY:
 *  - merchantId: string (required)
 *  - email: string (required)
 *  - amount: number (required, MINOR units, e.g. ZAR cents)
 *  - purpose: 'sale' | 'topup' (required)
 *  - method?: 'local_card' | 'eft' | 'international' (default: 'local_card')
 *  - saleId?: string (required when purpose === 'sale')
 *
 * Returns: { authorizationUrl, reference }
 */
export const createPaystackTransaction = functions.https.onRequest(
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
      }

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

      // --- inputs
      const { merchantId, email, purpose, saleId, method } = req.body || {};
      let { amount } = req.body || {};

      if (!merchantId || !email || !amount || !purpose) {
        res.status(400).json({
          error: "merchantId, email, amount, purpose are required",
        });
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

      amount = amount * 100;

      // --- initialize with Paystack (amount in MINOR units)
      const init = await axios.post(
        "https://api.paystack.co/transaction/initialize",
        {
          email,
          amount, // MINOR units (e.g., ZAR cents)
          currency: "ZAR",
          metadata: {
            merchantId,
            saleId: saleId || null,
            purpose, // 'sale' | 'topup'
            method: payMethod,
          },
          // callback_url: "https://your-site.example/return" // optional
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
