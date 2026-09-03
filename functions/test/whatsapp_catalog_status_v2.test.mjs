import assert from "node:assert/strict";
import test from "node:test";

import { buildMerchantCatalogDecision } from "../lib/whatsapp/catalogProjection.js";
import {
  decodeWhatsAppCatalogCursor,
  encodeWhatsAppCatalogCursor,
  summarizeWhatsAppCatalogStatusV2,
} from "../lib/whatsapp/catalogStatusV2.js";

const merchantId = "merchant-status-test";
const merchant = {
  whatsappOrdering: { orderingUrl: "https://shop.example.test/order" },
};

function validProduct(index = 1) {
  return {
    name: `Bread ${index}`,
    sellingPrice: 15 + index,
    image: `https://cdn.example.test/bread-${index}.jpg`,
    whatsappListed: true,
    quantity: 4,
  };
}

function decision(productId, product) {
  return buildMerchantCatalogDecision({
    merchantId,
    productId,
    product,
    merchant,
  });
}

function summarize({ products, mappings = [], outbox = [], rollout = true }) {
  return summarizeWhatsAppCatalogStatusV2({
    merchantId,
    merchant,
    products,
    mappings,
    outbox,
    rolloutEnabled: rollout,
    checkedAtMs: 1_788_422_400_000,
  });
}

test("derives every public catalogue status without provider details", () => {
  const liveProduct = validProduct(1);
  const staleProduct = validProduct(2);
  const syncingProduct = validProduct(3);
  const invalidProduct = { ...validProduct(4), image: "" };
  const reviewProduct = { ...validProduct(5), name: "Tobacco pouch" };
  const removedProduct = { ...validProduct(6), whatsappListed: false };
  const notListedProduct = { ...validProduct(7), whatsappListed: false };
  const supportProduct = validProduct(8);
  const liveDecision = decision("live", liveProduct);
  const staleDecision = decision("stale", staleProduct);
  const removedDecision = decision("removing", removedProduct);

  const result = summarize({
    products: [
      { id: "live", data: liveProduct },
      { id: "stale", data: staleProduct },
      { id: "syncing", data: syncingProduct },
      { id: "invalid", data: invalidProduct },
      { id: "review", data: reviewProduct },
      { id: "removing", data: removedProduct },
      { id: "not-listed", data: notListedProduct },
      { id: "support", data: supportProduct },
    ],
    mappings: [
      {
        productId: "live",
        status: "active",
        metaPolicyStatus: "accepted",
        lastAppliedRevision: liveDecision.revision,
      },
      {
        productId: "stale",
        status: "active",
        metaPolicyStatus: "accepted",
        lastAppliedRevision: `${staleDecision.revision}-old`,
      },
      {
        productId: "syncing",
        status: "pending",
      },
      {
        productId: "review",
        status: "rejected",
        metaPolicyStatus: "rejected",
      },
      {
        productId: "removing",
        status: "pending_delete",
        lastAppliedRevision: removedDecision.revision,
      },
      { productId: "support", status: "failed" },
    ],
    outbox: [{ productId: "syncing", status: "retry" }],
  });

  const statuses = Object.fromEntries(
    result.products.map((product) => [product.productId, product.status]),
  );
  assert.deepEqual(statuses, {
    invalid: "needs_attention",
    live: "live",
    "not-listed": "not_listed",
    removing: "removal_syncing",
    review: "review_required",
    stale: "stale",
    support: "support_review",
    syncing: "syncing",
  });
  assert.equal(result.summary.totalProducts, 8);
  assert.equal(result.summary.live, 1);
  assert.equal(result.summary.syncing, 1);
  assert.equal(result.summary.needsAttention, 4);
  assert.equal(result.summary.removalSyncing, 1);
  assert.equal(result.summary.supportReview, 1);
  assert.match(
    result.products.find((product) => product.productId === "support")
      .supportReference,
    /^CAT-[A-F0-9]{10}$/,
  );
  assert.equal(JSON.stringify(result).includes("retailerId"), false);
  assert.equal(JSON.stringify(result).includes("lastAppliedRevision"), false);
});

for (const count of [0, 1, 4, 5, 9, 10, 11, 22]) {
  test(`reports browsing thresholds for ${count} live products`, () => {
    const products = Array.from({ length: count }, (_, index) => ({
      id: `product-${String(index).padStart(3, "0")}`,
      data: validProduct(index),
    }));
    const mappings = products.map((product) => ({
      productId: product.id,
      status: "active",
      metaPolicyStatus: "accepted",
      lastAppliedRevision: decision(product.id, product.data).revision,
    }));
    const result = summarize({ products, mappings });
    assert.equal(result.summary.live, count);
    assert.equal(result.summary.canBrowseFive, count >= 5);
    assert.equal(result.summary.canBrowseTen, count >= 10);
    assert.deepEqual(
      result.products.map((product) => product.productId),
      [...result.products]
        .map((product) => product.productId)
        .sort((a, b) => a.localeCompare(b)),
    );
  });
}

test("represents an eligible product outside rollout without claiming it is live", () => {
  const result = summarize({
    products: [{ id: "waiting", data: validProduct() }],
    rollout: false,
  });
  assert.equal(result.summary.live, 0);
  assert.equal(result.products[0].status, "syncing");
  assert.deepEqual(result.products[0].reasonCodes, ["catalogue_not_enabled"]);
});

test("catalogue cursor is tenant-bound and rejects tampering", () => {
  const secret = "a-test-secret-that-is-at-least-thirty-two-characters";
  const cursor = {
    uid: "owner-a",
    storeId: merchantId,
    catalogVersion: "a".repeat(64),
    lastProductId: "product-099",
  };
  const encoded = encodeWhatsAppCatalogCursor(cursor, secret);
  assert.deepEqual(decodeWhatsAppCatalogCursor(encoded, secret), cursor);
  assert.equal(
    decodeWhatsAppCatalogCursor(`${encoded.slice(0, -1)}x`, secret),
    null,
  );
  assert.equal(decodeWhatsAppCatalogCursor(encoded, `${secret}-other`), null);
});

test("unknown and inconsistent source states fail closed", () => {
  for (const sources of [
    { mappings: [{ productId: "item", status: "future_state" }] },
    {
      mappings: [
        {
          productId: "item",
          status: "active",
          metaPolicyStatus: "future_state",
        },
      ],
    },
    { outbox: [{ productId: "item", status: "future_state" }] },
    {
      mappings: [
        {
          productId: "item",
          merchantId: "another-merchant",
          status: "pending",
        },
      ],
    },
  ]) {
    const result = summarize({
      products: [{ id: "item", data: validProduct() }],
      ...sources,
    });
    assert.equal(result.products[0].status, "support_review");
    assert.equal(result.products[0].action, "contact_support");
  }
});

test("blocked provider preparation produces sanitized product guidance", () => {
  const result = summarize({
    products: [{ id: "item", data: validProduct() }],
    mappings: [{ productId: "item", status: "blocked" }],
  });
  assert.deepEqual(result.products[0], {
    productId: "item",
    status: "needs_attention",
    reasonCodes: ["catalog_item_unavailable"],
    action: "edit_product",
    updatedAtMs: 1_788_422_400_000,
  });
});

test("catalogue version changes when the product revision changes", () => {
  const before = summarize({
    products: [{ id: "item", data: validProduct() }],
  });
  const after = summarize({
    products: [
      { id: "item", data: { ...validProduct(), name: "Brown bread" } },
    ],
  });
  assert.equal(before.products[0].status, after.products[0].status);
  assert.notEqual(before.catalogVersion, after.catalogVersion);
});
