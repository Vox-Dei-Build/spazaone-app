// functions/src/http/updateOrderPayment.ts
import { db, functions } from "../config/main";

const ALLOWED = new Set([
  "ACCEPT_BNPL",
  "MARK_CASH_RECEIVED",
  "MARK_COLLECTED",
  "SETTLE_BNPL",
]);

export const updateOrderPayment = functions.https.onCall(
  async (data, context) => {
    try {
      const merchantId = (data?.merchantId ?? "").toString().trim();
      const orderId = (data?.orderId ?? "").toString().trim();
      const paymentAction = (data?.paymentAction ?? "")
        .toString()
        .trim()
        .toUpperCase();

      console.log("[updateOrderPayment] input", {
        merchantId,
        orderId,
        paymentAction,
        uid: context.auth?.uid,
      });

      if (!merchantId || !orderId || !paymentAction) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "merchantId, orderId, paymentAction are required",
        );
      }
      if (!ALLOWED.has(paymentAction)) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          `Unknown paymentAction. Allowed: ${Array.from(ALLOWED).join(", ")}`,
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

      // Normalize fields that differ between writers
      const customerId = (
        orderData.customerId ??
        orderData.customerID ??
        orderData.customer
      )?.toString();
      const amount = Number(orderData.total ?? orderData.amount ?? 0) || 0;
      const products =
        orderData.products ?? orderData.items ?? orderData.cart ?? [];

      switch (paymentAction) {
        case "ACCEPT_BNPL": {
          patch = {
            ...patch,
            paymentMethod: "BNPL",
            paymentStatus: "approved",
            status: "bnpl_outstanding",
            collected: false,
          };

          // Only create a credit transaction if we have a valid customerId
          if (customerId) {
            await db
              .collection("users")
              .doc(merchantId)
              .collection("customers")
              .doc(customerId)
              .collection("transactions")
              .add({
                type: "Credit",
                amount: amount,
                date: now,
                status: "DUE",
                products, // may be array or map; your reader should handle both
                orderId,
                source: "updateOrderPayment",
              });
          } else {
            console.warn(
              "[updateOrderPayment] ACCEPT_BNPL: missing customerId, skipping customer transaction",
            );
          }
          break;
        }
        case "MARK_CASH_RECEIVED": {
          patch = {
            ...patch,
            paymentMethod: "Cash",
            paymentStatus: "paid",
            status: "paid",
            cashReceivedAt: now,
          };
          break;
        }
        case "MARK_COLLECTED": {
          patch = {
            ...patch,
            collected: true,
            collectedAt: now,
            status: "collected",
          };
          break;
        }
        case "SETTLE_BNPL": {
          patch = {
            ...patch,
            paymentStatus: "paid",
            status: "paid",
            paidAt: now,
          };
          break;
        }
      }

      await ref.update(patch);
      return { ok: true };
    } catch (err: any) {
      console.error("updateOrderPayment error", err);
      // If it's already an HttpsError, rethrow to preserve the code
      if (err?.code && err?.message) throw err;
      throw new functions.https.HttpsError(
        "internal",
        "Failed to update order",
      );
    }
  },
);
