import assert from "node:assert/strict";
import test from "node:test";

import {
  commerceNotificationDocumentId,
  commerceNotificationResult,
} from "../lib/commerce/notifications.js";
import { orderCreatedOutboxIsDue } from "../lib/commerce/orderCreatedNotificationOutbox.js";
import { validatedTrackingUrl } from "../lib/commerce/tracking.js";

test("tracking links accept only customer-safe http and https URLs", () => {
  assert.equal(
    validatedTrackingUrl("https://tracking.example/order/123"),
    "https://tracking.example/order/123",
  );
  assert.equal(
    validatedTrackingUrl("http://tracking.example/order/123"),
    "http://tracking.example/order/123",
  );
  assert.equal(validatedTrackingUrl(""), null);

  for (const invalid of [
    "tracking.example/123",
    "ftp://tracking.example/123",
    "javascript:alert(1)",
    "https://user:password@tracking.example/123",
    "https://",
  ]) {
    assert.throws(() => validatedTrackingUrl(invalid), /TRACKING_URL_INVALID/);
  }
});

test("failed customer delivery is reported as queued only with a retry", () => {
  assert.equal(
    commerceNotificationResult("failed", "push_sent", true).customer,
    "queued",
  );
  assert.equal(
    commerceNotificationResult("failed", "push_sent", false).customer,
    "failed",
  );
  assert.equal(
    commerceNotificationResult("whatsapp_sent", "failed", true).customer,
    "sent",
  );
  assert.equal(
    commerceNotificationResult("botpress_queued", "push_sent", false).customer,
    "queued",
  );
});

test("missing customer phone is never reported as notified", () => {
  assert.equal(
    commerceNotificationResult("skipped_no_phone", "push_sent", false).customer,
    "not_deliverable",
  );
});

test("one outbox identity covers both order kinds without collisions", () => {
  const notice = {
    orderId: "order-1",
    sellerId: "seller-1",
    buyerName: "Buyer",
    buyerPhone: "0820000000",
    status: "preparing",
    amountDueMinor: 10_000,
    orderKind: "merchant_stock",
    eventKey: "accept_order",
  };
  const first = commerceNotificationDocumentId(notice);
  assert.equal(first, commerceNotificationDocumentId(notice));
  assert.notEqual(
    first,
    commerceNotificationDocumentId({
      ...notice,
      orderKind: "supplier_delivery",
    }),
  );
  assert.notEqual(
    first,
    commerceNotificationDocumentId({
      ...notice,
      eventKey: "assign_driver",
    }),
  );
});

test("scheduler recovers pending and expired order-created deliveries", () => {
  const nowMs = 10_000;
  assert.equal(
    orderCreatedOutboxIsDue({ status: "pending", leaseUntilMs: 0 }, nowMs),
    true,
  );
  assert.equal(
    orderCreatedOutboxIsDue(
      { status: "delivering", leaseUntilMs: nowMs - 1 },
      nowMs,
    ),
    true,
  );
  assert.equal(
    orderCreatedOutboxIsDue(
      { status: "delivering", leaseUntilMs: nowMs + 60_000 },
      nowMs,
    ),
    false,
  );
  assert.equal(orderCreatedOutboxIsDue({ status: "delivered" }, nowMs), false);
  assert.equal(orderCreatedOutboxIsDue({ status: "failed" }, nowMs), false);
});
