// functions/src/http/getOrderById.ts
import { db, functions } from "../config/main";
import { authorizeCallableMerchantOrBot } from "../security/requestAuth";

export const getOrderById = functions.https.onCall(async (data, context) => {
  try {
    const merchantId = data.merchantId as string;
    const orderId = data.orderId as string;
    if (!merchantId || !orderId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "merchantId and orderId are required",
      );
    }
    if (!authorizeCallableMerchantOrBot(context, merchantId)) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Access denied",
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

    const orderData = snap.data() || {};
    return {
      id: snap.id,
      status: orderData.status || "pending",
      total: Number(
        orderData.amount ?? orderData.total ?? orderData.saleTotal ?? 0,
      ),
      itemsCount: Number(
        orderData.itemsCount ??
          (orderData.products && typeof orderData.products === "object"
            ? Object.values(orderData.products).reduce(
                (acc: number, q: any) => acc + Number(q || 0),
                0,
              )
            : 0),
      ),
      paymentMethod: orderData.paymentMethod || "",
      paymentStatus: orderData.paymentStatus || "",
      createdAt: orderData.dateAdded || orderData.createdAt || null,
      items: Array.isArray(orderData.items) ? orderData.items : [],
      collected: orderData.collected || false,
    };
  } catch (err: any) {
    console.error("getOrderById", err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError("internal", "Failed to fetch order");
  }
});
