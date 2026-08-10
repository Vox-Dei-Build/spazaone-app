import { functions, db } from "../config/main";
import { AndroidConfig, MulticastMessage } from "firebase-admin/messaging";
import * as admin from "firebase-admin";
import { sendMerchantOrderSmsFallback } from "../utils/merchantOrderSmsFallback";
import {
  readStoreNotificationTokens,
  removeInvalidStoreNotificationTokens,
} from "../notifications/storeNotificationTokens";
import {
  incrementUnreadCount,
  markOrderNotificationsRead,
  unreadEventDocumentId,
} from "../notifications/unreadCounts";
import {
  authenticateFirebaseRequest,
  requireBotRequest,
} from "../security/requestAuth";
import { assertStoreAccess } from "../stores/storeAccess";

/** Shape of an order notification record stored in Firestore. */
interface OrderNotificationData {
  type: "ORDER_EVENT";
  eventType: "ORDER_PLACED" | "ONLINE_PAYMENT_CONFIRMED";
  orderId: string;
  customerId: string;
  customerName: string | null;
  paymentMethod: "cash" | "online" | null;
  orderTotal: number | null;
  currency: string;
  channel: string | null;
  read: boolean;
  createdAt: string; // ISO string
  idempotencyKey: string | null;
  unreadEventId: string;
}

/**
 * Cloud Function handler: notify merchant about order events (placed or paid),
 * store an unread notification, and increment ordersUnreadCount.
 *
 * @param {import("firebase-functions").https.Request} req - Incoming HTTP request (POST).
 * @param {import("firebase-functions").Response} res - Outgoing HTTP response.
 * @returns {Promise<void>} Resolves when the notification has been processed.
 */
// eslint-disable-next-line valid-jsdoc, require-jsdoc
async function notifyOrderEventHandler(
  req: import("firebase-functions/v1").https.Request,
  res: import("firebase-functions/v1").Response,
): Promise<void> {
  try {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    if (!requireBotRequest(req, res)) return;

    const {
      merchantId,
      customerId,
      orderId,
      orderTotal,
      currency = "ZAR",
      customerName,
      paymentMethod,
      eventType,
      channel,
      idempotencyKey,
    } = (req.body || {}) as {
      merchantId?: string;
      customerId?: string;
      orderId?: string;
      orderTotal?: number;
      currency?: string;
      customerName?: string;
      paymentMethod?: "cash" | "online";
      eventType?: "ORDER_PLACED" | "ONLINE_PAYMENT_CONFIRMED";
      channel?: string;
      idempotencyKey?: string;
    };

    if (!merchantId || !orderId || !eventType) {
      res.status(400).json({
        error: "Missing required fields: merchantId, orderId, eventType",
      });
      return;
    }

    if (!customerId) {
      res.status(400).json({ error: "Missing customerId" });
      return;
    }

    if (!["ORDER_PLACED", "ONLINE_PAYMENT_CONFIRMED"].includes(eventType)) {
      res.status(400).json({ error: "Invalid eventType" });
      return;
    }

    const merchantRef = db.collection("users").doc(merchantId);
    const merchantSnap = await merchantRef.get();
    if (!merchantSnap.exists) {
      res.status(404).json({ error: "Merchant not found" });
      return;
    }

    // The bot credential authorizes the caller, while the stored order binding
    // authorizes the target. A valid bot token must not be enough to create a
    // notification against an unrelated store/customer pair.
    const legacyOrder = await merchantRef
      .collection("sales")
      .doc(orderId)
      .get();
    const commerceOrder = legacyOrder.exists
      ? null
      : await db.collection("commerceOrders").doc(orderId).get();
    const storedOrder = legacyOrder.exists
      ? legacyOrder.data()
      : commerceOrder?.data();
    if (!storedOrder) {
      res.status(404).json({ error: "Order not found" });
      return;
    }
    if (
      (!legacyOrder.exists &&
        String(storedOrder.sellerId ?? "") !== merchantId) ||
      String(storedOrder.customerId ?? "") !== customerId
    ) {
      res
        .status(403)
        .json({ error: "Order does not belong to this customer." });
      return;
    }

    const tokens = await readStoreNotificationTokens(merchantId);

    // 1) Create unread notification record
    const eventKey = `order:${orderId}:${eventType}`;
    const unreadEventId = unreadEventDocumentId(eventKey);
    const notifData: OrderNotificationData = {
      type: "ORDER_EVENT",
      eventType,
      orderId,
      customerId,
      customerName: customerName ?? null,
      paymentMethod: (paymentMethod ?? null) as "cash" | "online" | null,
      orderTotal: typeof orderTotal === "number" ? orderTotal : null,
      currency,
      channel: channel ?? null,
      read: false,
      createdAt: new Date().toISOString(),
      idempotencyKey: idempotencyKey ?? null,
      unreadEventId,
    };
    const notifRef = merchantRef.collection("notifications").doc(unreadEventId);

    // 2) Increment the canonical counters exactly once. The on-create trigger
    // uses the same key, so HTTP retries and trigger overlap cannot double the
    // merchant/customer badges.
    const unread = await incrementUnreadCount({
      merchantId,
      customerId,
      kind: "orders",
      eventKey,
      notification: { ref: notifRef, data: notifData },
    });
    const freshUnreadOrdersCount = unread.merchant.orders;
    const freshCustomerOrdersUnread = unread.customer.orders;
    if (unread.deduped) {
      res.status(200).json({
        message: "Order notification already processed.",
        deduped: true,
        unreadOrdersCount: freshUnreadOrdersCount,
        unreadTotalCount: unread.merchant.total,
      });
      return;
    }

    // 3) Build push message
    const title =
      eventType === "ONLINE_PAYMENT_CONFIRMED"
        ? "Online order paid 💳"
        : "New order placed 🛒";

    const amountString =
      typeof orderTotal === "number"
        ? `${currency} ${orderTotal.toFixed(2)}`
        : undefined;

    const parts = [
      customerName ? `From: ${customerName}` : null,
      amountString ? `Total: ${amountString}` : null,
      paymentMethod
        ? `Payment: ${paymentMethod === "online" ? "Online" : "Cash"}`
        : null,
    ].filter(Boolean) as string[];
    const body = parts.length ? parts.join(" · ") : "Open to view details.";

    const androidConfig: AndroidConfig = {
      priority: "high",
      notification: {
        channelId: "default_channel",
        sound: "default",
      },
    };

    const dataPayload: Record<string, string> = {
      type: "ORDER_EVENT",
      eventType,
      orderId,
      merchantId,
      paymentMethod: paymentMethod || "",
      orderTotal: typeof orderTotal === "number" ? String(orderTotal) : "",
      currency,
      channel: channel || "",
      route: `orders/detail?orderId=${orderId}`,
      idempotencyKey: idempotencyKey || "",
      unreadOrdersCount: String(freshUnreadOrdersCount),
      unreadTotalCount: String(unread.merchant.total),
    };

    dataPayload.customerOrdersUnreadCount = String(freshCustomerOrdersUnread);

    if (tokens.length) {
      const message: MulticastMessage = {
        tokens,
        notification: { title, body },
        android: androidConfig,
        data: dataPayload,
      };

      try {
        const fcmResponse = await admin
          .messaging()
          .sendEachForMulticast(message);

        if (fcmResponse.successCount === 0) {
          await sendMerchantOrderSmsFallback({
            merchantId,
            orderId,
            eventType,
            customerName: customerName ?? null,
            orderTotal: typeof orderTotal === "number" ? orderTotal : null,
            currency,
            source: "notifyOrderEvent",
            reason: "push_zero_success",
          });
        }

        // remove bad tokens
        if (fcmResponse.failureCount > 0) {
          const badTokens = fcmResponse.responses
            .map((r, i) => ({ r, t: tokens[i] }))
            .filter(
              ({ r }) =>
                r.error &&
                String(r.error.code).includes(
                  "registration-token-not-registered",
                ),
            )
            .map(({ t }) => t);

          if (badTokens.length) {
            await removeInvalidStoreNotificationTokens(merchantId, badTokens);
          }
        }
      } catch (error: unknown) {
        const err = error as { message?: string };
        console.error(
          `[notifyOrderEvent] FCM send failed for ${orderId}:`,
          err?.message || error,
        );
        await sendMerchantOrderSmsFallback({
          merchantId,
          orderId,
          eventType,
          customerName: customerName ?? null,
          orderTotal: typeof orderTotal === "number" ? orderTotal : null,
          currency,
          source: "notifyOrderEvent",
          reason: "push_error",
        });
      }
    } else {
      await sendMerchantOrderSmsFallback({
        merchantId,
        orderId,
        eventType,
        customerName: customerName ?? null,
        orderTotal: typeof orderTotal === "number" ? orderTotal : null,
        currency,
        source: "notifyOrderEvent",
        reason: "no_tokens",
      });
    }

    res.status(200).json({
      message: "Order notification processed.",
      notificationId: notifRef.id,
      unreadOrdersCount: freshUnreadOrdersCount,
    });
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error("Error notifying order event:", error);
    res.status(500).json({ error: "Internal Server Error" });
  }
}

/**
 * Cloud Function export bound to the HTTP handler for order events.
 * (Wrapper with no parameters; see {@link notifyOrderEventHandler} for details.)
 */
export const notifyOrderEvent = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(notifyOrderEventHandler);

/**
 * Mark a bounded set of ORDER_EVENT notifications as read and subtract only
 * those records from the compatible unread counters.
 *
 * @param {import("firebase-functions").https.Request} req - Incoming HTTP request (POST).
 * @param {import("firebase-functions").Response} res - Outgoing HTTP response.
 * @returns {Promise<void>} Resolves when unread orders are cleared.
 * Body: { merchantId: string; limit?: number }
 */
export const markOrdersAsRead = functions.https.onRequest(
  async (
    req: import("firebase-functions/v1").https.Request,
    res: import("firebase-functions/v1").Response,
  ): Promise<void> => {
    try {
      if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
      }

      const { merchantId, limit = 200 } = (req.body || {}) as {
        merchantId?: string;
        limit?: number;
      };
      if (!merchantId) {
        res.status(400).json({ error: "Missing merchantId" });
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
      const notifCol = userRef.collection("notifications");

      const unreadSnap = await notifCol
        .where("type", "==", "ORDER_EVENT")
        .where("read", "==", false)
        .orderBy("createdAt", "desc")
        .limit(Math.max(1, Math.min(Number(limit) || 150, 150)))
        .get();
      const result = await markOrderNotificationsRead({
        merchantId,
        notificationIds: unreadSnap.docs.map((doc) => doc.id),
      });

      res.status(200).json({
        message: "Orders marked as read",
        cleared: result.cleared,
        unreadOrdersCount: result.counts.orders,
        unreadTotalCount: result.counts.total,
      });
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error(e);
      res.status(500).json({ error: "Internal Server Error" });
    }
  },
);
