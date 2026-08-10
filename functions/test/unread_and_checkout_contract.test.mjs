import assert from "node:assert/strict";
import test from "node:test";
import { canonicalUnreadCounts } from "../lib/notifications/unreadCounts.js";
import { deliveryEstimateFromAging } from "../lib/commerce/prepareCommerceCheckout.js";

test("canonical unread counts dual-read released scalar fields", () => {
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

test("delivery estimates normalize single and ranged supplier aging", () => {
  assert.deepEqual(deliveryEstimateFromAging("8-14 days"), {
    minDays: 8,
    maxDays: 14,
  });
  assert.deepEqual(deliveryEstimateFromAging("12 days"), {
    minDays: 12,
    maxDays: 12,
  });
  assert.deepEqual(deliveryEstimateFromAging("check later"), {
    minDays: 10,
    maxDays: 20,
  });
});
