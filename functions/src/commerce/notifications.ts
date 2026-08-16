import * as admin from "firebase-admin";
import axios from "axios";
import { FieldValue } from "firebase-admin/firestore";
import twilio from "twilio";
import { db, functions } from "../config/main";
import {
  readStoreNotificationTokens,
  removeInvalidStoreNotificationTokens,
} from "../notifications/storeNotificationTokens";
import { formatPhoneNumber } from "../utils/phoneUtils";

export type OrderNotice = {
  orderId: string;
  sellerId: string;
  customerId?: string;
  buyerName: string;
  buyerPhone: string;
  status: string;
  paymentMethod?: string;
  amountDueMinor: number;
  trackingNumber?: string;
  trackingUrl?: string;
  notifyBuyer?: boolean;
  unreadOrdersCount?: number;
  unreadTotalCount?: number;
  orderKind?: "merchant_stock" | "supplier_delivery";
  eventKey?: string;
  noticeKind?: "order" | "account_payment";
};

export type CustomerNotificationDelivery =
  | "sent"
  | "queued"
  | "not_deliverable"
  | "skipped"
  | "failed";

export type CommerceNotificationResult = {
  notificationId?: string;
  customer: CustomerNotificationDelivery;
  buyerResult: string;
  sellerResult: string;
};

type NotifyCommerceOrderOptions = {
  previousBuyerResult?: string;
  previousSellerResult?: string;
  notificationId?: string;
};

type OutboxNotice = Omit<OrderNotice, "notifyBuyer"> & {
  notifyBuyer: boolean;
};

type OutboxDocument = {
  notice?: OutboxNotice;
  state?: string;
  attempts?: number;
  availableAtMs?: number;
  leaseUntilMs?: number;
  buyerResult?: string;
  sellerResult?: string;
};

const COMMERCE_NOTIFICATION_OUTBOX = "commerceNotificationOutbox";
const NOTIFICATION_LEASE_MS = 2 * 60 * 1000;
const NOTIFICATION_RETRY_DELAYS_MS = [60_000, 5 * 60_000, 30 * 60_000];
const MAX_NOTIFICATION_ATTEMPTS = NOTIFICATION_RETRY_DELAYS_MS.length + 1;
const TERMINAL_BUYER_RESULTS = new Set([
  "whatsapp_sent",
  "botpress_queued",
  "sms_sent",
  "skipped_no_phone",
  "skipped_conversational_reply",
]);
const TERMINAL_SELLER_RESULTS = new Set(["push_sent", "skipped_no_tokens"]);

function statusMessage(order: OrderNotice): string {
  const reference = order.orderId.slice(0, 8).toUpperCase();
  const amount = `R ${(order.amountDueMinor / 100).toFixed(2)}`;
  if (order.noticeKind === "account_payment") {
    return (
      `Spaza One: Your account payment of ${amount} was confirmed ` +
      `(reference ${reference}). Your updated balance is available from the shop.`
    );
  }
  switch (order.status) {
    case "pending_payment":
    case "awaiting_payment":
      if (order.paymentMethod === "manual") {
        return (
          `Spaza One: Order request ${reference} (${amount}) was sent to the seller. ` +
          "They will contact you to arrange payment and confirm the order."
        );
      }
      return `Spaza One: Order ${reference} is awaiting payment.`;
    case "paid":
      return (
        `Spaza One: Payment received for order ${reference} (${amount}). ` +
        "We will update you when your order is being prepared."
      );
    case "submitted_for_fulfilment":
    case "preparing":
      return `Spaza One: Order ${reference} is being prepared.`;
    case "shipped":
    case "on_the_way": {
      const tracking = order.trackingNumber
        ? ` Tracking: ${order.trackingNumber}.`
        : "";
      const link = order.trackingUrl ? ` Track: ${order.trackingUrl}` : "";
      return `Spaza One: Order ${reference} is on the way.` + tracking + link;
    }
    case "delivered":
      return (
        `Spaza One: Order ${reference} has been marked delivered. ` +
        "Thank you for shopping with Spaza One."
      );
    case "cancelled":
      return `Spaza One: Order ${reference} was cancelled.`;
    case "refunded":
      return `Spaza One: The refund for order ${reference} has been confirmed.`;
    default:
      return `Spaza One: Order ${reference} is now ${order.status}.`;
  }
}

async function notifyBuyer(order: OrderNotice): Promise<string> {
  const to = formatPhoneNumber(order.buyerPhone);
  if (!to) return "skipped_no_phone";
  if (order.noticeKind === "account_payment") {
    const mode = String(process.env.BOTPRESS_PROVIDER_MODE ?? "disabled")
      .trim()
      .toLowerCase();
    if (mode === "stub") return "botpress_queued";
    const url = String(
      process.env.BOTPRESS_PAYMENT_REQUEST_WEBHOOK_URL ?? "",
    ).trim();
    const secret = String(
      process.env.BOTPRESS_PAYMENT_REQUEST_WEBHOOK_SECRET ?? "",
    ).trim();
    const templateName = String(
      process.env.BOTPRESS_PAYMENT_CONFIRMATION_TEMPLATE_NAME ?? "",
    ).trim();
    const templateLanguage = String(
      process.env.BOTPRESS_PAYMENT_CONFIRMATION_TEMPLATE_LANGUAGE ?? "en",
    ).trim();
    if (
      !["test", "live"].includes(mode) ||
      !/^https:\/\//.test(url) ||
      !secret ||
      !templateName
    ) {
      return "skipped_not_configured";
    }
    const reference = order.orderId.slice(0, 8).toUpperCase();
    const amount = `R ${(order.amountDueMinor / 100).toFixed(2)}`;
    const response = await axios.post(
      url,
      {
        schemaVersion: 1,
        eventType: "account_payment_confirmation",
        userPhone: to,
        templateName,
        templateLanguage,
        templateVariables: {
          customerName: order.buyerName || "Customer",
          amount,
          reference,
        },
        merchantId: order.sellerId,
        customerId: order.customerId ?? "",
        paymentIntentId: order.orderId,
      },
      {
        headers: {
          "Content-Type": "application/json",
          "x-bp-secret": secret,
        },
        timeout: 15_000,
        validateStatus: () => true,
      },
    );
    return response.status >= 200 && response.status < 300
      ? "botpress_queued"
      : "failed";
  }
  const config = functions.config().twilio ?? {};
  const accountSid = process.env.TWILIO_ACCOUNT_SID || config.sid;
  const authToken = process.env.TWILIO_AUTH_TOKEN || config.token;
  const whatsappFrom =
    process.env.TWILIO_WHATSAPP_NUMBER ||
    config.customer_whatsapp_number ||
    config.number;
  const smsFrom =
    process.env.TWILIO_SMS_NUMBER || config.sms_number || config.number;
  if (!accountSid || !authToken) return "skipped_not_configured";

  const client = twilio(accountSid, authToken);
  const body = statusMessage(order);
  if (whatsappFrom) {
    try {
      await client.messages.create({
        to: `whatsapp:${to}`,
        from: `whatsapp:${formatPhoneNumber(String(whatsappFrom))}`,
        body,
      });
      return "whatsapp_sent";
    } catch (error) {
      console.warn("[commerce] WhatsApp update failed; trying SMS", error);
    }
  }
  if (!smsFrom) return "failed";
  try {
    await client.messages.create({
      to,
      from: formatPhoneNumber(String(smsFrom)),
      body,
    });
    return "sms_sent";
  } catch (error) {
    console.error("[commerce] buyer notification failed", error);
    return "failed";
  }
}

async function notifySeller(order: OrderNotice): Promise<string> {
  const tokens = await readStoreNotificationTokens(order.sellerId);
  if (!tokens.length) return "skipped_no_tokens";
  const reference = order.orderId.slice(0, 8).toUpperCase();
  const result = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title:
        order.noticeKind === "account_payment"
          ? "Account payment confirmed"
          : order.status === "pending_payment" &&
              order.paymentMethod === "manual"
            ? "New order request"
            : order.status === "paid"
              ? "Payment confirmed"
              : "Order updated",
      body: `Order ${reference} is ${order.status.split("_").join(" ")}.`,
    },
    data: {
      type: "COMMERCE_ORDER_EVENT",
      orderId: order.orderId,
      merchantId: order.sellerId,
      route: "/customerAccount",
      notificationType: "commerce_order",
      noticeKind: order.noticeKind ?? "order",
      action: "open_customer_orders",
      customerId: order.customerId ?? "",
      customerName: order.buyerName,
      customerNumber: order.buyerPhone,
      status: order.status,
      orderKind: order.orderKind ?? "supplier_delivery",
      ...(order.unreadOrdersCount == null
        ? {}
        : { unreadOrdersCount: String(order.unreadOrdersCount) }),
      ...(order.unreadTotalCount == null
        ? {}
        : { unreadTotalCount: String(order.unreadTotalCount) }),
    },
  });
  const invalid = result.responses
    .map((response, index) => ({ response, token: tokens[index] }))
    .filter(({ response }) =>
      String(response.error?.code ?? "").includes(
        "registration-token-not-registered",
      ),
    )
    .map(({ token }) => token);
  if (invalid.length) {
    await removeInvalidStoreNotificationTokens(order.sellerId, invalid);
  }
  return result.successCount > 0 ? "push_sent" : "failed";
}

function customerDelivery(
  buyerResult: string,
  willRetry: boolean,
): CustomerNotificationDelivery {
  if (["whatsapp_sent", "sms_sent"].includes(buyerResult)) return "sent";
  if (buyerResult === "botpress_queued") return "queued";
  if (buyerResult === "skipped_no_phone") return "not_deliverable";
  if (buyerResult === "skipped_conversational_reply") return "skipped";
  return willRetry ? "queued" : "failed";
}

/** Pure result mapping used by the callable and its regression tests. */
export function commerceNotificationResult(
  buyerResult: string,
  sellerResult: string,
  willRetry: boolean,
  notificationId?: string,
): CommerceNotificationResult {
  return {
    ...(notificationId ? { notificationId } : {}),
    customer: customerDelivery(buyerResult, willRetry),
    buyerResult,
    sellerResult,
  };
}

function outboxNotice(order: OrderNotice): OutboxNotice {
  return {
    orderId: order.orderId,
    sellerId: order.sellerId,
    customerId: order.customerId ?? "",
    buyerName: order.buyerName,
    buyerPhone: order.buyerPhone,
    status: order.status,
    paymentMethod: order.paymentMethod ?? "",
    amountDueMinor: order.amountDueMinor,
    ...(order.trackingNumber == null
      ? {}
      : { trackingNumber: order.trackingNumber }),
    ...(order.trackingUrl == null ? {} : { trackingUrl: order.trackingUrl }),
    notifyBuyer: order.notifyBuyer !== false,
    orderKind: order.orderKind ?? "supplier_delivery",
    ...(order.unreadOrdersCount == null
      ? {}
      : { unreadOrdersCount: order.unreadOrdersCount }),
    ...(order.unreadTotalCount == null
      ? {}
      : { unreadTotalCount: order.unreadTotalCount }),
    noticeKind: order.noticeKind ?? "order",
  };
}

export function commerceNotificationDocumentId(order: OrderNotice): string {
  return [
    order.orderKind ?? "supplier_delivery",
    order.sellerId,
    order.orderId,
    order.status,
    order.eventKey ?? order.status,
    order.noticeKind ?? "order",
  ].join("--");
}

/**
 * Adds the notification to the same transaction as its order transition.
 * The deterministic document ID makes a repeated transition idempotent.
 */
export function enqueueCommerceOrderNotification(
  tx: FirebaseFirestore.Transaction | FirebaseFirestore.WriteBatch,
  order: OrderNotice,
): string {
  const id = commerceNotificationDocumentId(order);
  tx.create(db.collection(COMMERCE_NOTIFICATION_OUTBOX).doc(id), {
    notice: outboxNotice(order),
    state: "pending",
    attempts: 0,
    availableAtMs: Date.now(),
    leaseUntilMs: 0,
    buyerResult: "pending",
    sellerResult: "pending",
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return id;
}

async function attemptNotice(
  order: OrderNotice,
  previousBuyerResult = "pending",
  previousSellerResult = "pending",
): Promise<{ buyerResult: string; sellerResult: string }> {
  const buyerResult = TERMINAL_BUYER_RESULTS.has(previousBuyerResult)
    ? previousBuyerResult
    : order.notifyBuyer === false
      ? "skipped_conversational_reply"
      : await notifyBuyer(order).catch(() => "failed");
  const sellerResult = TERMINAL_SELLER_RESULTS.has(previousSellerResult)
    ? previousSellerResult
    : await notifySeller(order).catch(() => "failed");
  return { buyerResult, sellerResult };
}

function resultFromStored(
  id: string,
  value: OutboxDocument,
): CommerceNotificationResult {
  const buyerResult = String(value.buyerResult ?? "pending");
  const sellerResult = String(value.sellerResult ?? "pending");
  const willRetry = ["pending", "processing", "retry"].includes(
    String(value.state ?? "pending"),
  );
  return commerceNotificationResult(buyerResult, sellerResult, willRetry, id);
}

/** Claims and delivers one durable notification without resending a channel
 * that already completed during an earlier attempt. */
export async function deliverCommerceOrderNotificationOutbox(
  id: string,
): Promise<CommerceNotificationResult> {
  const ref = db.collection(COMMERCE_NOTIFICATION_OUTBOX).doc(id);
  const nowMs = Date.now();
  const claimed = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) throw new Error("NOTIFICATION_OUTBOX_NOT_FOUND");
    const value = snapshot.data() as OutboxDocument;
    const state = String(value.state ?? "pending");
    const notDue =
      (state === "processing" && Number(value.leaseUntilMs ?? 0) > nowMs) ||
      (state === "retry" && Number(value.availableAtMs ?? 0) > nowMs);
    if (["sent", "failed"].includes(state) || notDue) {
      return { claimed: false as const, value };
    }
    const attempts = Number(value.attempts ?? 0) + 1;
    tx.set(
      ref,
      {
        state: "processing",
        attempts,
        leaseUntilMs: nowMs + NOTIFICATION_LEASE_MS,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { claimed: true as const, value, attempts };
  });
  if (!claimed.claimed) return resultFromStored(id, claimed.value);

  const order = claimed.value.notice;
  if (!order) throw new Error("NOTIFICATION_NOTICE_INVALID");
  const { buyerResult, sellerResult } = await attemptNotice(
    order,
    String(claimed.value.buyerResult ?? "pending"),
    String(claimed.value.sellerResult ?? "pending"),
  );
  const retryNeeded =
    !TERMINAL_BUYER_RESULTS.has(buyerResult) ||
    !TERMINAL_SELLER_RESULTS.has(sellerResult);
  const willRetry = retryNeeded && claimed.attempts < MAX_NOTIFICATION_ATTEMPTS;
  const retryDelay =
    NOTIFICATION_RETRY_DELAYS_MS[
      Math.min(claimed.attempts - 1, NOTIFICATION_RETRY_DELAYS_MS.length - 1)
    ];
  const batch = db.batch();
  batch.set(
    ref,
    {
      state: retryNeeded ? (willRetry ? "retry" : "failed") : "sent",
      buyerResult,
      sellerResult,
      availableAtMs: willRetry ? Date.now() + retryDelay : 0,
      leaseUntilMs: 0,
      lastAttemptAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  const orderRef =
    order.orderKind === "merchant_stock"
      ? db.doc(`users/${order.sellerId}/sales/${order.orderId}`)
      : db.doc(`commerceOrders/${order.orderId}`);
  batch.set(
    orderRef,
    {
      notificationHistory: FieldValue.arrayUnion({
        notificationId: id,
        status: order.status,
        buyerResult,
        sellerResult,
        queuedForRetry: willRetry,
        attemptedAt: new Date().toISOString(),
      }),
      notificationUpdatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await batch.commit();
  return commerceNotificationResult(buyerResult, sellerResult, willRetry, id);
}

async function recoverExpiredOutboxLeases(nowMs: number): Promise<void> {
  const snapshot = await db
    .collection(COMMERCE_NOTIFICATION_OUTBOX)
    .where("state", "==", "processing")
    .limit(50)
    .get();
  const expired = snapshot.docs.filter(
    (doc) => Number(doc.data().leaseUntilMs ?? 0) <= nowMs,
  );
  if (!expired.length) return;
  const batch = db.batch();
  expired.forEach((doc) => {
    batch.set(
      doc.ref,
      {
        state: "retry",
        availableAtMs: nowMs,
        leaseUntilMs: 0,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
  await batch.commit();
}

export async function processCommerceNotificationOutbox(
  limit = 20,
): Promise<number> {
  const nowMs = Date.now();
  await recoverExpiredOutboxLeases(nowMs);
  const [pending, retry] = await Promise.all([
    db
      .collection(COMMERCE_NOTIFICATION_OUTBOX)
      .where("state", "==", "pending")
      .limit(limit)
      .get(),
    db
      .collection(COMMERCE_NOTIFICATION_OUTBOX)
      .where("state", "==", "retry")
      .limit(limit)
      .get(),
  ]);
  const due = [...pending.docs, ...retry.docs]
    .filter((doc) => Number(doc.data().availableAtMs ?? 0) <= nowMs)
    .slice(0, limit);
  await Promise.all(
    due.map((doc) =>
      deliverCommerceOrderNotificationOutbox(doc.id).catch((error) => {
        console.error(`[commerce] notification retry ${doc.id} failed`, error);
      }),
    ),
  );
  return due.length;
}

/** Immediate, non-outbox delivery retained for order-created and webhook
 * callers. Fulfilment transitions use the durable outbox above. */
export async function notifyCommerceOrder(
  order: OrderNotice,
  options: NotifyCommerceOrderOptions = {},
): Promise<CommerceNotificationResult> {
  const { buyerResult, sellerResult } = await attemptNotice(
    order,
    options.previousBuyerResult,
    options.previousSellerResult,
  );
  await db.doc(`commerceOrders/${order.orderId}`).set(
    {
      notificationHistory: FieldValue.arrayUnion({
        ...(options.notificationId
          ? { notificationId: options.notificationId }
          : {}),
        status: order.status,
        buyerResult,
        sellerResult,
        attemptedAt: new Date().toISOString(),
      }),
      notificationUpdatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return commerceNotificationResult(buyerResult, sellerResult, false);
}
