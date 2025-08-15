// functions/src/http/getOrderById.ts
import { db, functions } from "../config/main";

export const getOrderById = functions.https.onCall(async (data) => {
  try {
    const merchantId = data.merchantId as string;
    const orderId = data.orderId as string;
    if (!merchantId || !orderId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "merchantId and orderId are required",
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

    const data = snap.data() || {};
    return {
      id: snap.id,
      status: data.status || "pending",
      total: Number(data.amount ?? 0),
      itemsCount: Number(
        data.itemsCount ??
          (data.products && typeof data.products === "object"
            ? Object.values(data.products).reduce(
                (acc: number, q: any) => acc + Number(q || 0),
                0,
              )
            : 0),
      ),
      paymentMethod: data.paymentMethod || "",
      paymentStatus: data.paymentStatus || "",
      createdAt: data.dateAdded || data.createdAt || null,
      items: Array.isArray(data.items) ? data.items : [],
      collected: data.collected || false,
    };
  } catch (err: any) {
    console.error("getOrderById", err);
    throw new functions.https.HttpsError(
      "internal",
      "Failed to fetch order",
    );
  }
});
