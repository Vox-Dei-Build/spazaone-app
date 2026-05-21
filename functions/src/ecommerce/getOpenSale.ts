// functions/src/http/getOpenSale.ts
import { db, functions } from "../config/main";

const OPEN_STATUSES = new Set([
  "pending_payment", // Online waiting for payment
  "awaiting_collection", // Cash (not yet collected)
  "pending_merchant_review", // WhatsApp order request waiting for merchant
  "accepted", // Merchant accepted; payment/collection still outstanding
  "pending_review", // BNPL
  "bnpl_outstanding", // BNPL approved but unpaid
]);

export const getOpenSale = functions.https.onRequest(async (req, res) => {
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

  const q = await db
    .collection("users")
    .doc(merchantId)
    .collection("sales")
    .where("customerId", "==", customerId)
    .where("inventoryFinalized", "==", false)
    .orderBy("dateAdded", "desc")
    .limit(1)
    .get();

  if (q.empty) {
    res.status(200).json({ openSale: null });
    return;
  }

  const sale = q.docs[0].data();
  const open = OPEN_STATUSES.has(String(sale.status || "").toLowerCase());
  res.status(200).json({ openSale: open ? { ...sale } : null });
});
