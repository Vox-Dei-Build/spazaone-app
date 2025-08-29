// functions/src/orderNotifications.ts
import { functions, db } from "../config/main";

export const markCustomerOrdersAsRead = functions.https.onRequest(
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
      }
      const { merchantId, customerId, limit = 200 } = req.body || {};
      if (!merchantId || !customerId) {
        res.status(400).json({ error: "Missing merchantId or customerId" });
        return;
      }

      const userRef = db.collection("users").doc(merchantId);
      const customerRef = userRef.collection("customers").doc(customerId);

      // mark only this customer's ORDER_EVENT notifications as read (optional but nice)
      const notifCol = userRef.collection("notifications");
      const unreadSnap = await notifCol
        .where("type", "==", "ORDER_EVENT")
        .where("read", "==", false)
        .where("orderId", "!=", null) // ensure field exists for index stability
        .orderBy("createdAt", "desc")
        .limit(Math.min(Number(limit) || 200, 500))
        .get();

      const batch = db.batch();
      unreadSnap.docs.forEach((d) => {
        const data = d.data() as any;
        if (data.customerId === customerId) {
          batch.update(d.ref, { read: true, readAt: new Date().toISOString() });
        }
      });

      // reset ONLY this customer's counter
      batch.set(customerRef, { ordersUnreadCount: 0 }, { merge: true });
      await batch.commit();

      res.status(200).json({ message: "Customer orders marked as read" });
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: "Internal Server Error" });
    }
  },
);
