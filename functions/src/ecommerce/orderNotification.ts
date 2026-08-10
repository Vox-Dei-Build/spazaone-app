// functions/src/orderNotifications.ts
import { functions, db } from "../config/main";
import { markOrderNotificationsRead } from "../notifications/unreadCounts";
import { authenticateFirebaseRequest } from "../security/requestAuth";
import { assertStoreAccess } from "../stores/storeAccess";

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
      const uid = await authenticateFirebaseRequest(req, res, {
        requireAppCheck: true,
      });
      if (!uid) return;
      try {
        await assertStoreAccess(uid, merchantId);
      } catch (error) {
        res.status(403).json({ error: "Access denied." });
        return;
      }

      const userRef = db.collection("users").doc(merchantId);
      // mark only this customer's ORDER_EVENT notifications as read (optional but nice)
      const notifCol = userRef.collection("notifications");
      const unreadSnap = await notifCol
        .where("type", "==", "ORDER_EVENT")
        .where("read", "==", false)
        .where("customerId", "==", customerId)
        .limit(Math.max(1, Math.min(Number(limit) || 150, 150)))
        .get();
      const result = await markOrderNotificationsRead({
        merchantId,
        customerId,
        notificationIds: unreadSnap.docs.map((doc) => doc.id),
      });

      res.status(200).json({
        message: "Customer orders marked as read",
        cleared: result.cleared,
        unreadOrdersCount: result.counts.orders,
        unreadTotalCount: result.counts.total,
      });
    } catch (e) {
      console.error(e);
      res.status(500).json({ error: "Internal Server Error" });
    }
  },
);
