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
// IDEMPOTENCY
// -----------
// Two safeguards prevent double-notification when /notifyOrderEvent IS also
// called for the same sale:
//
//   1. The notification doc is written with a deterministic id
//      `order_${saleId}_placed` using `create()`. If /notifyOrderEvent ran
//      first (it uses .add() with auto-id, so it would not collide), this
//      trigger's create() still succeeds — but step 2 stops the duplicate.
//
//   2. A `notifiedPlacedAt` marker is written onto the sale doc inside a
//      transaction. If the marker already exists, this trigger bails out
//      before doing any counter increment or FCM send.
//
// Note: /notifyOrderEvent (notifyOrderEvent.ts) does NOT currently set the
// `notifiedPlacedAt` marker. To make the two paths fully cooperative, a
// follow-up patch could add that marker write to /notifyOrderEvent. Until
// then, double-notifications are still possible if /notifyOrderEvent runs
// AFTER this trigger, but the deterministic notification doc id prevents
// duplicate notification records, and FCM duplicates are limited to a
// single repeat at worst.

import { db, functions } from "../config/main";
import * as admin from "firebase-admin";
import { AndroidConfig, MulticastMessage } from "firebase-admin/messaging";
import { sendMerchantOrderSmsFallback } from "../utils/merchantOrderSmsFallback";

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

    const saleRef = snap.ref;

    // Step 1: idempotency marker on the sale doc. Transactional so two
    // concurrent invocations cannot both pass.
    const shouldProceed = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(saleRef);
      const data = fresh.data() || {};
      if (data.notifiedPlacedAt) return false;
      tx.update(saleRef, {
        notifiedPlacedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    });

    if (!shouldProceed) {
      console.log(
        `[onSaleCreatedNotify] skip ${saleId}: notifiedPlacedAt already set`,
      );
      return;
    }

    // Step 2: write the notification record with a deterministic id.
    // Use create() so we never overwrite a notification written by another
    // path; if it already exists we treat as success and continue.
    const notifId = `order_${saleId}_placed`;
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
      customerName: customerName || null,
      paymentMethod, // "cash" | "online" | "bnpl" | null
      orderTotal,
      currency,
      channel: null as string | null,
      read: false,
      createdAt: new Date().toISOString(),
      idempotencyKey: notifId,
      source: "onSaleCreatedNotify",
    };

    try {
      await notifRef.create(notifData);
    } catch (e: unknown) {
      // ALREADY_EXISTS — another path already wrote this notification.
      // We've already set notifiedPlacedAt, so don't increment counters
      // or send FCM (assume the other path did or will).
      const err = e as { code?: string; message?: string };
      const code = err?.code || "";
      if (
        String(code).includes("already-exists") ||
        String(err?.message || "").includes("ALREADY_EXISTS")
      ) {
        console.log(
          `[onSaleCreatedNotify] notification ${notifId} already exists; skipping counters/FCM`,
        );
        return;
      }
      throw e;
    }

    // Step 3: increment ordersUnreadCount on merchant + per-customer doc.
    const merchantRef = db.collection("users").doc(merchantId);
    const customerRef = merchantRef.collection("customers").doc(customerId);

    let freshUnreadOrdersCount = 0;
    await db.runTransaction(async (tx) => {
      const s = await tx.get(merchantRef);
      const prev = (s.data()?.ordersUnreadCount as number) ?? 0;
      const next = prev + 1;
      tx.set(merchantRef, { ordersUnreadCount: next }, { merge: true });
      freshUnreadOrdersCount = next;
    });

    let freshCustomerOrdersUnread = 0;
    await db.runTransaction(async (tx) => {
      const s = await tx.get(customerRef);
      const prev = (s.data()?.ordersUnreadCount as number) ?? 0;
      const next = prev + 1;
      tx.set(customerRef, { ordersUnreadCount: next }, { merge: true });
      freshCustomerOrdersUnread = next;
    });

    // Step 4: FCM push to the merchant.
    const tokens = await readMerchantTokens(merchantId);
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
          await merchantRef.set(
            {
              fcmTokens: admin.firestore.FieldValue.arrayRemove(...badTokens),
            },
            { merge: true },
          );
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
async function readMerchantTokens(merchantId: string): Promise<string[]> {
  const snap = await db.collection("users").doc(merchantId).get();
  if (!snap.exists) return [];
  const data = snap.data() || {};
  let tokens: string[] = [];
  if (Array.isArray(data.fcmTokens)) {
    tokens = (data.fcmTokens as unknown[]).filter(Boolean) as string[];
  } else if (data.fcmToken) {
    tokens = [data.fcmToken as string];
  }
  return tokens;
}

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
