// functions/src/http/getOpenSale.ts
import { db, functions } from "../config/main";
import {
  isOpenCommerceOrder,
  orderCreatedAtMillis,
  presentCommerceOrder,
} from "../commerce/orderPresentation";
import { requireBotRequest } from "../security/requestAuth";

const OPEN_COMMERCE_STATUSES = [
  "pending_payment",
  "paid",
  "submitted_for_fulfilment",
  "shipped",
];

const OPEN_STATUSES = new Set([
  "pending_payment", // Online waiting for payment
  "awaiting_collection", // Cash (not yet collected)
  "pending_merchant_review", // WhatsApp order request waiting for merchant
  "accepted", // Merchant accepted; payment/collection still outstanding
  "pending_review", // BNPL
  "bnpl_outstanding", // BNPL approved but unpaid
]);

export const getOpenSale = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    if (req.method !== "GET") {
      res.status(405).send("Method Not Allowed");
      return;
    }
    const merchantId = (req.query.merchantId || "").toString().trim();
    const customerId = (req.query.customerId || "").toString().trim();
    if (!merchantId || !customerId) {
      res.status(400).json({ error: "merchantId and customerId are required" });
      return;
    }

    const [legacySnapshot, commerceSnapshot] = await Promise.all([
      db
        .collection("users")
        .doc(merchantId)
        .collection("sales")
        .where("customerId", "==", customerId)
        .where("inventoryFinalized", "==", false)
        .orderBy("dateAdded", "desc")
        .limit(1)
        .get(),
      db
        .collection("commerceOrders")
        .where("sellerId", "==", merchantId)
        .where("customerId", "==", customerId)
        .where("status", "in", OPEN_COMMERCE_STATUSES)
        .orderBy("createdAt", "desc")
        .limit(10)
        .get(),
    ]);

    const candidates: Record<string, unknown>[] = [];
    if (!legacySnapshot.empty) {
      const doc = legacySnapshot.docs[0];
      const sale = doc.data();
      if (OPEN_STATUSES.has(String(sale.status || "").toLowerCase())) {
        candidates.push({ ...sale, id: doc.id, source: "legacy" });
      }
    }
    for (const doc of commerceSnapshot.docs) {
      if (isOpenCommerceOrder(doc.data())) {
        candidates.push(presentCommerceOrder(doc.id, doc.data()));
      }
    }
    candidates.sort(
      (left, right) => orderCreatedAtMillis(right) - orderCreatedAtMillis(left),
    );
    res.status(200).json({ openSale: candidates[0] ?? null });
  });
