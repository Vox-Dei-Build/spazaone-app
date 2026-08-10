import { randomBytes } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../config/main";
import {
  incrementUnreadCount,
  unreadEventDocumentId,
} from "../notifications/unreadCounts";
import { notifyCommerceOrder } from "./notifications";

const ORDER_CREATED_OUTBOX_COLLECTION = "commerceOrderNotificationOutbox";
const ORDER_CREATED_OUTBOX_LEASE_MS = 60 * 1000;
const ORDER_CREATED_OUTBOX_MAX_ATTEMPTS = 4;
const TERMINAL_BUYER_RESULTS = new Set([
  "whatsapp_sent",
  "sms_sent",
  "skipped_no_phone",
  "skipped_conversational_reply",
]);
const TERMINAL_SELLER_RESULTS = new Set(["push_sent", "skipped_no_tokens"]);

type OutboxValue = {
  orderId?: unknown;
  status?: unknown;
  attempts?: unknown;
  leaseUntilMs?: unknown;
  claimToken?: unknown;
};

type DeliveryHistory = {
  notificationId?: unknown;
  status?: unknown;
  buyerResult?: unknown;
  sellerResult?: unknown;
};

export function orderCreatedOutboxRef(orderId: string) {
  return db.doc(`${ORDER_CREATED_OUTBOX_COLLECTION}/${orderId}_created`);
}

export function orderCreatedOutboxIsDue(
  value: OutboxValue,
  nowMs: number,
): boolean {
  const status = String(value.status ?? "pending");
  if (status === "pending") return true;
  return status === "delivering" && Number(value.leaseUntilMs ?? 0) <= nowMs;
}

function completedChannelResults(
  historyValue: unknown,
  notificationId: string,
): { buyerResult: string; sellerResult: string } {
  const history: DeliveryHistory[] = Array.isArray(historyValue)
    ? historyValue
    : [];
  let buyerResult = "pending";
  let sellerResult = "pending";
  for (const item of history) {
    const matchingEvent =
      item?.notificationId === notificationId ||
      (!item?.notificationId && item?.status === "pending_payment");
    if (!matchingEvent) continue;
    const buyer = String(item?.buyerResult ?? "pending");
    const seller = String(item?.sellerResult ?? "pending");
    if (TERMINAL_BUYER_RESULTS.has(buyer)) buyerResult = buyer;
    if (TERMINAL_SELLER_RESULTS.has(seller)) sellerResult = seller;
  }
  return { buyerResult, sellerResult };
}

function deliveryComplete(results: {
  buyerResult: string;
  sellerResult: string;
}): boolean {
  return (
    TERMINAL_BUYER_RESULTS.has(results.buyerResult) &&
    TERMINAL_SELLER_RESULTS.has(results.sellerResult)
  );
}

export async function deliverOrderCreatedOutbox(
  orderId: string,
): Promise<"delivered" | "leased" | "failed" | "skipped"> {
  const outboxRef = orderCreatedOutboxRef(orderId);
  const orderRef = db.doc(`commerceOrders/${orderId}`);
  const notificationId = `${orderId}_created`;
  const claimToken = randomBytes(16).toString("hex");
  const nowMs = Date.now();
  const claim = await db.runTransaction(async (tx) => {
    const [outbox, order] = await Promise.all([
      tx.get(outboxRef),
      tx.get(orderRef),
    ]);
    if (!order.exists || order.data()?.paymentMethod !== "manual") {
      return { state: "skipped" as const };
    }
    const value = (outbox.data() ?? {}) as OutboxValue;
    if (value.status === "delivered") {
      return { state: "delivered" as const };
    }
    if (value.status === "failed") return { state: "failed" as const };

    const previous = completedChannelResults(
      order.data()?.notificationHistory,
      notificationId,
    );
    if (deliveryComplete(previous)) {
      tx.set(
        outboxRef,
        {
          orderId,
          event: "order_created",
          status: "delivered",
          claimToken: null,
          leaseUntilMs: 0,
          attempts: Number(value.attempts ?? 0),
          deliveredAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          ...(!outbox.exists
            ? {
                repairedAt: FieldValue.serverTimestamp(),
                createdAt: FieldValue.serverTimestamp(),
              }
            : {}),
        },
        { merge: true },
      );
      return { state: "delivered" as const };
    }
    if (
      value.status === "delivering" &&
      Number(value.leaseUntilMs ?? 0) > nowMs
    ) {
      return { state: "leased" as const };
    }
    const attempts = Number(value.attempts ?? 0);
    if (attempts >= ORDER_CREATED_OUTBOX_MAX_ATTEMPTS) {
      tx.set(
        outboxRef,
        {
          status: "failed",
          claimToken: null,
          leaseUntilMs: 0,
          failedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { state: "failed" as const };
    }
    tx.set(
      outboxRef,
      {
        orderId,
        event: "order_created",
        status: "delivering",
        claimToken,
        leaseUntilMs: nowMs + ORDER_CREATED_OUTBOX_LEASE_MS,
        attempts: attempts + 1,
        updatedAt: FieldValue.serverTimestamp(),
        ...(!outbox.exists
          ? {
              repairedAt: FieldValue.serverTimestamp(),
              createdAt: FieldValue.serverTimestamp(),
            }
          : {}),
      },
      { merge: true },
    );
    return {
      state: "claimed" as const,
      order: order.data() ?? {},
      previous,
      attempts: attempts + 1,
    };
  });
  if (claim.state !== "claimed") return claim.state;

  try {
    const buyer =
      claim.order.buyer && typeof claim.order.buyer === "object"
        ? claim.order.buyer
        : {};
    const merchantId = String(claim.order.sellerId ?? "");
    const customerId = String(claim.order.customerId ?? "");
    const eventKey = `order:${orderId}:ORDER_PLACED`;
    const unreadEventId = unreadEventDocumentId(eventKey);
    const notificationRef = db.doc(
      `users/${merchantId}/notifications/${unreadEventId}`,
    );
    const amountDueMinor = Number(claim.order.amountDueMinor ?? 0);
    const unread = await incrementUnreadCount({
      merchantId,
      customerId,
      customerNumber: buyer.phone,
      kind: "orders",
      eventKey,
      notification: {
        ref: notificationRef,
        data: {
          type: "ORDER_EVENT",
          eventType: "ORDER_PLACED",
          orderId,
          customerId,
          customerName: String(buyer.name ?? "Customer"),
          paymentMethod: null,
          orderTotal:
            Number.isSafeInteger(amountDueMinor) && amountDueMinor >= 0
              ? amountDueMinor / 100
              : null,
          currency: String(claim.order.currency ?? "ZAR"),
          channel: String(claim.order.orderChannel ?? "commerce"),
          read: false,
          createdAt: new Date().toISOString(),
          idempotencyKey: notificationId,
          unreadEventId,
          source: "commerce_order_created_outbox",
        },
      },
    });
    const result = await notifyCommerceOrder(
      {
        orderId,
        sellerId: merchantId,
        customerId,
        buyerName: String(buyer.name ?? "Customer"),
        buyerPhone: String(buyer.phone ?? ""),
        status: "pending_payment",
        paymentMethod: "manual",
        amountDueMinor,
        notifyBuyer: claim.order.orderChannel !== "whatsapp",
        unreadOrdersCount: unread.merchant.orders,
        unreadTotalCount: unread.merchant.total,
      },
      {
        notificationId,
        previousBuyerResult: claim.previous.buyerResult,
        previousSellerResult: claim.previous.sellerResult,
      },
    );
    const delivered = deliveryComplete(result);
    const exhausted =
      !delivered && claim.attempts >= ORDER_CREATED_OUTBOX_MAX_ATTEMPTS;
    await db.runTransaction(async (tx) => {
      const current = await tx.get(outboxRef);
      if (current.data()?.claimToken !== claimToken) return;
      tx.set(
        outboxRef,
        {
          status: delivered ? "delivered" : exhausted ? "failed" : "pending",
          claimToken: null,
          leaseUntilMs: 0,
          ...(delivered
            ? { deliveredAt: FieldValue.serverTimestamp() }
            : exhausted
              ? { failedAt: FieldValue.serverTimestamp() }
              : {}),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });
    if (!delivered) throw new Error("ORDER_CREATED_NOTIFICATION_FAILED");
    return "delivered";
  } catch (error) {
    await db.runTransaction(async (tx) => {
      const current = await tx.get(outboxRef);
      if (current.data()?.claimToken !== claimToken) return;
      const attempts = Number(current.data()?.attempts ?? claim.attempts);
      const exhausted = attempts >= ORDER_CREATED_OUTBOX_MAX_ATTEMPTS;
      tx.set(
        outboxRef,
        {
          status: exhausted ? "failed" : "pending",
          claimToken: null,
          leaseUntilMs: 0,
          lastError: String(
            error instanceof Error ? error.message : "notification_failed",
          ).slice(0, 120),
          ...(exhausted ? { failedAt: FieldValue.serverTimestamp() } : {}),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });
    throw error;
  }
}

export async function processOrderCreatedNotificationOutbox(
  limit = 20,
  onlyOrderIds: readonly string[] = [],
): Promise<number> {
  const nowMs = Date.now();
  if (onlyOrderIds.length) {
    const candidates = await Promise.all(
      onlyOrderIds
        .slice(0, limit)
        .map((orderId) => orderCreatedOutboxRef(orderId).get()),
    );
    const due = candidates.filter(
      (doc) => doc.exists && orderCreatedOutboxIsDue(doc.data() ?? {}, nowMs),
    );
    await Promise.all(
      due.map((doc) =>
        deliverOrderCreatedOutbox(String(doc.data()?.orderId ?? "")).catch(
          (error) => {
            console.error(
              `[commerce] order-created notification retry ${doc.id} failed`,
              error,
            );
            return "failed" as const;
          },
        ),
      ),
    );
    return due.length;
  }
  const [pending, delivering] = await Promise.all([
    db
      .collection(ORDER_CREATED_OUTBOX_COLLECTION)
      .where("status", "==", "pending")
      .limit(limit)
      .get(),
    db
      .collection(ORDER_CREATED_OUTBOX_COLLECTION)
      .where("status", "==", "delivering")
      .limit(limit)
      .get(),
  ]);
  const due = [...pending.docs, ...delivering.docs]
    .filter((doc) => orderCreatedOutboxIsDue(doc.data(), nowMs))
    .slice(0, limit);
  await Promise.all(
    due.map((doc) => {
      const orderId = String(doc.data().orderId ?? "").trim();
      if (!orderId) return Promise.resolve("skipped" as const);
      return deliverOrderCreatedOutbox(orderId).catch((error) => {
        console.error(
          `[commerce] order-created notification retry ${doc.id} failed`,
          error,
        );
        return "failed" as const;
      });
    }),
  );
  return due.length;
}
