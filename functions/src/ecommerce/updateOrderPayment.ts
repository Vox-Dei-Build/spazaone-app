// functions/src/http/updateOrderPayment.ts
import { db, functions } from "../config/main";

export const updateOrderPayment = functions.https.onCall(
  async (data) => {
    try {
      const merchantId = data.merchantId as string;
      const orderId = data.orderId as string;
      const paymentAction = data.paymentAction as string;
      if (!merchantId || !orderId || !paymentAction) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "merchantId, orderId, paymentAction are required",
        );
      }

      const ref = db
        .collection("users")
        .doc(merchantId)
        .collection("sales")
        .doc(orderId);
      const snap = await ref.get();
      if (!snap.exists) {
        throw new functions.https.HttpsError("not-found", "Order not found");
      }

      const now = new Date();
      let patch: Record<string, any> = { updatedAt: now };

      const orderData = snap.data() || {};

      switch (paymentAction) {
        case "ACCEPT_BNPL":
          patch = {
            ...patch,
            paymentMethod: "BNPL",
            paymentStatus: "approved",
            status: "bnpl_outstanding",
            collected: false,
          };
          // create credit transaction for customer
          await db
            .collection("users")
            .doc(merchantId)
            .collection("customers")
            .doc(orderData.customerId)
            .collection("transactions")
            .add({
              type: "Credit",
              amount: Number(orderData.amount ?? 0),
              date: now,
              status: "DUE",
              products: orderData.products || {},
            });
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
        case "MARK_COLLECTED":
          patch = {
            ...patch,
            collected: true,
          };
          break;
        case "SETTLE_BNPL":
          patch = {
            ...patch,
            paymentStatus: "paid",
            status: "paid",
          };
          break;
        default:
          throw new functions.https.HttpsError(
            "invalid-argument",
            "Unknown paymentAction",
          );
      }

      await ref.update(patch);
      return { ok: true };
    } catch (err: any) {
      console.error("updateOrderPayment", err);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to update order",
      );
    }
  },
);
