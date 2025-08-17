import { db, functions } from "../config/main";

/**
 * List orders (sales) for a customer with normalized fields for UI.
 * Returns: { orders: [{ id, status, total, itemsCount, createdAt, items? }] }
 */
export const getCustomerOrders = functions.https.onCall(async (data) => {
  try {
    const merchantId = data.merchantId as string;
    const customerId = data.customerId as string;

    if (!merchantId || !customerId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "merchantId and customerId are required",
      );
    }

    const qs = await db
      .collection("users")
      .doc(merchantId)
      .collection("sales")
      .where("customerId", "==", customerId)
      .orderBy("dateAdded", "desc")
      .limit(50)
      .get();

    const orders = qs.docs.map((d) => {
      const s: any = d.data() || {};
      // Prefer saved amount/itemsCount; fall back to products map if missing
      const total = Number(s.amount ?? 0);
      const itemsCount = Number(
        s.itemsCount ??
          (s.products && typeof s.products === "object"
            ? Object.values(s.products).reduce(
                (acc: number, q: any) => acc + Number(q || 0),
                0,
              )
            : 0),
      );

      return {
        id: d.id,
        status: s.status || "pending",
        total,
        itemsCount,
        createdAt: s.dateAdded || s.createdAt || null,
        items: Array.isArray(s.items) ? s.items : undefined, // includes snapshots if you wrote them
      };
    });

    return { orders };
  } catch (error: any) {
    console.error("Error fetching orders:", error?.message || error);
    throw new functions.https.HttpsError("internal", "Failed to fetch orders");
  }
});
