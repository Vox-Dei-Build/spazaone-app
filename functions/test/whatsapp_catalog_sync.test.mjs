import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import {
  buildMerchantCatalogDecision,
  catalogRetailerId,
  evaluateMerchantProductEligibility,
  isMerchantProductCustomerVisible,
} from "../lib/whatsapp/catalogProjection.js";
import {
  buildMetaCatalogBatchRequests,
  parseMetaCatalogBatchStatus,
} from "../lib/whatsapp/metaCatalogClient.js";
import {
  classifyCatalogImageResponse,
  supportedCatalogImageContentType,
} from "../lib/whatsapp/catalogImage.js";
import { catalogRetryDelayMs } from "../lib/whatsapp/catalogWorker.js";
import { whatsappCatalogRuntimeConfig } from "../lib/whatsapp/catalogConfig.js";
import {
  buildMetaWhatsAppProductCarouselPayload,
  buildMetaWhatsAppProductListPayload,
  buildMetaWhatsAppSingleProductPayload,
  decideNativeProductListClaim,
  orderedCatalogVersion,
  productListRetryDelayMs,
  selectNativeCatalogPage,
  sendMetaWhatsAppCatalog,
  sendMetaWhatsAppCatalogWithFallback,
  sendMetaWhatsAppProductList,
  whatsappProductListRuntimeConfig,
} from "../lib/whatsapp/nativeProductList.js";
import { summarizeProductListDeliveryHealth } from "../lib/whatsapp/nativeProductListStatus.js";
import {
  catalogMappingUnavailableReason,
  mappingMatchesCurrentProjection,
} from "../lib/whatsapp/nativeProductListDelivery.js";

const sourceRoot = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "src",
  "whatsapp",
);

const product = {
  name: "Maize Meal 5 kg",
  description: "Merchant product",
  sellingPrice: 122.54,
  image: "https://images.example.test/maize.jpg",
  whatsappListed: true,
  checkoutUrl: "https://shop.example.test/order/maize",
};

function withEnvironment(values, run) {
  const previous = new Map();
  for (const [key, value] of Object.entries(values)) {
    previous.set(key, process.env[key]);
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  try {
    return run();
  } finally {
    for (const [key, value] of previous) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

async function withEnvironmentAsync(values, run) {
  const previous = new Map();
  for (const [key, value] of Object.entries(values)) {
    previous.set(key, process.env[key]);
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  try {
    return await run();
  } finally {
    for (const [key, value] of previous) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

test("merchant retailer IDs are stable, opaque, and tenant-specific", () => {
  const first = catalogRetailerId("merchant_a", "product_1");
  assert.equal(first, catalogRetailerId("merchant_a", "product_1"));
  assert.notEqual(first, catalogRetailerId("merchant_b", "product_1"));
  assert.match(first, /^spz_[a-f0-9]{32}$/);
  assert.equal(first.includes("merchant_a"), false);
});

test("adopted supplier items use the normal merchant-product projection", () => {
  const ordinary = buildMerchantCatalogDecision({
    merchantId: "merchant_a",
    productId: "product_1",
    product,
  });
  const adopted = buildMerchantCatalogDecision({
    merchantId: "merchant_a",
    productId: "product_1",
    product: {
      ...product,
      isDropshipListing: true,
      supplierId: "cj_dropshipping",
      sourceProductId: "supplier_owned_source",
    },
  });
  assert.equal(ordinary.action, "upsert");
  assert.equal(adopted.action, "upsert");
  assert.equal(adopted.retailerId, ordinary.retailerId);
  assert.equal(adopted.revision, ordinary.revision);
});

test("explicit internal state overrides a stale WhatsApp listing flag", () => {
  for (const internalMarker of [
    { dropshipListingState: "internal" },
    { dropshipListingState: "paused" },
    { internalOnly: true },
    { visibility: "hidden" },
    { customerVisible: false },
  ]) {
    const result = evaluateMerchantProductEligibility({
      ...product,
      ...internalMarker,
      whatsappListed: true,
    });
    assert.equal(result.eligible, false);
    assert.deepEqual(result.reasons, ["internal_product"]);
    assert.equal(
      isMerchantProductCustomerVisible({
        ...product,
        ...internalMarker,
        whatsappListed: true,
      }),
      false,
    );
  }

  assert.equal(
    evaluateMerchantProductEligibility({
      ...product,
      isDropshipListing: true,
      dropshipListingState: "active",
    }).eligible,
    true,
  );
});

test("local eligibility requires WhatsApp visibility, price, name, and HTTPS image", () => {
  assert.equal(evaluateMerchantProductEligibility(product).eligible, true);
  const invalid = evaluateMerchantProductEligibility({
    ...product,
    sellPriceMinor: 0,
    image: "legacy/local/path.jpg",
    whatsappListed: false,
  });
  assert.deepEqual(invalid.reasons, [
    "not_whatsapp_listed",
    "invalid_price",
    "invalid_image_url",
  ]);
});

test("canonical minor-unit price wins over a stale legacy price", () => {
  const invalid = evaluateMerchantProductEligibility({
    ...product,
    sellPriceMinor: 0,
    sellingPrice: 99,
  });
  assert.equal(invalid.eligible, false);
  assert.ok(invalid.reasons.includes("invalid_price"));
});

test("policy keywords require review and are never called Meta-approved locally", () => {
  const result = evaluateMerchantProductEligibility({
    ...product,
    name: "Craft beer case",
  });
  assert.equal(result.eligible, false);
  assert.deepEqual(result.policyReviewReasons, ["alcohol"]);
  assert.ok(result.reasons.includes("policy_review_required"));
});

test("merchant ordering link safely fills a missing product link", () => {
  const decision = buildMerchantCatalogDecision({
    merchantId: "merchant_a",
    productId: "product_1",
    product: { ...product, checkoutUrl: undefined },
    merchant: {
      businessName: "Neighbourhood Store",
      whatsappOrdering: {
        orderingUrl: "https://wa.me/27600000000?text=order%20ABC123",
      },
    },
  });
  assert.equal(decision.action, "upsert");
  assert.equal(
    decision.projection?.link,
    "https://wa.me/27600000000?text=order%20ABC123",
  );
  assert.equal(decision.projection?.brand, "Neighbourhood Store");
});

test("batch encoder uses stable retailer IDs and feed-compatible ZAR price", () => {
  const decision = buildMerchantCatalogDecision({
    merchantId: "merchant_a",
    productId: "product_1",
    product,
  });
  const requests = buildMetaCatalogBatchRequests([
    {
      action: "upsert",
      retailerId: decision.retailerId,
      projection: decision.projection,
    },
    { action: "delete", retailerId: "spz_deleted" },
  ]);
  assert.equal(requests[0].method, "UPDATE");
  assert.equal(requests[0].data.id, decision.retailerId);
  assert.equal(requests[0].data.price, "122.54 ZAR");
  assert.equal(requests[0].data.image_link, product.image);
  assert.deepEqual(requests[1], {
    method: "DELETE",
    data: { id: "spz_deleted" },
  });
});

test("Meta batch status keeps item-level rejection separate from submission", () => {
  const status = parseMetaCatalogBatchStatus(
    {
      data: [
        {
          handle: "handle_1",
          status: "finished",
          errors_total_count: 1,
          warnings_total_count: 2,
          ids_of_invalid_requests: ["spz_bad"],
        },
      ],
    },
    "fallback",
  );
  assert.equal(status.state, "complete");
  assert.equal(status.handle, "handle_1");
  assert.equal(status.invalidRetailerIds.has("spz_bad"), true);
  assert.equal(status.warnings, 2);
});

test("image validation accepts only successful HTTPS JPEG or PNG responses", () => {
  assert.equal(
    supportedCatalogImageContentType("image/jpeg; charset=binary"),
    true,
  );
  assert.equal(supportedCatalogImageContentType("image/webp"), false);
  assert.equal(
    classifyCatalogImageResponse({
      status: 200,
      contentType: "image/png",
      finalUrlIsHttps: true,
    }).state,
    "valid",
  );
  assert.equal(
    classifyCatalogImageResponse({
      status: 404,
      contentType: "application/xml",
      finalUrlIsHttps: true,
    }).state,
    "invalid",
  );
  assert.equal(
    classifyCatalogImageResponse({
      status: 503,
      contentType: "text/html",
      finalUrlIsHttps: true,
    }).state,
    "transient",
  );
});

test("retry delay is exponential and capped", () => {
  assert.deepEqual(
    [1, 2, 3, 4, 5, 10].map(catalogRetryDelayMs),
    [30_000, 60_000, 120_000, 240_000, 480_000, 900_000],
  );
});

test("catalog provider gates fail closed and cap a batch at ten", () => {
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      WHATSAPP_CATALOG_QUEUE_ENABLED: "true",
      WHATSAPP_CATALOG_SYNC_ENABLED: "true",
      META_CATALOG_PROVIDER_MODE: "test",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_CATALOG_CANARY_MERCHANT_IDS: "merchant_a",
      WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED: "false",
      WHATSAPP_CATALOG_MAX_BATCH_SIZE: "50",
      META_GRAPH_API_VERSION: "v25.0",
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      const config = whatsappCatalogRuntimeConfig();
      assert.equal(config.providerMode, "test");
      assert.equal(config.maxBatchSize, 10);
      assert.deepEqual([...config.canaryMerchantIds], ["merchant_a"]);
    },
  );

  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      WHATSAPP_CATALOG_QUEUE_ENABLED: "true",
      WHATSAPP_CATALOG_SYNC_ENABLED: "true",
      META_CATALOG_PROVIDER_MODE: "test",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_CATALOG_CANARY_MERCHANT_IDS: "merchant_a,merchant_b",
      WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED: "false",
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      assert.throws(
        whatsappCatalogRuntimeConfig,
        /DEVELOPMENT_WHATSAPP_CATALOG_SINGLE_MERCHANT_REQUIRED/,
      );
    },
  );

  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      WHATSAPP_CATALOG_QUEUE_ENABLED: "true",
      WHATSAPP_CATALOG_SYNC_ENABLED: "true",
      META_CATALOG_PROVIDER_MODE: "test",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_CATALOG_CANARY_MERCHANT_IDS: "merchant_a",
      WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED: "true",
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      assert.throws(
        whatsappCatalogRuntimeConfig,
        /DEVELOPMENT_WHATSAPP_CATALOG_FULL_ROLLOUT_FORBIDDEN/,
      );
    },
  );

  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      WHATSAPP_CATALOG_QUEUE_ENABLED: "true",
      WHATSAPP_CATALOG_SYNC_ENABLED: "true",
      META_CATALOG_PROVIDER_MODE: "live",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_CATALOG_CANARY_MERCHANT_IDS: "",
      WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED: "false",
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      assert.throws(
        whatsappCatalogRuntimeConfig,
        /WHATSAPP_CATALOG_CANARY_REQUIRED/,
      );
    },
  );
});

test("native product list sends exactly ten merchant retailer IDs in one payload", () => {
  const ids = Array.from(
    { length: 10 },
    (_, index) => `spz_${String(index).padStart(32, "0")}`,
  );
  const payload = buildMetaWhatsAppProductListPayload({
    recipient: "082 123 4567",
    catalogId: "1234567890",
    productRetailerIds: ids,
  });
  assert.equal(payload.to, "27821234567");
  assert.equal(payload.interactive.type, "product_list");
  assert.equal(payload.interactive.action.sections.length, 1);
  assert.deepEqual(
    payload.interactive.action.sections[0].product_items.map(
      (item) => item.product_retailer_id,
    ),
    ids,
  );
  assert.throws(
    () =>
      buildMetaWhatsAppProductListPayload({
        recipient: "+27821234567",
        catalogId: "1234567890",
        productRetailerIds: ids.slice(0, 1),
      }),
    /WHATSAPP_PRODUCT_LIST_ITEMS_INVALID/,
  );
});

test("native carousel has exact Meta shape, ten unique cards, and one catalog", () => {
  const ids = Array.from(
    { length: 10 },
    (_, index) => `spz_${String(index).padStart(32, "0")}`,
  );
  const payload = buildMetaWhatsAppProductCarouselPayload({
    recipient: "+27821234567",
    catalogId: "1234567890",
    productRetailerIds: ids,
    page: 0,
    pageCount: 2,
  });
  assert.deepEqual(Object.keys(payload).sort(), [
    "interactive",
    "messaging_product",
    "recipient_type",
    "to",
    "type",
  ]);
  assert.equal(payload.interactive.type, "carousel");
  assert.equal(payload.interactive.action.cards.length, 10);
  assert.deepEqual(
    payload.interactive.action.cards.map((card) => card.card_index),
    Array.from({ length: 10 }, (_, index) => index),
  );
  assert.deepEqual(
    payload.interactive.action.cards.map(
      (card) => card.action.product_retailer_id,
    ),
    ids,
  );
  assert.deepEqual(
    new Set(
      payload.interactive.action.cards.map((card) => card.action.catalog_id),
    ),
    new Set(["1234567890"]),
  );
  assert.match(payload.interactive.body.text, /Reply More/);
  const middle = buildMetaWhatsAppProductCarouselPayload({
    recipient: "+27821234567",
    catalogId: "1234567890",
    productRetailerIds: ids,
    page: 1,
    pageCount: 3,
  });
  assert.match(middle.interactive.body.text, /More.*Back/);
  const last = buildMetaWhatsAppProductCarouselPayload({
    recipient: "+27821234567",
    catalogId: "1234567890",
    productRetailerIds: ids,
    page: 2,
    pageCount: 3,
  });
  assert.doesNotMatch(last.interactive.body.text, /Reply More/);
  assert.match(last.interactive.body.text, /Reply Back/);
  assert.throws(
    () =>
      buildMetaWhatsAppProductCarouselPayload({
        recipient: "+27821234567",
        catalogId: "1234567890",
        productRetailerIds: [ids[0], ids[0]],
      }),
    /WHATSAPP_PRODUCT_CAROUSEL_ITEMS_INVALID/,
  );
});

test("catalog paging covers boundary counts without duplicates or skips", () => {
  const items = (count) =>
    Array.from({ length: count }, (_, index) => ({
      retailerId: `spz_${String(index).padStart(32, "0")}`,
      lastAppliedRevision: String(index + 1).padStart(64, "a"),
    }));
  for (const count of [0, 1, 2, 4]) {
    const decision = selectNativeCatalogPage({ items: items(count), page: 0 });
    assert.equal(decision.outcome, "fallback", `count=${count}`);
    assert.equal(decision.reason, "fewer_than_five_ready_products");
  }
  for (const count of [5, 9, 10]) {
    const decision = selectNativeCatalogPage({ items: items(count), page: 0 });
    assert.equal(decision.outcome, "ready", `count=${count}`);
    assert.equal(decision.format, "product_carousel");
    assert.equal(decision.items.length, count);
    assert.equal(decision.pageCount, 1);
  }

  for (const count of [11, 22]) {
    const all = items(count);
    const first = selectNativeCatalogPage({ items: all, page: 0 });
    assert.equal(first.outcome, "ready");
    const pages = [first];
    for (let page = 1; page < first.pageCount; page += 1) {
      const next = selectNativeCatalogPage({
        items: all,
        page,
        catalogVersion: first.catalogVersion,
      });
      assert.equal(next.outcome, "ready");
      pages.push(next);
    }
    const flattened = pages.flatMap((page) =>
      page.items.map((item) => item.retailerId),
    );
    assert.deepEqual(
      flattened,
      all.map((item) => item.retailerId),
    );
    assert.equal(new Set(flattened).size, count);
    assert.equal(
      pages.at(-1).format,
      count === 11 ? "single_product" : "product_carousel",
    );
  }
});

test("continuation pages require the unchanged ordered catalog version", () => {
  const items = Array.from({ length: 11 }, (_, index) => ({
    retailerId: `spz_${String(index).padStart(32, "0")}`,
    lastAppliedRevision: String(index).padStart(64, "b"),
  }));
  const version = orderedCatalogVersion(items);
  assert.equal(
    version,
    orderedCatalogVersion(items.map((item) => ({ ...item }))),
  );
  assert.equal(
    selectNativeCatalogPage({ items, page: 1 }).reason,
    "catalog_version_required",
  );
  assert.equal(
    selectNativeCatalogPage({
      items,
      page: 1,
      catalogVersion: "c".repeat(64),
    }).reason,
    "catalog_changed",
  );
  const changed = items.map((item, index) =>
    index === 10 ? { ...item, lastAppliedRevision: "d".repeat(64) } : item,
  );
  assert.notEqual(orderedCatalogVersion(changed), version);
  assert.equal(
    selectNativeCatalogPage({
      items: changed,
      page: 1,
      catalogVersion: version,
    }).reason,
    "catalog_changed",
  );
});

test("one-product remainder uses native single-product detail", () => {
  const retailerId = `spz_${"e".repeat(32)}`;
  const payload = buildMetaWhatsAppSingleProductPayload({
    recipient: "+27821234567",
    catalogId: "1234567890",
    productRetailerId: retailerId,
  });
  assert.equal(payload.interactive.type, "product");
  assert.deepEqual(payload.interactive.action, {
    catalog_id: "1234567890",
    product_retailer_id: retailerId,
  });
});

test("native carousel transport performs one provider call and stores one wamid", async () => {
  const payload = buildMetaWhatsAppProductCarouselPayload({
    recipient: "+27821234567",
    catalogId: "1234567890",
    productRetailerIds: Array.from(
      { length: 10 },
      (_, index) => `spz_${String(index).padStart(32, "0")}`,
    ),
  });
  const calls = [];
  await withEnvironmentAsync(
    { META_WHATSAPP_ACCESS_TOKEN: "test-only-token" },
    async () => {
      const result = await sendMetaWhatsAppCatalog({
        config: {
          environment: "development",
          enabled: true,
          providerMode: "test",
          catalogId: "1234567890",
          phoneNumberId: "9876543210",
          graphApiVersion: "v25.0",
          canaryMerchantIds: new Set(["merchant_a"]),
          recipientCooldownMs: 7_000,
          pairLimitPauseMs: 86_400_000,
          maxAttempts: 3,
        },
        payload,
        fetchImpl: async (url, init) => {
          calls.push({ url, init });
          return new Response(
            JSON.stringify({ messages: [{ id: "wamid.carousel-one" }] }),
            { status: 200 },
          );
        },
      });
      assert.equal(result.wamid, "wamid.carousel-one");
    },
  );
  assert.equal(calls.length, 1);
  assert.equal(JSON.parse(calls[0].init.body).interactive.type, "carousel");
});

test("native Meta transport makes one request and accepts one wamid", async () => {
  const ids = Array.from(
    { length: 10 },
    (_, index) => `spz_${String(index).padStart(32, "0")}`,
  );
  const payload = buildMetaWhatsAppProductListPayload({
    recipient: "+27821234567",
    catalogId: "1234567890",
    productRetailerIds: ids,
  });
  const calls = [];
  await withEnvironmentAsync(
    { META_WHATSAPP_ACCESS_TOKEN: "test-only-token" },
    async () => {
      const result = await sendMetaWhatsAppProductList({
        config: {
          environment: "development",
          enabled: true,
          providerMode: "test",
          catalogId: "1234567890",
          phoneNumberId: "9876543210",
          graphApiVersion: "v25.0",
          canaryMerchantIds: new Set(["merchant_a"]),
          recipientCooldownMs: 7_000,
          maxAttempts: 3,
        },
        payload,
        fetchImpl: async (url, init) => {
          calls.push({ url, init });
          return new Response(
            JSON.stringify({ messages: [{ id: "wamid.dev-one" }] }),
            {
              status: 200,
              headers: { "content-type": "application/json" },
            },
          );
        },
      });
      assert.equal(result.wamid, "wamid.dev-one");
    },
  );
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /\/9876543210\/messages$/);
  assert.equal(JSON.parse(calls[0].init.body).type, "interactive");
});

test("definite carousel rejection uses one product-list fallback, but ambiguity does not", async () => {
  const ids = Array.from(
    { length: 5 },
    (_, index) => `spz_${String(index).padStart(32, "0")}`,
  );
  const config = {
    environment: "development",
    enabled: true,
    providerMode: "test",
    catalogId: "1234567890",
    phoneNumberId: "9876543210",
    graphApiVersion: "v25.0",
    canaryMerchantIds: new Set(["merchant_a"]),
    recipientCooldownMs: 7_000,
    pairLimitPauseMs: 86_400_000,
    maxAttempts: 3,
  };
  const primaryPayload = buildMetaWhatsAppProductCarouselPayload({
    recipient: "+27821234567",
    catalogId: config.catalogId,
    productRetailerIds: ids,
  });
  const productListFallbackPayload = buildMetaWhatsAppProductListPayload({
    recipient: "+27821234567",
    catalogId: config.catalogId,
    productRetailerIds: ids,
  });
  await withEnvironmentAsync(
    { META_WHATSAPP_ACCESS_TOKEN: "test-only-token" },
    async () => {
      const calls = [];
      const accepted = await sendMetaWhatsAppCatalogWithFallback({
        config,
        primaryPayload,
        productListFallbackPayload,
        fetchImpl: async (_url, init) => {
          calls.push(JSON.parse(init.body).interactive.type);
          return calls.length === 1
            ? new Response(JSON.stringify({ error: { code: 131009 } }), {
                status: 400,
              })
            : new Response(
                JSON.stringify({ messages: [{ id: "wamid.list-fallback" }] }),
                { status: 200 },
              );
        },
      });
      assert.deepEqual(calls, ["carousel", "product_list"]);
      assert.deepEqual(accepted, {
        wamid: "wamid.list-fallback",
        format: "product_list",
        providerRequests: 2,
      });

      let ambiguousCalls = 0;
      await assert.rejects(
        sendMetaWhatsAppCatalogWithFallback({
          config,
          primaryPayload,
          productListFallbackPayload,
          fetchImpl: async () => {
            ambiguousCalls += 1;
            return new Response(JSON.stringify({ error: { code: 2 } }), {
              status: 503,
            });
          },
        }),
        (error) => error.ambiguous === true,
      );
      assert.equal(ambiguousCalls, 1);
    },
  );
});

test("Meta pair-limit code 131056 is a definite paced rejection", async () => {
  const config = {
    environment: "development",
    enabled: true,
    providerMode: "test",
    catalogId: "1234567890",
    phoneNumberId: "9876543210",
    graphApiVersion: "v25.0",
    canaryMerchantIds: new Set(["merchant_a"]),
    recipientCooldownMs: 7_000,
    maxAttempts: 3,
  };
  const payload = buildMetaWhatsAppProductListPayload({
    recipient: "+27821234567",
    catalogId: config.catalogId,
    productRetailerIds: Array.from(
      { length: 10 },
      (_, index) => `spz_${String(index).padStart(32, "0")}`,
    ),
  });
  await withEnvironmentAsync(
    { META_WHATSAPP_ACCESS_TOKEN: "test-only-token" },
    async () => {
      await assert.rejects(
        sendMetaWhatsAppProductList({
          config,
          payload,
          fetchImpl: async () =>
            new Response(
              JSON.stringify({
                error: {
                  code: 131056,
                  message: "Pair rate limit hit",
                },
              }),
              {
                status: 400,
                headers: { "content-type": "application/json" },
              },
            ),
        }),
        (error) => {
          assert.equal(error.providerCode, "META_WHATSAPP_400_131056_");
          assert.equal(error.retryable, true);
          assert.equal(error.ambiguous, false);
          return true;
        },
      );
    },
  );
});

test("transport classifies explicit rejection, 429, 5xx, and post-dispatch ambiguity", async () => {
  const config = {
    environment: "development",
    enabled: true,
    providerMode: "test",
    catalogId: "1234567890",
    phoneNumberId: "9876543210",
    graphApiVersion: "v25.0",
    canaryMerchantIds: new Set(["merchant_a"]),
    recipientCooldownMs: 7_000,
    pairLimitPauseMs: 86_400_000,
    maxAttempts: 3,
  };
  const payload = buildMetaWhatsAppProductCarouselPayload({
    recipient: "+27821234567",
    catalogId: config.catalogId,
    productRetailerIds: Array.from(
      { length: 5 },
      (_, index) => `spz_${String(index).padStart(32, "0")}`,
    ),
  });
  await withEnvironmentAsync(
    { META_WHATSAPP_ACCESS_TOKEN: "test-only-token" },
    async () => {
      const cases = [
        {
          name: "explicit",
          response: () =>
            new Response(JSON.stringify({ error: { code: 131009 } }), {
              status: 400,
            }),
          retryable: false,
          ambiguous: false,
        },
        {
          name: "rate-limit",
          response: () =>
            new Response(JSON.stringify({ error: { code: 4 } }), {
              status: 429,
              headers: { "retry-after": "12" },
            }),
          retryable: true,
          ambiguous: false,
          retryAfterMs: 12_000,
        },
        {
          name: "server-error-after-dispatch",
          response: () =>
            new Response(JSON.stringify({ error: { code: 2 } }), {
              status: 503,
            }),
          retryable: false,
          ambiguous: true,
        },
      ];
      for (const scenario of cases) {
        await assert.rejects(
          sendMetaWhatsAppCatalog({
            config,
            payload,
            fetchImpl: async () => scenario.response(),
          }),
          (error) => {
            assert.equal(error.retryable, scenario.retryable, scenario.name);
            assert.equal(error.ambiguous, scenario.ambiguous, scenario.name);
            if (scenario.retryAfterMs) {
              assert.equal(error.retryAfterMs, scenario.retryAfterMs);
            }
            return true;
          },
        );
      }
      await assert.rejects(
        sendMetaWhatsAppCatalog({
          config,
          payload,
          fetchImpl: async () => {
            throw new Error("socket closed after write");
          },
        }),
        (error) => {
          assert.equal(error.retryable, false);
          assert.equal(error.ambiguous, true);
          return true;
        },
      );
      await assert.rejects(
        sendMetaWhatsAppCatalog({
          config,
          payload,
          fetchImpl: async () =>
            new Response(
              JSON.stringify({
                messages: [{ id: "wamid.one" }, { id: "wamid.two" }],
              }),
              { status: 200 },
            ),
        }),
        (error) => {
          assert.equal(error.ambiguous, true);
          return true;
        },
      );
    },
  );
});

test("delivery claim prevents duplicates and never retries an unknown outcome", () => {
  const base = {
    fingerprint: "fingerprint-a",
    nowMs: 10_000,
    recipientNextAllowedAtMs: 0,
    maxAttempts: 3,
  };
  assert.deepEqual(decideNativeProductListClaim(base), {
    action: "send",
    attempt: 1,
  });
  assert.deepEqual(
    decideNativeProductListClaim({
      ...base,
      existing: {
        fingerprint: "fingerprint-a",
        status: "sent",
        attempts: 1,
        wamid: "wamid.original",
      },
    }),
    { action: "duplicate", wamid: "wamid.original" },
  );
  assert.deepEqual(
    decideNativeProductListClaim({
      ...base,
      existing: {
        fingerprint: "fingerprint-a",
        status: "sending",
        attempts: 1,
        leaseUntilMs: 9_999,
      },
    }),
    { action: "needs_review" },
  );
  assert.deepEqual(
    decideNativeProductListClaim({
      ...base,
      existing: {
        fingerprint: "fingerprint-b",
        status: "sent",
        wamid: "wamid.wrong",
      },
    }),
    { action: "idempotency_conflict" },
  );
  assert.deepEqual(
    [1, 2, 3, 10].map(productListRetryDelayMs),
    [7_000, 14_000, 28_000, 28_000],
  );
});

test("native product-list gates require dev-only provider and exact canary", () => {
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      WHATSAPP_PRODUCT_LIST_ENABLED: "true",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "test",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_SENDER_NUMBER_ID: "9876543210",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "merchant_a,merchant_b",
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      assert.throws(
        whatsappProductListRuntimeConfig,
        /DEVELOPMENT_WHATSAPP_PRODUCT_LIST_SINGLE_MERCHANT_REQUIRED/,
      );
    },
  );

  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      WHATSAPP_PRODUCT_LIST_ENABLED: "true",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "test",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_SENDER_NUMBER_ID: "9876543210",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "merchant_a",
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      const config = whatsappProductListRuntimeConfig();
      assert.equal(config.enabled, true);
      assert.equal(config.providerMode, "test");
      assert.deepEqual([...config.canaryMerchantIds], ["merchant_a"]);
    },
  );
  withEnvironment(
    {
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      WHATSAPP_PRODUCT_LIST_ENABLED: "true",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "live",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_SENDER_NUMBER_ID: "9876543210",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "merchant_a",
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      assert.throws(
        whatsappProductListRuntimeConfig,
        /DEVELOPMENT_META_WHATSAPP_MESSAGE_MODE_INVALID/,
      );
    },
  );
});

test("native delivery selects products server-side and rechecks visibility", () => {
  const deliverySource = readFileSync(
    join(sourceRoot, "nativeProductListDelivery.ts"),
    "utf8",
  );
  assert.match(
    deliverySource,
    /users\/\$\{merchant\}\/products\/\$\{item\.productId\}/,
  );
  assert.match(deliverySource, /buildMerchantCatalogDecision/);
  assert.match(deliverySource, /mappingMatchesCurrentProjection/);
  assert.match(deliverySource, /status === "active"/);
  assert.doesNotMatch(deliverySource, /req\.body\?\.productRetailerIds/);
  assert.equal(deliverySource.includes("supplierCatalogProducts"), false);
});

test("every development catalogue entrypoint enforces the merchant canary", () => {
  const queueSource = readFileSync(join(sourceRoot, "catalogQueue.ts"), "utf8");
  const statusSource = readFileSync(join(sourceRoot, "catalogStatus.ts"), "utf8");
  assert.match(queueSource, /whatsappCatalogMerchantAllowed\(config, merchantId\)/);
  assert.match(statusSource, /whatsappCatalogMerchantAllowed\(config, merchantId\)/);
  assert.match(statusSource, /reason: "merchant_not_allowed"/);
});

test("send-time selection rejects cross-tenant, internal, and stale mappings", () => {
  const decision = buildMerchantCatalogDecision({
    merchantId: "merchant_a",
    productId: "product_1",
    product,
  });
  const base = {
    requestedMerchantId: "merchant_a",
    mappingMerchantId: "merchant_a",
    productId: "product_1",
    retailerId: decision.retailerId,
    lastAppliedRevision: decision.revision,
    product,
    merchant: {},
  };
  assert.equal(mappingMatchesCurrentProjection(base), true);
  assert.equal(
    mappingMatchesCurrentProjection({
      ...base,
      requestedMerchantId: "merchant_b",
    }),
    false,
  );
  assert.equal(
    mappingMatchesCurrentProjection({
      ...base,
      product: { ...product, dropshipListingState: "internal" },
    }),
    false,
  );
  assert.equal(
    mappingMatchesCurrentProjection({
      ...base,
      product: { ...product, sellingPrice: 123.45 },
    }),
    false,
  );
});

test("catalog resolution distinguishes a cross-merchant cart from a missing product", () => {
  const base = {
    exists: true,
    status: "active",
    requestedMerchantId: "merchant_a",
    mappingMerchantId: "merchant_a",
    requestedRetailerId: `spz_${"a".repeat(32)}`,
    mappingRetailerId: `spz_${"a".repeat(32)}`,
  };

  assert.equal(catalogMappingUnavailableReason(base), undefined);
  assert.equal(
    catalogMappingUnavailableReason({
      ...base,
      mappingMerchantId: "merchant_b",
    }),
    "merchant_mismatch",
  );
  assert.equal(
    catalogMappingUnavailableReason({ ...base, exists: false }),
    "not_found",
  );
  assert.equal(
    catalogMappingUnavailableReason({ ...base, status: "deleted" }),
    "not_found",
  );
});

test("catalog-origin cart writes revalidate mapping and projection atomically", () => {
  const source = readFileSync(
    join(sourceRoot, "..", "ecommerce", "addToCart.ts"),
    "utf8",
  );
  assert.match(source, /addWhatsAppCatalogProductToCartBotHttp/);
  assert.match(source, /requireBotRequest/);
  assert.match(source, /buildMerchantCatalogDecision/);
  assert.match(source, /mapping\.merchantId !== merchantId/);
  assert.match(source, /mapping\.productId !== productId/);
  assert.match(source, /decision\.revision !== mapping\.lastAppliedRevision/);
  assert.match(source, /db\.runTransaction/);
  assert.match(source, /catalogRetailerId: retailerId/);
});

test("delivery ledgers are denied to every client in Firestore rules", () => {
  const rules = readFileSync(
    join(
      dirname(fileURLToPath(import.meta.url)),
      "..",
      "..",
      "firestore.rules",
    ),
    "utf8",
  );
  for (const collectionName of [
    "whatsappProductListDeliveries",
    "whatsappProductListRecipientState",
  ]) {
    assert.match(
      rules,
      new RegExp(
        `match /${collectionName}/\\{[^}]+\\} \\{\\s*allow read, write: if false;`,
      ),
    );
  }
});

test("delivery dashboard flags ambiguous, failed, and stale sends", () => {
  const health = summarizeProductListDeliveryHealth(
    [
      { status: "sent", updatedAtMs: 100_000 },
      { status: "retry_wait", updatedAtMs: 100_000 },
      { status: "needs_review", updatedAtMs: 100_000 },
      { status: "failed", updatedAtMs: 100_000 },
      { status: "sending", updatedAtMs: 1_000 },
    ],
    100_000,
  );
  assert.deepEqual(health, {
    total: 5,
    sent: 1,
    sending: 1,
    retryWaiting: 1,
    needsReview: 1,
    failed: 1,
    staleSending: 1,
    healthy: false,
  });
});

test("catalog sync is isolated from supplier discovery and financial state", () => {
  const source = readdirSync(sourceRoot)
    .filter((name) => name.endsWith(".ts"))
    .map((name) => readFileSync(join(sourceRoot, name), "utf8"))
    .join("\n");
  assert.match(source, /users\/\$\{merchantId\}\/products\/\$\{productId\}/);
  for (const forbidden of [
    "supplierCatalogProducts",
    "bankingDetails",
    "merchantPaymentProfiles",
    "paymentIntents",
    "payoutRequests",
    "settlements",
    "Paystack",
  ]) {
    assert.equal(source.includes(forbidden), false, forbidden);
  }
});
