import assert from "node:assert/strict";
import { after, beforeEach, test } from "node:test";
import admin from "firebase-admin";
import {
  incrementUnreadCount,
  markCustomerMessagesRead,
  markOrderNotificationsRead,
  unreadEventDocumentId,
} from "../lib/notifications/unreadCounts.js";

const emulatorHost = String(process.env.FIRESTORE_EMULATOR_HOST ?? "");
const emulatorProject = String(
  process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "",
);
if (!emulatorHost || !emulatorProject.startsWith("demo-")) {
  throw new Error(
    "Refusing unread integration test without a demo Firestore emulator.",
  );
}

const db = admin.firestore();
const merchantRef = db.doc("users/merchant-a");
const customerARef = merchantRef.collection("customers").doc("customer-a");
const customerBRef = merchantRef.collection("customers").doc("customer-b");

beforeEach(async () => {
  await admin.firestore().recursiveDelete(merchantRef);
  await merchantRef.set({
    unreadCount: 0,
    ordersUnreadCount: 0,
    unreadCounts: { messages: 0, orders: 0, total: 0 },
    unreadMessages: [
      { id: "legacy-a-1", customerNumber: "0821234567", message: "one" },
      {
        id: "legacy-a-2",
        customerNumber: "+27821234567",
        message: "two",
      },
      { id: "legacy-b-1", customerNumber: "0712345678", message: "other" },
      {
        id: "legacy-outbound",
        customerNumber: "0821234567",
        message: "bot reply",
        direction: "outbound",
      },
    ],
  });
  await customerARef.set({
    number: "0821234567",
    unreadCounts: { messages: 0, orders: 0, total: 0 },
  });
  await customerBRef.set({
    number: "0712345678",
    unreadCounts: { messages: 0, orders: 0, total: 0 },
  });
});

after(async () => {
  await admin.firestore().recursiveDelete(merchantRef);
});

test("message migration, idempotency, and bounded clears survive concurrent arrivals", async () => {
  const first = await incrementUnreadCount({
    merchantId: "merchant-a",
    customerId: "customer-a",
    customerNumber: "0821234567",
    kind: "messages",
    eventKey: "message:new-a-1",
    messageEntry: {
      id: "new-a-1",
      customerNumber: "0821234567",
      message: "new",
      direction: "inbound",
    },
  });
  assert.equal(first.merchant.messages, 4);
  assert.equal(first.customer.messages, 3);

  const duplicate = await incrementUnreadCount({
    merchantId: "merchant-a",
    customerId: "customer-a",
    customerNumber: "0821234567",
    kind: "messages",
    eventKey: "message:new-a-1",
    messageEntry: {
      id: "new-a-1",
      customerNumber: "0821234567",
      message: "new",
      direction: "inbound",
    },
  });
  assert.equal(duplicate.deduped, true);

  const [cleared, arrival] = await Promise.all([
    markCustomerMessagesRead({
      merchantId: "merchant-a",
      customerId: "customer-a",
      customerNumber: "+27821234567",
      limit: 1,
    }),
    incrementUnreadCount({
      merchantId: "merchant-a",
      customerId: "customer-a",
      customerNumber: "0821234567",
      kind: "messages",
      eventKey: "message:new-a-2",
      messageEntry: {
        id: "new-a-2",
        customerNumber: "0821234567",
        message: "concurrent",
        direction: "inbound",
      },
    }),
  ]);
  assert.equal(cleared.cleared, 1);
  assert.equal(arrival.deduped, false);

  const merchant = (await merchantRef.get()).data();
  const customerA = (await customerARef.get()).data();
  assert.equal(merchant.unreadCounts.messages, 4);
  assert.equal(customerA.unreadCounts.messages, 3);
  assert.equal(
    merchant.unreadMessages.filter(
      (entry) => entry.direction !== "outbound" && entry.isRead !== true,
    ).length,
    4,
  );
});

test("order clears subtract only scanned records and never erase a concurrent order", async () => {
  const createOrderUnread = async (orderId, customerId) => {
    const eventKey = `order:${orderId}:ORDER_PLACED`;
    const eventId = unreadEventDocumentId(eventKey);
    const notificationRef = merchantRef
      .collection("notifications")
      .doc(eventId);
    await incrementUnreadCount({
      merchantId: "merchant-a",
      customerId,
      kind: "orders",
      eventKey,
      notification: {
        ref: notificationRef,
        data: {
          type: "ORDER_EVENT",
          eventType: "ORDER_PLACED",
          orderId,
          customerId,
          unreadEventId: eventId,
          read: false,
        },
      },
    });
    return eventId;
  };

  const firstId = await createOrderUnread("order-1", "customer-a");
  const secondId = await createOrderUnread("order-2", "customer-b");
  const afterOrderIncrement = (await merchantRef.get()).data();
  const customerAAfterIncrement = (await customerARef.get()).data();
  const customerBAfterIncrement = (await customerBRef.get()).data();
  assert.equal(afterOrderIncrement.unreadCounts.messages, 3);
  assert.equal(customerAAfterIncrement.unreadCounts.messages, 2);
  assert.equal(customerBAfterIncrement.unreadCounts.messages, 1);

  const [cleared] = await Promise.all([
    markOrderNotificationsRead({
      merchantId: "merchant-a",
      notificationIds: [firstId, secondId],
    }),
    createOrderUnread("order-3", "customer-a"),
  ]);
  assert.equal(cleared.cleared, 2);

  const merchant = (await merchantRef.get()).data();
  const customerA = (await customerARef.get()).data();
  const customerB = (await customerBRef.get()).data();
  assert.equal(merchant.unreadCounts.orders, 1);
  assert.equal(merchant.unreadCounts.messages, 3);
  assert.equal(customerA.unreadCounts.orders, 1);
  assert.equal(customerA.unreadCounts.messages, 2);
  assert.equal(customerB.unreadCounts.orders, 0);
  assert.equal(customerB.unreadCounts.messages, 1);

  const retry = await markOrderNotificationsRead({
    merchantId: "merchant-a",
    notificationIds: [firstId, secondId],
  });
  assert.equal(retry.cleared, 0);
  assert.equal(retry.counts.orders, 1);
  assert.equal(retry.counts.messages, 3);
});
