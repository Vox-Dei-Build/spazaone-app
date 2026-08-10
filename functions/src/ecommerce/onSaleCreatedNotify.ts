// functions/src/ecommerce/onSaleCreatedNotify.ts
//
// Defense-in-depth Firestore trigger: when a new sale doc is created under
// users/{merchantId}/sales/{saleId}, ensure the merchant is notified
// (notification record + ordersUnreadCount increments + FCM push).
//
// This protects against the case where the customer-side caller (Botpress
// today) creates the sale via /checkoutCart but fails to subsequently call
// /notifyOrderEvent. Without this trigger, the order silently lands in
// Firestore and the merchant sees no badge / no push.
//
// The trigger and /notifyOrderEvent share one deterministic unread-event key.
// A single transaction creates that marker, the notification record, and the
// compatible counters. Retries and overlapping paths therefore cannot create
// a second badge or push.

import { db, functions } from "../config/main";
import * as admin from "firebase-admin";
import { AndroidConfig, MulticastMessage } from "firebase-admin/messaging";
import { sendMerchantOrderSmsFallback } from "../utils/merchantOrderSmsFallback";
import {
  readStoreNotificationTokens,
  removeInvalidStoreNotificationTokens,
} from "../notifications/storeNotificationTokens";
import {
  incrementUnreadCount,
  unreadEventDocumentId,
} from "../notifications/unreadCounts";

/**
 * Firestore onCreate trigger for users/{merchantId}/sales/{saleId}.
 *
 * Fires once per new sale; idempotent against /notifyOrderEvent.
 *
 * @returns {Promise<void>}
 */
export const onSaleCreatedNotify = functions.firestore
  .document("users/{merchantId}/sales/{saleId}")
  .onCreate(async (snap, context) => {
    const merchantId = context.params.merchantId as string;
    const saleId = context.params.saleId as string;
    const sale = snap.data() || {};

    // Skip if the sale was created already-cancelled (defensive; should not
    // happen in the normal flow, but supersede paths or admin tooling could).
    const status = String(sale.status || "").toLowerCase();
    if (status === "cancelled") {
      console.log(
        `[onSaleCreatedNotify] skip ${saleId}: status=cancelled at create`,
      );
      return;
    }

    const customerId = String(sale.customerId || "");
    if (!customerId) {
      console.warn(
        `[onSaleCreatedNotify] skip ${saleId}: no customerId on sale doc`,
      );
      return;
    }

    // The unread event is the durable idempotency marker. Its transaction also
    // writes this notification, so a retry cannot leave a counter without a
    // read-clear record (or vice versa).
    const eventKey = `order:${saleId}:ORDER_PLACED`;
    const unreadEventId = unreadEventDocumentId(eventKey);
    const notifId = unreadEventId;
    const notifRef = db
      .collection("users")
      .doc(merchantId)
      .collection("notifications")
      .doc(notifId);

    const customerName = await fetchCustomerName(merchantId, customerId);
    const orderTotal =
      typeof sale.amount === "number"
        ? sale.amount
        : Number(sale.amount ?? 0) || null;
    const currency = (sale.currency as string) || "ZAR";
    const paymentMethod = derivePaymentMethod(sale);

    const notifData = {
      type: "ORDER_EVENT" as const,
      eventType: "ORDER_PLACED" as const,
      orderId: saleId,
      customerId,
      customerName: customerName || null,
      paymentMethod, // "cash" | "online" | "bnpl" | null
      orderTotal,
      currency,
      channel: null as string | null,
      read: false,
      createdAt: new Date().toISOString(),
      idempotencyKey: notifId,
      unreadEventId: unreadEventDocumentId(eventKey),
      source: "onSaleCreatedNotify",
    };

    // Share one exactly-once counter path with /notifyOrderEvent.
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
      console.log(
        `[onSaleCreatedNotify] skip ${saleId}: unread event already processed`,
      );
      return;
    }

    // Step 4: FCM push to the merchant.
    const tokens = await readStoreNotificationTokens(merchantId);
    if (!tokens.length) {
      console.warn(
        `[onSaleCreatedNotify] no FCM tokens for merchant ${merchantId}`,
      );
      await sendMerchantOrderSmsFallback({
        merchantId,
        orderId: saleId,
        eventType: "ORDER_PLACED",
        customerName: customerName || null,
        orderTotal,
        currency,
        source: "onSaleCreatedNotify",
        reason: "no_tokens",
      });
      return;
    }

    const isOrderRequest = sale.orderRequest === true;
    const title = isOrderRequest
      ? "New WhatsApp order request"
      : "New order placed 🛒";
    const amountString =
      typeof orderTotal === "number"
        ? `${currency} ${orderTotal.toFixed(2)}`
        : undefined;
    const parts = [
      customerName ? `From: ${customerName}` : null,
      amountString ? `Total: ${amountString}` : null,
      paymentMethod
        ? `Payment: ${paymentMethod === "online" ? "Online" : paymentMethod === "cash" ? "Cash" : "BNPL"}`
        : null,
    ].filter(Boolean) as string[];
    const body = parts.length ? parts.join(" · ") : "Open to view details.";

    const androidConfig: AndroidConfig = {
      priority: "high",
      notification: { channelId: "default_channel", sound: "default" },
    };

    const dataPayload: Record<string, string> = {
      type: "ORDER_EVENT",
      eventType: "ORDER_PLACED",
      orderId: saleId,
      merchantId,
      orderRequest: isOrderRequest ? "true" : "false",
      paymentMethod: paymentMethod || "",
      orderTotal: typeof orderTotal === "number" ? String(orderTotal) : "",
      currency,
      channel: "",
      route: `orders/detail?orderId=${saleId}`,
      idempotencyKey: notifId,
      unreadOrdersCount: String(freshUnreadOrdersCount),
      unreadTotalCount: String(unread.merchant.total),
      customerOrdersUnreadCount: String(freshCustomerOrdersUnread),
      source: "onSaleCreatedNotify",
    };

    const message: MulticastMessage = {
      tokens,
      notification: { title, body },
      android: androidConfig,
      data: dataPayload,
    };

    try {
      const fcmResponse = await admin.messaging().sendEachForMulticast(message);

      if (fcmResponse.successCount === 0) {
        await sendMerchantOrderSmsFallback({
          merchantId,
          orderId: saleId,
          eventType: "ORDER_PLACED",
          customerName: customerName || null,
          orderTotal,
          currency,
          source: "onSaleCreatedNotify",
          reason: "push_zero_success",
        });
      }

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
    } catch (e: unknown) {
      const err = e as { message?: string };
      console.error(
        `[onSaleCreatedNotify] FCM send failed for ${saleId}:`,
        err?.message || e,
      );
      await sendMerchantOrderSmsFallback({
        merchantId,
        orderId: saleId,
        eventType: "ORDER_PLACED",
        customerName: customerName || null,
        orderTotal,
        currency,
        source: "onSaleCreatedNotify",
        reason: "push_error",
      });
    }
  });

/**
 * Fetch a best-effort customer display name. Returns "" if missing.
 *
 * @param {string} merchantId Merchant Firestore user id.
 * @param {string} customerId Customer subdoc id.
 * @returns {Promise<string>} Display name or empty string.
 */
async function fetchCustomerName(
  merchantId: string,
  customerId: string,
): Promise<string> {
  try {
    const cs = await db
      .collection("users")
      .doc(merchantId)
      .collection("customers")
      .doc(customerId)
      .get();
    return (cs.get("name") || cs.get("displayName") || "") as string;
  } catch {
    return "";
  }
}

/**
 * Read the merchant's FCM tokens. Mirrors notifyOrderEvent.ts:113-119
 * (array-first, scalar-fallback) to keep behavior consistent.
 *
 * @param {string} merchantId Merchant Firestore user id.
 * @returns {Promise<string[]>} Array of non-empty FCM tokens.
 */
/**
 * Derive a normalized paymentMethod from the sale doc.
 * checkoutCart writes `type` as "Cash" | "Online" | "BNPL".
 *
 * @param {FirebaseFirestore.DocumentData} sale Sale document data.
 * @returns {"cash"|"online"|"bnpl"|null} Lowercased method or null.
 */
function derivePaymentMethod(
  sale: FirebaseFirestore.DocumentData,
): "cash" | "online" | "bnpl" | null {
  const t = String(sale.type || sale.paymentMethod || "")
    .trim()
    .toLowerCase();
  if (t === "cash") return "cash";
  if (t === "online") return "online";
  if (t === "bnpl" || t === "buy now pay later") return "bnpl";
  return null;
}
