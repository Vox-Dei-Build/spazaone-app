import assert from "node:assert/strict";
import { after, test } from "node:test";
import admin from "firebase-admin";

import { processOrderCreatedNotificationOutbox } from "../lib/commerce/orderCreatedNotificationOutbox.js";
import {
  markOrderNotificationsRead,
  unreadEventDocumentId,
} from "../lib/notifications/unreadCounts.js";

const emulatorHost = String(process.env.FIRESTORE_EMULATOR_HOST ?? "");
const emulatorProject = String(
  process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "",
);
if (!emulatorHost || !emulatorProject.startsWith("demo-")) {
  throw new Error(
    "Refusing scheduler integration test without a demo Firestore emulator.",
  );
}

const db = admin.firestore();
const suffix = `scheduler-${Date.now()}-${process.pid}`;
const merchantId = `merchant-${suffix}`;
const customerId = `customer-${suffix}`;
const orderId = `order-${suffix}`;
const merchantRef = db.doc(`users/${merchantId}`);
const orderRef = db.doc(`commerceOrders/${orderId}`);
const outboxRef = db.doc(`commerceOrderNotificationOutbox/${orderId}_created`);
const unreadEventId = unreadEventDocumentId(`order:${orderId}:ORDER_PLACED`);
const notificationRef = merchantRef
  .collection("notifications")
  .doc(unreadEventId);

after(async () => {
  await Promise.all([
    admin.firestore().recursiveDelete(merchantRef),
    orderRef.delete(),
    outboxRef.delete(),
  ]);
});

test("scheduler recovers an expired created-order lease exactly once", async () => {
  await merchantRef.set({
    unreadCount: 0,
    ordersUnreadCount: 0,
    unreadCounts: { messages: 0, orders: 0, total: 0 },
    unreadMessages: [
      {
        customerNumber: "+27820000000",
        message: "Legacy customer message",
      },
    ],
  });
  await merchantRef
    .collection("customers")
    .doc(customerId)
    .set({
      name: "Scheduler Customer",
      number: "0820000000",
      unreadCount: 0,
      ordersUnreadCount: 0,
      unreadCounts: { messages: 0, orders: 0, total: 0 },
    });
  await orderRef.set({
    sellerId: merchantId,
    customerId,
    buyer: { name: "Scheduler Customer", phone: "0820000000" },
    orderChannel: "whatsapp",
    paymentMethod: "manual",
    amountDueMinor: 25_000,
    status: "pending_payment",
    notificationHistory: [],
  });
  await outboxRef.set({
    orderId,
    event: "order_created",
    status: "delivering",
    attempts: 0,
    claimToken: "expired-claim",
    leaseUntilMs: Date.now() - 1,
  });

  assert.equal(await processOrderCreatedNotificationOutbox(1, [orderId]), 1);
  const delivered = await outboxRef.get();
  const firstOrder = await orderRef.get();
  const firstMerchant = await merchantRef.get();
  const firstCustomer = await merchantRef
    .collection("customers")
    .doc(customerId)
    .get();
  const firstNotification = await notificationRef.get();
  assert.equal(delivered.get("status"), "delivered");
  assert.equal(delivered.get("attempts"), 1);
  assert.equal(firstOrder.get("notificationHistory").length, 1);
  assert.equal(firstMerchant.get("ordersUnreadCount"), 1);
  assert.equal(firstMerchant.get("unreadCounts.messages"), 1);
  assert.equal(firstCustomer.get("ordersUnreadCount"), 1);
  assert.equal(firstCustomer.get("unreadCounts.messages"), 1);
  assert.equal(firstNotification.get("type"), "ORDER_EVENT");
  assert.equal(firstNotification.get("orderId"), orderId);
  assert.equal(firstNotification.get("customerId"), customerId);
  assert.equal(firstNotification.get("unreadEventId"), unreadEventId);
  assert.equal(firstNotification.get("read"), false);

  const cleared = await markOrderNotificationsRead({
    merchantId,
    notificationIds: [unreadEventId],
  });
  assert.equal(cleared.cleared, 1);
  assert.equal(cleared.counts.orders, 0);
  assert.equal(cleared.counts.messages, 1);
  const clearedCustomer = await merchantRef
    .collection("customers")
    .doc(customerId)
    .get();
  assert.equal(clearedCustomer.get("ordersUnreadCount"), 0);
  assert.equal(clearedCustomer.get("unreadCounts.messages"), 1);
  assert.equal((await notificationRef.get()).get("read"), true);

  await outboxRef.set(
    {
      status: "delivering",
      claimToken: "second-expired-claim",
      leaseUntilMs: Date.now() - 1,
    },
    { merge: true },
  );
  assert.equal(await processOrderCreatedNotificationOutbox(1, [orderId]), 1);
  const deduped = await outboxRef.get();
  const secondOrder = await orderRef.get();
  const secondMerchant = await merchantRef.get();
  assert.equal(deduped.get("status"), "delivered");
  assert.equal(deduped.get("attempts"), 1);
  assert.equal(secondOrder.get("notificationHistory").length, 1);
  assert.equal(secondMerchant.get("ordersUnreadCount"), 0);
  assert.equal(secondMerchant.get("unreadCounts.messages"), 1);
});
