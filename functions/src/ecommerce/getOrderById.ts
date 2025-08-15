// functions/src/http/getOrderById.ts
import { db, functions } from "../config/main";

export const getOrderById = functions.https.onRequest(async (req, res) => {
  try {
    const { merchantId, orderId } = req.body || {};
    if (!merchantId || !orderId) {
      res.status(400).json({ error: "merchantId and orderId are required" });
    }
    const ref = db
      .collection("users")
      .doc(merchantId)
      .collection("sales")
      .doc(orderId);
    const snap = await ref.get();
    if (!snap.exists) res.status(404).json({ error: "Order not found" });

    const data = snap.data() || {};
    res.status(200).json({
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
      // add any shipping/customer fields as needed
    });
  } catch (err: any) {
    console.error("getOrderById", err);
    res.status(500).json({ error: "Failed to fetch order" });
  }
});
