import { functions, db } from "../config/main";
import { AndroidConfig, MulticastMessage } from "firebase-admin/messaging";
import * as admin from "firebase-admin";
import { sendMerchantOrderSmsFallback } from "../utils/merchantOrderSmsFallback";

/** Shape of an order notification record stored in Firestore. */
interface OrderNotificationData {
  type: "ORDER_EVENT";
  eventType: "ORDER_PLACED" | "ONLINE_PAYMENT_CONFIRMED";
  orderId: string;
  customerName: string | null;
  paymentMethod: "cash" | "online" | null;
  orderTotal: number | null;
  currency: string;
  channel: string | null;
  read: boolean;
  createdAt: string; // ISO string
  idempotencyKey: string | null;
}

/**
 * Writes a notification record into users/{merchantId}/notifications.
 *
 * @param {string} merchantId - Merchant document ID.
 * @param {OrderNotificationData} data - Notification payload to persist.
 * @return {Promise<FirebaseFirestore.DocumentReference>} The created doc ref.
 */
async function writeNotificationRecord(
  merchantId: string,
  data: OrderNotificationData,
): Promise<FirebaseFirestore.DocumentReference> {
  const col = db
    .collection("users")
    .doc(merchantId)
    .collection("notifications");
  return await col.add(data);
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
  req: import("firebase-functions").https.Request,
  res: import("firebase-functions").Response,
): Promise<void> {
  try {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }

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

    const customerRef = db
      .collection("users")
      .doc(merchantId)
      .collection("customers")
      .doc(customerId);

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

    const merchantData = merchantSnap.data() || {};
    let tokens: string[] = [];
    if (Array.isArray(merchantData.fcmTokens)) {
      tokens = (merchantData.fcmTokens as unknown[]).filter(
        Boolean,
      ) as string[];
    } else if (merchantData.fcmToken) {
      tokens = [merchantData.fcmToken as string];
    }

    // 1) Create unread notification record
    const notifData: OrderNotificationData = {
      type: "ORDER_EVENT",
      eventType,
      orderId,
      customerName: customerName ?? null,
      paymentMethod: (paymentMethod ?? null) as "cash" | "online" | null,
      orderTotal: typeof orderTotal === "number" ? orderTotal : null,
      currency,
      channel: channel ?? null,
      read: false,
      createdAt: new Date().toISOString(),
      idempotencyKey: idempotencyKey ?? null,
    };
    const notifRef = await writeNotificationRecord(merchantId, notifData);

    // 2) Atomically increment ordersUnreadCount and read the fresh value
    let freshUnreadOrdersCount = 0;
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(merchantRef);
      const prev = (snap.data()?.ordersUnreadCount as number) ?? 0;
      const next = prev + 1;
      tx.set(merchantRef, { ordersUnreadCount: next }, { merge: true });
      freshUnreadOrdersCount = next;
    });

    let freshCustomerOrdersUnread = 0;
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(customerRef);
      const prev = (snap.data()?.ordersUnreadCount as number) ?? 0;
      const next = prev + 1;
      tx.set(customerRef, { ordersUnreadCount: next }, { merge: true });
      freshCustomerOrdersUnread = next;
    });

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
            await merchantRef.set(
              {
                fcmTokens: admin.firestore.FieldValue.arrayRemove(...badTokens),
              },
              { merge: true },
            );
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
export const notifyOrderEvent = functions.https.onRequest(
  notifyOrderEventHandler,
);

/**
 * Mark all ORDER_EVENT notifications as read and reset ordersUnreadCount.
 *
 * @param {import("firebase-functions").https.Request} req - Incoming HTTP request (POST).
 * @param {import("firebase-functions").Response} res - Outgoing HTTP response.
 * @returns {Promise<void>} Resolves when unread orders are cleared.
 * Body: { merchantId: string; limit?: number }
 */
export const markOrdersAsRead = functions.https.onRequest(
  async (
    req: import("firebase-functions").https.Request,
    res: import("firebase-functions").Response,
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

      const userRef = db.collection("users").doc(merchantId);
      const notifCol = userRef.collection("notifications");

      const unreadSnap = await notifCol
        .where("type", "==", "ORDER_EVENT")
        .where("read", "==", false)
        .orderBy("createdAt", "desc")
        .limit(Math.min(Number(limit) || 200, 500))
        .get();

      const batch = db.batch();
      unreadSnap.docs.forEach((d) =>
        batch.update(d.ref, {
          read: true,
          readAt: new Date().toISOString(),
        }),
      );
      batch.set(userRef, { ordersUnreadCount: 0 }, { merge: true });
      await batch.commit();

      res
        .status(200)
        .json({ message: "Orders marked as read", cleared: unreadSnap.size });
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error(e);
      res.status(500).json({ error: "Internal Server Error" });
    }
  },
);
