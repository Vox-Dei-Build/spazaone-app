// functions/src/http/updateOrderPayment.ts
import { db, functions } from "../config/main";

export const updateOrderPayment = functions.https.onRequest(
  async (req, res) => {
    try {
      const { merchantId, orderId, paymentAction } = req.body || {};
      if (!merchantId || !orderId || !paymentAction) {
        res
          .status(400)
          .json({ error: "merchantId, orderId, paymentAction are required" });
      }

      const ref = db
        .collection("users")
        .doc(merchantId)
        .collection("sales")
        .doc(orderId);
      const snap = await ref.get();
      if (!snap.exists) res.status(404).json({ error: "Order not found" });

      const now = new Date();
      let patch: Record<string, any> = { updatedAt: now };

      switch (paymentAction) {
        case "ACCEPT_BNPL":
          patch = {
            ...patch,
            paymentMethod: "BNPL",
            paymentStatus: "approved",
            status: "paid", // or "bnpl_accepted" then your UI maps to Paid
          };
          break;
        case "MARK_CASH_RECEIVED":
          patch = {
            ...patch,
            paymentMethod: "Cash",
            paymentStatus: "paid",
            status: "paid",
            cashReceivedAt: now,
          };
          break;
        default:
          res.status(400).json({ error: "Unknown paymentAction" });
      }

      await ref.update(patch);
      res.status(200).json({ ok: true });
    } catch (err: any) {
      console.error("updateOrderPayment", err);
      res.status(500).json({ error: "Failed to update order" });
    }
  },
);
