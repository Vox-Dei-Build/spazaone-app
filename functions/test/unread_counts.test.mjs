import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  canonicalUnreadCounts,
  customerNumbersMatch,
  legacyUnreadMessageCount,
  legacyUnreadMessageCountForCustomer,
  markMatchingMessagesRead,
  unreadEventDocumentId,
} from "../lib/notifications/unreadCounts.js";

test("dual-reads legacy scalar counters without letting stale scalars replace canonical values", () => {
  assert.deepEqual(
    canonicalUnreadCounts({ unreadCount: 2, ordersUnreadCount: 3 }),
    { messages: 2, orders: 3, total: 5 },
  );
  assert.deepEqual(
    canonicalUnreadCounts({
      unreadCount: 99,
      ordersUnreadCount: 99,
      unreadCounts: { messages: 4, orders: 6 },
    }),
    { messages: 4, orders: 6, total: 10 },
  );
});

test("derives a customer's legacy chats from their stored number during order work", () => {
  const merchant = {
    unreadMessages: [
      { customerNumber: "+27821234567", message: "customer A" },
      { customerNumber: "0712345678", message: "customer B" },
      {
        customerNumber: "0821234567",
        message: "read",
        isRead: true,
      },
    ],
  };
  assert.equal(
    legacyUnreadMessageCountForCustomer(merchant, {
      number: "0821234567",
    }),
    1,
  );
  assert.equal(
    legacyUnreadMessageCountForCustomer(merchant, { number: "0821234567" }, ""),
    1,
  );
  assert.equal(
    legacyUnreadMessageCountForCustomer(merchant, {
      phoneNumber: "+27712345678",
    }),
    1,
  );
  assert.equal(legacyUnreadMessageCountForCustomer(merchant, {}), undefined);
});

test("migrates hidden per-customer legacy messages from unreadMessages", () => {
  const merchant = {
    unreadMessages: [
      { customerNumber: "082 123 4567", message: "one" },
      {
        customerNumber: "+27 82 123 4567",
        message: "two",
        direction: "inbound",
      },
      {
        customerNumber: "0821234567",
        message: "already read",
        isRead: true,
      },
      {
        customerNumber: "0821234567",
        message: "bot reply",
        direction: "outbound",
      },
      { customerNumber: "0712345678", message: "someone else" },
    ],
  };
  assert.equal(legacyUnreadMessageCount(merchant), 3);
  assert.equal(legacyUnreadMessageCount(merchant, "0821234567"), 2);
  assert.deepEqual(
    canonicalUnreadCounts(
      { unreadCounts: { messages: 0, orders: 1 } },
      { legacyMessageCount: 2 },
    ),
    { messages: 2, orders: 1, total: 3 },
  );
});

test("phone matching tolerates released local/E.164 formatting", () => {
  assert.equal(customerNumbersMatch("082 123 4567", "+27 82 123 4567"), true);
  assert.equal(customerNumbersMatch("0821234567", "0712345678"), false);
  assert.equal(customerNumbersMatch("", "0821234567"), false);
});

test("bounded message clearing marks only exact unread inbound records", () => {
  const untouchedReadAt = "2025-01-01T00:00:00.000Z";
  const result = markMatchingMessagesRead({
    customerNumber: "+27821234567",
    limit: 2,
    readAt: "2026-08-09T10:00:00.000Z",
    messages: [
      { id: "a", customerNumber: "0821234567" },
      { id: "b", customerNumber: "0821234567", direction: "inbound" },
      { id: "c", customerNumber: "0821234567", direction: "inbound" },
      { id: "d", customerNumber: "0821234567", direction: "outbound" },
      {
        id: "e",
        customerNumber: "0821234567",
        isRead: true,
        readAt: untouchedReadAt,
      },
      { id: "f", customerNumber: "0712345678" },
    ],
  });
  assert.equal(result.marked, 2);
  assert.equal(result.messages[0].isRead, true);
  assert.equal(result.messages[1].isRead, true);
  assert.equal(result.messages[2].isRead, undefined);
  assert.equal(result.messages[3].isRead, undefined);
  assert.equal(result.messages[4].readAt, untouchedReadAt);
  assert.equal(result.messages[5].isRead, undefined);
});

test("unread event IDs are deterministic and do not expose caller keys", () => {
  const first = unreadEventDocumentId("order:merchant/order:ORDER_PLACED");
  assert.equal(
    first,
    unreadEventDocumentId("order:merchant/order:ORDER_PLACED"),
  );
  assert.notEqual(first, unreadEventDocumentId("order:other:ORDER_PLACED"));
  assert.match(first, /^[a-f0-9]{64}$/);
  assert.equal(first.includes("merchant"), false);
});

test("public unread endpoints enforce their intended trust boundary", async () => {
  const [notify, orders, customerOrders, messages] = await Promise.all([
    readFile(
      new URL("../src/ecommerce/notifyOrderEvent.ts", import.meta.url),
      "utf8",
    ),
    readFile(
      new URL("../src/ecommerce/notifyOrderEvent.ts", import.meta.url),
      "utf8",
    ),
    readFile(
      new URL("../src/ecommerce/orderNotification.ts", import.meta.url),
      "utf8",
    ),
    readFile(
      new URL("../src/merchant_hub/markMessagesAsRead.ts", import.meta.url),
      "utf8",
    ),
  ]);

  assert.match(notify, /secrets:\s*\["PASELLA_BOT_TOKEN"\]/);
  assert.match(notify, /requireBotRequest\(req, res\)/);
  for (const source of [orders, customerOrders, messages]) {
    assert.match(source, /authenticateFirebaseRequest\(req, res,/);
    assert.match(source, /requireAppCheck:\s*true/);
    assert.match(source, /assertStoreAccess\(uid, merchantId\)/);
  }
  assert.doesNotMatch(orders, /ordersUnreadCount:\s*0/);
  assert.doesNotMatch(customerOrders, /ordersUnreadCount:\s*0/);
  assert.doesNotMatch(messages, /unreadCount:\s*0/);
});
