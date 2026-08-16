import assert from "node:assert/strict";
import { test } from "node:test";
import {
  buyerSafeTrackingCarrier,
  canonicalCommerceOrderStatus,
  isOpenCommerceOrder,
  orderCreatedAtMillis,
  presentCommerceOrder,
} from "../lib/commerce/orderPresentation.js";

test("buyer tracking omits every delivery partner name", () => {
  assert.equal(buyerSafeTrackingCarrier("CJPacket Ordinary"), "");
  assert.equal(buyerSafeTrackingCarrier("CJ Dropshipping"), "");
  assert.equal(buyerSafeTrackingCarrier("The Courier Guy"), "");
});

test("commerce orders are explicitly identified for WhatsApp tracking", () => {
  const createdAt = { toMillis: () => 1234 };
  const row = presentCommerceOrder("order-1", {
    sellerId: "seller-1",
    customerId: "customer-1",
    status: "submitted_for_fulfilment",
    amountDueMinor: 54_789,
    paymentMethod: "manual",
    paymentStatus: "paid",
    createdAt,
    tracking: {
      carrier: "CJPacket ZA",
      number: "TRACK-123",
      url: "https://tracking.example.test/TRACK-123",
    },
    lineItems: [
      {
        sellerProductId: "product-1",
        title: "Messenger bag",
        quantity: 1,
      },
    ],
  });

  assert.equal(row.source, "commerce");
  assert.equal(row.orderKind, "supplier_delivery");
  assert.equal(row.status, "preparing");
  assert.equal(row.sourceStatus, "submitted_for_fulfilment");
  assert.equal(row.total, 547.89);
  assert.equal(row.itemsCount, 1);
  assert.equal(row.items[0].productId, "product-1");
  assert.equal(row.createdAt, createdAt);
  assert.deepEqual(row.tracking, {
    carrier: "",
    number: "TRACK-123",
    url: "https://tracking.example.test/TRACK-123",
  });
});

test("supplier source states use the canonical customer lifecycle", () => {
  assert.equal(
    canonicalCommerceOrderStatus("pending_payment"),
    "awaiting_payment",
  );
  assert.equal(canonicalCommerceOrderStatus("paid"), "paid");
  assert.equal(
    canonicalCommerceOrderStatus("submitted_for_fulfilment"),
    "preparing",
  );
  assert.equal(canonicalCommerceOrderStatus("shipped"), "on_the_way");
  assert.equal(canonicalCommerceOrderStatus("delivered"), "delivered");
  assert.equal(
    canonicalCommerceOrderStatus("cancelled", "refund_pending"),
    "cancelled",
  );
  assert.equal(
    canonicalCommerceOrderStatus("cancelled", "refunded"),
    "refunded",
  );
});

test("only active fulfilment states count as open supplier orders", () => {
  for (const status of [
    "pending_payment",
    "paid",
    "submitted_for_fulfilment",
    "shipped",
  ]) {
    assert.equal(isOpenCommerceOrder({ status }), true, status);
  }
  for (const status of ["delivered", "cancelled", "refunded"]) {
    assert.equal(isOpenCommerceOrder({ status }), false, status);
  }
});

test("mixed legacy dateAdded and commerce createdAt rows sort newest first", () => {
  const legacy = {
    id: "legacy-newer",
    dateAdded: { toMillis: () => 2_000 },
  };
  const commerce = {
    id: "commerce-older",
    createdAt: { toMillis: () => 1_000 },
  };
  const rows = [commerce, legacy].sort(
    (left, right) => orderCreatedAtMillis(right) - orderCreatedAtMillis(left),
  );
  assert.deepEqual(
    rows.map((row) => row.id),
    ["legacy-newer", "commerce-older"],
  );
});
