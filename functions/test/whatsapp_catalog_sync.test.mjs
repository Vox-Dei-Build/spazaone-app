import assert from "node:assert/strict";
import { createHash } from "node:crypto";
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
  isMerchantProductVisibleInBotCatalog,
  merchantBotCatalogVisibilityFilter,
  nativeProductListDeliveryEnabled,
} from "../lib/ecommerce/botCatalogVisibility.js";
import {
  buildMetaCatalogBatchRequests,
  parseMetaCatalogBatchStatus,
} from "../lib/whatsapp/metaCatalogClient.js";
import {
  classifyCatalogImageResponse,
  detectedCatalogImageContentType,
  supportedCatalogImageContentType,
} from "../lib/whatsapp/catalogImage.js";
import { catalogRetryDelayMs } from "../lib/whatsapp/catalogWorker.js";
import { whatsappCatalogRuntimeConfig } from "../lib/whatsapp/catalogConfig.js";
import {
  buildMetaWhatsAppProductCarouselPayload,
  buildMetaWhatsAppProductListPayload,
  buildMetaWhatsAppSingleProductPayload,
  controlledWhatsAppRecipientDigest,
  decideNativeProductListClaim,
  orderedCatalogVersion,
  productListDeliveryFingerprint,
  productListRetryDelayMs,
  selectNativeCatalogPage,
  sendMetaWhatsAppCatalog,
  sendMetaWhatsAppCatalogWithFallback,
  sendMetaWhatsAppProductList,
  whatsappNativeCatalogAccessReason,
  whatsappProductListMerchantAllowed,
  whatsappProductListMerchantRolloutAllowed,
  whatsappProductListRuntimeConfig,
} from "../lib/whatsapp/nativeProductList.js";
import { summarizeProductListDeliveryHealth } from "../lib/whatsapp/nativeProductListStatus.js";
import { summarizeMerchantWhatsAppCatalogCompleteness } from "../lib/whatsapp/catalogCompleteness.js";
import {
  catalogMappingUnavailableReason,
  merchantAvailableForNativeCatalog,
  mappingMatchesCurrentProjection,
  nativeCatalogProductAllowedByMerchantFeature,
  nativeCatalogProductKind,
  nativeCatalogSessionGate,
  nativeCatalogSupplierListingMatches,
  resolvedMerchantWhatsAppCatalogProductResponse,
  runNativeCatalogPreDispatch,
  WHATSAPP_PRODUCT_LIST_DELIVERY_RETENTION_MS,
  whatsappProductListDeliveryExpiresAt,
  whatsappProductListRecipientStateExpiresAt,
} from "../lib/whatsapp/nativeProductListDelivery.js";
import {
  collectAllNativeCatalogMappingPages,
  collectNativeCatalogBatchReads,
} from "../lib/whatsapp/catalogMappingPages.js";
import {
  WHATSAPP_CATALOG_CART_MAX_ITEMS,
  WhatsAppCatalogCartValidationError,
  customerMatchesWhatsAppRecipient,
  decideCatalogCartIdempotency,
  nativeCatalogCartFingerprint,
  nativeCatalogCartStateDocumentId,
  parseWhatsAppCatalogCartRequest,
  planStoredNativeCatalogCart,
  planWhatsAppCatalogCartReplacement,
  validateCatalogCartMappings,
} from "../lib/ecommerce/replaceWhatsAppCatalogCart.js";

const sourceRoot = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "src",
  "whatsapp",
);
const ecommerceSourceRoot = join(sourceRoot, "..", "ecommerce");

const product = {
  name: "Maize Meal 5 kg",
  description: "Merchant product",
  sellingPrice: 122.54,
  image: "https://images.example.test/maize.jpg",
  whatsappListed: true,
  checkoutUrl: "https://shop.example.test/order/maize",
};

const controlledRecipient = "+27821234567";
const controlledRecipientHashKey = "whatsapp-catalog-test-recipient-key-2026";
const controlledRecipientHash = controlledWhatsAppRecipientDigest(
  controlledRecipient,
  controlledRecipientHashKey,
);
const developmentCatalogScope = {
  WHATSAPP_CATALOG_QUEUE_ENABLED: "true",
  WHATSAPP_CATALOG_SYNC_ENABLED: "true",
  META_CATALOG_PROVIDER_MODE: "test",
  WHATSAPP_CATALOG_CANARY_MERCHANT_IDS: "merchant_a",
  WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED: "false",
};
const productionCatalogFullScope = {
  WHATSAPP_CATALOG_QUEUE_ENABLED: "true",
  WHATSAPP_CATALOG_SYNC_ENABLED: "true",
  META_CATALOG_PROVIDER_MODE: "live",
  WHATSAPP_CATALOG_CANARY_MERCHANT_IDS: "",
  WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED: "true",
};
const productionCatalogCanaryScope = {
  ...productionCatalogFullScope,
  WHATSAPP_CATALOG_CANARY_MERCHANT_IDS: "merchant_a",
  WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED: "false",
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

function catalogCartFixture(count = 1) {
  const merchantId = "merchant_a";
  const merchant = {
    name: "Merchant A",
    whatsappOrdering: { orderingUrl: "https://shop.example.test/merchant-a" },
  };
  const requests = [];
  const mappings = [];
  const products = [];
  for (let index = 0; index < count; index += 1) {
    const productId = `product_${index + 1}`;
    const priceMinor = 1_000 + index;
    const value = {
      name: `Product ${index + 1}`,
      description: `Product ${index + 1} description`,
      sellPriceMinor: priceMinor,
      imageUrl: `https://images.example.test/product-${index + 1}.jpg`,
      whatsappListed: true,
      quantity: 50,
    };
    const decision = buildMerchantCatalogDecision({
      merchantId,
      productId,
      product: value,
      merchant,
    });
    assert.equal(decision.action, "upsert");
    requests.push({
      retailerId: decision.retailerId,
      quantity: (index % 3) + 1,
      expectedPriceMinor: priceMinor,
    });
    mappings.push({
      exists: true,
      status: "active",
      merchantId,
      productId,
      retailerId: decision.retailerId,
      lastAppliedRevision: decision.revision,
    });
    products.push(value);
  }
  const resolved = validateCatalogCartMappings({
    merchantId,
    items: requests,
    mappings,
  });
  return { merchantId, merchant, requests, mappings, products, resolved };
}

function planCatalogCart(fixture) {
  return planWhatsAppCatalogCartReplacement({
    merchantId: fixture.merchantId,
    merchantExists: true,
    merchant: fixture.merchant,
    items: fixture.resolved.map((request, index) => ({
      request,
      product: fixture.products[index],
    })),
  });
}

function storedNativeCartFixture(count = 1) {
  const fixture = catalogCartFixture(count);
  const customerId = "customer_1";
  const catalogId = "1234567890";
  const plan = planCatalogCart(fixture);
  const fingerprint = nativeCatalogCartFingerprint({
    merchantId: fixture.merchantId,
    customerId,
    catalogId,
    items: plan.items,
  });
  return {
    ...fixture,
    customerId,
    catalogId,
    plan,
    fingerprint,
    summary: {
      source: "whatsapp_native_catalog",
      catalogId,
      nativeCartFingerprint: fingerprint,
      currency: plan.currency,
      lineCount: plan.lineCount,
      itemsCount: plan.itemsCount,
      total: plan.total,
      totalMinor: plan.totalMinor,
    },
    state: {
      exists: true,
      merchantId: fixture.merchantId,
      customerId,
      catalogId,
      fingerprint,
      schemaVersion: 1,
    },
    lines: plan.items.map((item) => ({
      productId: item.productId,
      quantity: item.quantity,
      source: "whatsapp_native_catalog",
      retailerId: item.retailerId,
      catalogRevision: item.catalogRevision,
      catalogPriceMinor: item.priceMinor,
    })),
  };
}

function planStoredCart(fixture) {
  return planStoredNativeCatalogCart({
    merchantId: fixture.merchantId,
    customerId: fixture.customerId,
    merchantExists: true,
    merchant: fixture.merchant,
    summary: fixture.summary,
    state: fixture.state,
    lines: fixture.lines,
    mappings: fixture.mappings,
    products: fixture.products,
  });
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

test("dark native delivery preserves legacy bot catalogue visibility", () => {
  for (const configured of [undefined, "", "false", "1"]) {
    withEnvironment({ WHATSAPP_PRODUCT_LIST_ENABLED: configured }, () => {
      assert.equal(nativeProductListDeliveryEnabled(), false);
      assert.equal(
        isMerchantProductVisibleInBotCatalog({
          whatsappListed: true,
          dropshipListingState: "internal",
          customerVisible: false,
          archived: true,
        }),
        true,
      );
      assert.equal(
        isMerchantProductVisibleInBotCatalog({
          whatsappEnabled: true,
          visibility: "hidden",
        }),
        true,
      );
      assert.equal(
        isMerchantProductVisibleInBotCatalog({
          availableOnWhatsApp: true,
          listingState: "draft",
        }),
        true,
      );
      assert.equal(
        isMerchantProductVisibleInBotCatalog({
          whatsappListed: "true",
          whatsappEnabled: false,
          availableOnWhatsApp: false,
        }),
        false,
      );
    });
  }
});

test("enabled native delivery applies customer-visible bot catalogue filtering", () => {
  withEnvironment(
    {
      ...productionCatalogFullScope,
      WHATSAPP_PRODUCT_LIST_ENABLED: " TRUE ",
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "live",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_SENDER_NUMBER_ID: "9876543210",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "",
      WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "true",
      WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES: "",
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: controlledRecipientHashKey,
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      assert.equal(nativeProductListDeliveryEnabled(), true);
      const productVisible = merchantBotCatalogVisibilityFilter();
      assert.equal(
        productVisible({
          whatsappListed: true,
          dropshipListingState: "active",
        }),
        true,
      );
      for (const internalMarker of [
        { dropshipListingState: "internal" },
        { internalOnly: true },
        { visibility: "hidden" },
        { customerVisible: false },
      ]) {
        assert.equal(
          productVisible({
            whatsappListed: true,
            ...internalMarker,
          }),
          false,
        );
      }
    },
  );
});

test("enabled native visibility fails closed on incomplete runtime configuration", () => {
  withEnvironment(
    {
      ...productionCatalogFullScope,
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      WHATSAPP_PRODUCT_LIST_ENABLED: "true",
      WHATSAPP_CATALOG_SYNC_ENABLED: "false",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "live",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_SENDER_NUMBER_ID: "9876543210",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "",
      WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "true",
      WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES: "",
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: controlledRecipientHashKey,
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      assert.throws(
        merchantBotCatalogVisibilityFilter,
        /WHATSAPP_CATALOG_SYNC_REQUIRED/,
      );
    },
  );
});

test("merchant bot endpoint resolves the validated visibility filter once per request", () => {
  const source = readFileSync(
    join(ecommerceSourceRoot, "getMerchantCatalogBotHttp.ts"),
    "utf8",
  );
  assert.match(
    source,
    /const productVisible = merchantBotCatalogVisibilityFilter\(\);/,
  );
  assert.match(source, /if \(!productVisible\(data\)\) return null;/);
  assert.match(source, /"WHATSAPP_CATALOG_RECIPIENT_HASH_KEY"/);
  assert.equal(
    (source.match(/merchantBotCatalogVisibilityFilter\(\)/g) ?? []).length,
    1,
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
  assert.equal(supportedCatalogImageContentType("image/jpg"), true);
  assert.equal(
    detectedCatalogImageContentType(Uint8Array.from([0xff, 0xd8, 0xff, 0xe0])),
    "image/jpeg",
  );
  assert.equal(
    detectedCatalogImageContentType(
      Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    ),
    "image/png",
  );
  assert.equal(
    classifyCatalogImageResponse({
      status: 206,
      contentType: "binary/octet-stream",
      detectedContentType: "image/jpeg",
      finalUrlIsHttps: true,
    }).state,
    "valid",
  );
  assert.equal(
    classifyCatalogImageResponse({
      status: 200,
      contentType: "text/html",
      detectedContentType: "image/jpeg",
      finalUrlIsHttps: true,
    }).state,
    "invalid",
  );
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

test("native product list sends thirty merchant retailer IDs in one payload", () => {
  const ids = Array.from(
    { length: 30 },
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
  assert.throws(
    () =>
      buildMetaWhatsAppProductListPayload({
        recipient: "+27821234567",
        catalogId: "1234567890",
        productRetailerIds: [...ids, `spz_${"f".repeat(32)}`],
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
  const empty = selectNativeCatalogPage({ items: items(0), page: 0 });
  assert.equal(empty.outcome, "fallback");
  assert.equal(empty.reason, "no_ready_products");

  const single = selectNativeCatalogPage({ items: items(1), page: 0 });
  assert.equal(single.outcome, "ready");
  assert.equal(single.format, "single_product");
  assert.equal(single.items.length, 1);
  assert.equal(single.pageCount, 1);

  for (const count of [2, 4, 5, 9, 10, 11, 22, 30]) {
    const decision = selectNativeCatalogPage({ items: items(count), page: 0 });
    assert.equal(decision.outcome, "ready", `count=${count}`);
    assert.equal(decision.format, "product_list");
    assert.equal(decision.items.length, count);
    assert.equal(decision.pageCount, 1);
  }

  for (const count of [31, 60, 61]) {
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
      count % 30 === 1 ? "single_product" : "product_list",
    );
  }
});

test("continuation pages require the unchanged ordered catalog version", () => {
  const items = Array.from({ length: 31 }, (_, index) => ({
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
    index === 30 ? { ...item, lastAppliedRevision: "d".repeat(64) } : item,
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
  assert.equal(
    selectNativeCatalogPage({
      items: changed,
      page: 0,
      catalogVersion: version,
    }).reason,
    "catalog_changed",
  );
  assert.equal(
    selectNativeCatalogPage({
      items,
      page: 0,
      catalogVersion: version,
    }).outcome,
    "ready",
  );
});

test("a pending unrelated product gates only a new catalogue session", () => {
  const merchantId = "merchant_a";
  const merchant = {
    whatsappOrdering: { orderingUrl: "https://shop.example.test/merchant-a" },
  };
  const products = Array.from({ length: 32 }, (_, index) => ({
    id: `product_${index + 1}`,
    data: {
      ...product,
      name: `Product ${index + 1}`,
      sellingPrice: 10 + index,
      image: `https://images.example.test/product-${index + 1}.jpg`,
    },
  }));
  const decisions = products.map(({ id, data }) =>
    buildMerchantCatalogDecision({
      merchantId,
      productId: id,
      product: data,
      merchant,
    }),
  );
  const visible = decisions.slice(0, 31).map((decision) => ({
    retailerId: decision.retailerId,
    lastAppliedRevision: decision.revision,
  }));
  const incomplete = summarizeMerchantWhatsAppCatalogCompleteness({
    merchantId,
    merchant,
    products,
    mappings: decisions.slice(0, 31).map((decision, index) => ({
      merchantId,
      productId: products[index].id,
      retailerId: decision.retailerId,
      status: "active",
      metaPolicyStatus: "accepted",
      lastAppliedRevision: decision.revision,
    })),
  });
  assert.equal(incomplete.complete, false);
  assert.equal(incomplete.missingProducts, 1);
  assert.equal(
    nativeCatalogSessionGate({ page: 0, catalogVersion: "" }),
    "completeness_required",
  );

  const first = selectNativeCatalogPage({ items: visible, page: 0 });
  assert.equal(first.outcome, "ready");
  assert.equal(
    nativeCatalogSessionGate({
      page: 1,
      catalogVersion: first.catalogVersion,
    }),
    undefined,
  );
  assert.equal(
    selectNativeCatalogPage({
      items: visible,
      page: 1,
      catalogVersion: first.catalogVersion,
    }).outcome,
    "ready",
  );
  assert.equal(
    selectNativeCatalogPage({
      items: visible,
      page: 0,
      catalogVersion: first.catalogVersion,
    }).outcome,
    "ready",
  );
  assert.equal(
    nativeCatalogSessionGate({ page: 1, catalogVersion: "" }),
    "catalog_version_required",
  );
});

test("send-time mapping pagination does not truncate a merchant above 2,000 items", async () => {
  const all = Array.from({ length: 2_001 }, (_, index) => ({
    id: `mapping-${String(index).padStart(4, "0")}`,
  }));
  const cursors = [];
  const collected = await collectAllNativeCatalogMappingPages(
    async (cursor, limit) => {
      cursors.push(cursor ?? null);
      const start = cursor
        ? all.findIndex((item) => item.id === cursor) + 1
        : 0;
      return all.slice(start, start + limit);
    },
    500,
  );

  assert.equal(collected.length, 2_001);
  assert.deepEqual(collected, all);
  assert.deepEqual(cursors, [
    null,
    "mapping-0499",
    "mapping-0999",
    "mapping-1499",
    "mapping-1999",
  ]);

  const batches = [];
  const read = await collectNativeCatalogBatchReads(
    all,
    async (batch) => {
      batches.push(batch.length);
      return batch.map((item) => ({ readId: item.id }));
    },
    200,
  );
  assert.deepEqual(
    batches,
    [200, 200, 200, 200, 200, 200, 200, 200, 200, 200, 1],
  );
  assert.deepEqual(
    read.map((item) => item.readId),
    all.map((item) => item.id),
  );
});

test("pre-dispatch storage failures select one compact fallback without provider delivery", async () => {
  let providerRequests = 0;
  const result = await runNativeCatalogPreDispatch(async () => {
    throw new Error("synthetic-firestore-read-failure");
  });
  if (result.outcome === "ready") providerRequests += 1;

  assert.deepEqual(result, {
    outcome: "fallback",
    reason: "catalog_temporarily_unavailable",
  });
  assert.equal(providerRequests, 0);
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
    { length: 22 },
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
  const sent = JSON.parse(calls[0].init.body);
  assert.equal(sent.type, "interactive");
  assert.equal(sent.interactive.type, "product_list");
  assert.equal(sent.interactive.action.sections[0].product_items.length, 22);
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

test("product list is primary and a small list uses one carousel only after definite rejection", async () => {
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
  const primaryPayload = buildMetaWhatsAppProductListPayload({
    recipient: "+27821234567",
    catalogId: config.catalogId,
    productRetailerIds: ids,
  });
  const carouselFallbackPayload = buildMetaWhatsAppProductCarouselPayload({
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
        carouselFallbackPayload,
        fetchImpl: async (_url, init) => {
          calls.push(JSON.parse(init.body).interactive.type);
          return calls.length === 1
            ? new Response(JSON.stringify({ error: { code: 131009 } }), {
                status: 400,
              })
            : new Response(
                JSON.stringify({ messages: [{ id: "wamid.carousel-fallback" }] }),
                { status: 200 },
              );
        },
      });
      assert.deepEqual(calls, ["product_list", "carousel"]);
      assert.deepEqual(accepted, {
        wamid: "wamid.carousel-fallback",
        format: "product_carousel",
        providerRequests: 2,
      });

      let ambiguousCalls = 0;
      await assert.rejects(
        sendMetaWhatsAppCatalogWithFallback({
          config,
          primaryPayload,
          carouselFallbackPayload,
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

test("pair-limit completion persists delivery and recipient pause atomically", () => {
  const deliverySource = readFileSync(
    join(sourceRoot, "nativeProductListDelivery.ts"),
    "utf8",
  );
  assert.match(deliverySource, /recipientPauseUntilMs/);
  assert.match(
    deliverySource,
    /tx\.set\([\s\S]*WHATSAPP_PRODUCT_LIST_RECIPIENT_STATE/,
  );
  assert.match(deliverySource, /retryAfterMs: effectiveRetryDelay/);
  assert.doesNotMatch(deliverySource, /async function pauseRecipient/);
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
      for (const body of [
        { messages: [] },
        { messages: [{ id: "abc" }] },
        { messages: [{ id: `wamid.${"x".repeat(501)}` }] },
      ]) {
        await assert.rejects(
          sendMetaWhatsAppCatalog({
            config,
            payload,
            fetchImpl: async () =>
              new Response(JSON.stringify(body), { status: 200 }),
          }),
          (error) => {
            assert.equal(
              error.providerCode,
              "META_WHATSAPP_MESSAGE_ID_OUTCOME_UNKNOWN",
            );
            assert.equal(error.retryable, false);
            assert.equal(error.ambiguous, true);
            return true;
          },
        );
      }
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
  for (const wamid of ["", "abc", `wamid.${"x".repeat(501)}`]) {
    assert.deepEqual(
      decideNativeProductListClaim({
        ...base,
        existing: {
          fingerprint: "fingerprint-a",
          status: "sent",
          attempts: 1,
          wamid,
        },
      }),
      { action: "needs_review" },
    );
  }
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
    decideNativeProductListClaim({
      ...base,
      recipientNextAllowedAtMs: 96_400_000,
      existing: {
        fingerprint: "fingerprint-a",
        status: "retry_wait",
        attempts: 1,
        nextAttemptAtMs: 17_000,
      },
    }),
    { action: "retry_later", retryAfterMs: 96_390_000 },
  );
  assert.deepEqual(
    [1, 2, 3, 10].map(productListRetryDelayMs),
    [7_000, 14_000, 28_000, 28_000],
  );
});

test("native delivery and recipient-state expiry is a future 30-day Firestore timestamp on every write path", () => {
  const nowMs = Date.parse("2026-08-28T08:00:00.000Z");
  const expiresAt = whatsappProductListDeliveryExpiresAt(nowMs);
  assert.equal(
    expiresAt.toMillis(),
    nowMs + WHATSAPP_PRODUCT_LIST_DELIVERY_RETENTION_MS,
  );
  assert.equal(
    WHATSAPP_PRODUCT_LIST_DELIVERY_RETENTION_MS,
    30 * 24 * 60 * 60 * 1_000,
  );
  assert.throws(
    () => whatsappProductListDeliveryExpiresAt(-1),
    /WHATSAPP_PRODUCT_LIST_DELIVERY_TIME_INVALID/,
  );
  assert.equal(
    whatsappProductListRecipientStateExpiresAt(nowMs).toMillis(),
    expiresAt.toMillis(),
  );

  const source = readFileSync(
    join(sourceRoot, "nativeProductListDelivery.ts"),
    "utf8",
  );
  assert.equal((source.match(/expiresAt,/g) ?? []).length, 2);
  assert.equal(
    (
      source.match(
        /expiresAt:\s*whatsappProductListDeliveryExpiresAt\(nowMs\)/g,
      ) ?? []
    ).length,
    1,
  );
  assert.equal(
    (
      source.match(
        /expiresAt:\s*whatsappProductListRecipientStateExpiresAt\(nowMs\)/g,
      ) ?? []
    ).length,
    2,
  );
});

test("Firestore index config preserves every existing entry and declares all native-catalog TTL policies", () => {
  const config = JSON.parse(
    readFileSync(
      join(
        dirname(fileURLToPath(import.meta.url)),
        "..",
        "..",
        "firestore.indexes.json",
      ),
      "utf8",
    ),
  );
  const digest = (value) =>
    createHash("sha256").update(JSON.stringify(value)).digest("hex");
  const ttlPolicies = config.fieldOverrides.filter(
    (field) => field.ttl === true,
  );
  const existingFieldOverrides = config.fieldOverrides.filter(
    (field) => field.ttl !== true,
  );

  assert.deepEqual(ttlPolicies, [
    {
      collectionGroup: "whatsappCatalogCartReplacements",
      fieldPath: "expiresAt",
      ttl: true,
      indexes: [],
    },
    {
      collectionGroup: "whatsappProductListDeliveries",
      fieldPath: "expiresAt",
      ttl: true,
      indexes: [],
    },
    {
      collectionGroup: "whatsappProductListRecipientState",
      fieldPath: "expiresAt",
      ttl: true,
      indexes: [],
    },
  ]);
  assert.equal(config.indexes.length, 24);
  assert.equal(existingFieldOverrides.length, 7);
  assert.equal(
    digest(config.indexes),
    "5c13abe2069135854f7fdeae950a20a51d32fa78d1764759486389f1acbcc134",
  );
  assert.equal(
    digest(existingFieldOverrides),
    "999b81113ca772777f626296ec2107d119057f05bf9b85f763cc38a761779f48",
  );
});

test("native product-list gates require dev-only provider and exact canary", () => {
  withEnvironment(
    {
      ...developmentCatalogScope,
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      WHATSAPP_PRODUCT_LIST_ENABLED: "true",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "test",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_SENDER_NUMBER_ID: "9876543210",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "merchant_a,merchant_b",
      WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "false",
      WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES: controlledRecipientHash,
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: controlledRecipientHashKey,
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
      ...developmentCatalogScope,
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      WHATSAPP_PRODUCT_LIST_ENABLED: "true",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "test",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_SENDER_NUMBER_ID: "9876543210",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "merchant_a",
      WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "false",
      WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES: controlledRecipientHash,
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: controlledRecipientHashKey,
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
      ...developmentCatalogScope,
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      WHATSAPP_PRODUCT_LIST_ENABLED: "true",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "test",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_SENDER_NUMBER_ID: "9876543210",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "merchant_a",
      WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "true",
      WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES: controlledRecipientHash,
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: controlledRecipientHashKey,
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      assert.throws(
        whatsappProductListRuntimeConfig,
        /DEVELOPMENT_WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_FORBIDDEN/,
      );
    },
  );
  withEnvironment(
    {
      ...developmentCatalogScope,
      SPAZAONE_ENVIRONMENT: "development",
      SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
      WHATSAPP_PRODUCT_LIST_ENABLED: "true",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "live",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_SENDER_NUMBER_ID: "9876543210",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "merchant_a",
      WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "false",
      WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES: controlledRecipientHash,
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: controlledRecipientHashKey,
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

test("merchant rollout status follows native delivery rather than sync", () => {
  const common = {
    ...productionCatalogFullScope,
    SPAZAONE_ENVIRONMENT: "production",
    SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
    WHATSAPP_CATALOG_ID: "1234567890",
    GCLOUD_PROJECT: undefined,
    GOOGLE_CLOUD_PROJECT: undefined,
  };

  withEnvironment(
    {
      ...common,
      WHATSAPP_PRODUCT_LIST_ENABLED: "false",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "disabled",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "",
      WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "false",
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: undefined,
    },
    () => {
      assert.equal(
        whatsappProductListMerchantRolloutAllowed("merchant_a"),
        false,
      );
    },
  );

  withEnvironment(
    {
      ...common,
      WHATSAPP_PRODUCT_LIST_ENABLED: "true",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "live",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "merchant_a",
      WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "false",
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: undefined,
    },
    () => {
      assert.equal(
        whatsappProductListMerchantRolloutAllowed("merchant_a"),
        true,
      );
      assert.equal(
        whatsappProductListMerchantRolloutAllowed("merchant_b"),
        false,
      );
    },
  );
});

test("native delivery allows all recipients only when both full-rollout gates are enabled", () => {
  withEnvironment(
    {
      ...productionCatalogFullScope,
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      WHATSAPP_PRODUCT_LIST_ENABLED: "true",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "live",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_SENDER_NUMBER_ID: "9876543210",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "",
      WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "true",
      WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES: "",
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: controlledRecipientHashKey,
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      const config = whatsappProductListRuntimeConfig();
      assert.equal(config.fullRolloutEnabled, true);
      assert.equal(
        whatsappProductListMerchantAllowed(config, "merchant_a"),
        true,
      );
      assert.equal(
        whatsappProductListMerchantAllowed(config, "merchant_b"),
        true,
      );
      assert.equal(
        whatsappProductListMerchantAllowed(
          {
            ...config,
            catalogFullRolloutEnabled: false,
            catalogCanaryMerchantIds: new Set(["merchant_a"]),
          },
          "merchant_b",
        ),
        false,
      );
      assert.equal(
        whatsappNativeCatalogAccessReason(
          config,
          "merchant_b",
          controlledRecipient,
        ),
        undefined,
      );
      assert.equal(
        whatsappNativeCatalogAccessReason(config, "merchant_b", "+27820000000"),
        undefined,
      );
      const catalogCanaryOnly = {
        ...config,
        catalogFullRolloutEnabled: false,
        catalogCanaryMerchantIds: new Set(["merchant_a"]),
        controlledRecipientHashes: new Set([controlledRecipientHash]),
      };
      assert.equal(
        whatsappNativeCatalogAccessReason(
          catalogCanaryOnly,
          "merchant_a",
          "+27820000000",
        ),
        "recipient_not_allowed",
      );
      assert.equal(
        whatsappNativeCatalogAccessReason(
          catalogCanaryOnly,
          "merchant_a",
          controlledRecipient,
        ),
        undefined,
      );
      assert.equal(
        whatsappNativeCatalogAccessReason(
          catalogCanaryOnly,
          "merchant_b",
          controlledRecipient,
        ),
        "merchant_not_allowed",
      );
      const deliveryCanaryOnly = {
        ...config,
        fullRolloutEnabled: false,
        canaryMerchantIds: new Set(["merchant_a"]),
        controlledRecipientHashes: new Set([controlledRecipientHash]),
      };
      assert.equal(
        whatsappNativeCatalogAccessReason(
          deliveryCanaryOnly,
          "merchant_a",
          "+27820000000",
        ),
        "recipient_not_allowed",
      );
    },
  );
});

test("native access rejects disabled, non-canary and non-controlled requests", () => {
  withEnvironment(
    {
      ...productionCatalogCanaryScope,
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      WHATSAPP_PRODUCT_LIST_ENABLED: "true",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "live",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_SENDER_NUMBER_ID: "9876543210",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "merchant_a",
      WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "false",
      WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES: controlledRecipientHash,
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: controlledRecipientHashKey,
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      const config = whatsappProductListRuntimeConfig();
      assert.equal(
        whatsappNativeCatalogAccessReason(
          { ...config, enabled: false },
          "merchant_a",
          controlledRecipient,
        ),
        "feature_disabled",
      );
      assert.equal(
        whatsappNativeCatalogAccessReason(
          config,
          "merchant_b",
          controlledRecipient,
        ),
        "merchant_not_allowed",
      );
      assert.equal(
        whatsappNativeCatalogAccessReason(config, "merchant_a", "+27820000000"),
        "recipient_not_allowed",
      );
      assert.equal(
        whatsappNativeCatalogAccessReason(
          config,
          "merchant_a",
          controlledRecipient,
        ),
        undefined,
      );
    },
  );
});

test("controlled recipients use keyed, normalized one-way digests", () => {
  assert.equal(
    controlledWhatsAppRecipientDigest(
      "082 123 4567",
      controlledRecipientHashKey,
    ),
    controlledRecipientHash,
  );
  assert.notEqual(
    controlledWhatsAppRecipientDigest(
      controlledRecipient,
      `${controlledRecipientHashKey}-rotated`,
    ),
    controlledRecipientHash,
  );
  assert.equal(controlledRecipientHash.includes("27821234567"), false);
  const deliveryFingerprint = productListDeliveryFingerprint({
    merchantId: "merchant_a",
    recipientHash: controlledRecipientHash,
    senderPhoneNumberId: "9876543210",
    catalogId: "1234567890",
    page: 0,
    productRetailerIds: [`spz_${"a".repeat(32)}`],
  });
  assert.match(deliveryFingerprint, /^[a-f0-9]{64}$/);
  assert.throws(
    () =>
      productListDeliveryFingerprint({
        merchantId: "merchant_a",
        recipientHash: controlledRecipient,
        senderPhoneNumberId: "9876543210",
        catalogId: "1234567890",
        page: 0,
        productRetailerIds: [`spz_${"a".repeat(32)}`],
      }),
    /WHATSAPP_RECIPIENT_HASH_INVALID/,
  );
});

test("enabled native delivery refuses missing or weak recipient policy", () => {
  const base = {
    ...productionCatalogCanaryScope,
    SPAZAONE_ENVIRONMENT: "production",
    SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
    WHATSAPP_PRODUCT_LIST_ENABLED: "true",
    META_WHATSAPP_MESSAGE_PROVIDER_MODE: "live",
    WHATSAPP_CATALOG_ID: "1234567890",
    WHATSAPP_SENDER_NUMBER_ID: "9876543210",
    WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "merchant_a",
    WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "false",
    GCLOUD_PROJECT: undefined,
    GOOGLE_CLOUD_PROJECT: undefined,
  };
  withEnvironment(
    {
      ...base,
      WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES: "",
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: controlledRecipientHashKey,
    },
    () => {
      assert.throws(
        whatsappProductListRuntimeConfig,
        /WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_REQUIRED/,
      );
    },
  );
  withEnvironment(
    {
      ...base,
      WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES: controlledRecipientHash,
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: "too-short",
    },
    () => {
      assert.throws(
        whatsappProductListRuntimeConfig,
        /WHATSAPP_CATALOG_RECIPIENT_HASH_KEY_INVALID/,
      );
    },
  );
});

test("enabled native delivery refuses a disabled catalogue-sync scope", () => {
  withEnvironment(
    {
      ...productionCatalogFullScope,
      SPAZAONE_ENVIRONMENT: "production",
      SPAZAONE_FIREBASE_PROJECT_ID: "pasella-ledger",
      WHATSAPP_CATALOG_SYNC_ENABLED: "false",
      WHATSAPP_PRODUCT_LIST_ENABLED: "true",
      META_WHATSAPP_MESSAGE_PROVIDER_MODE: "live",
      WHATSAPP_CATALOG_ID: "1234567890",
      WHATSAPP_SENDER_NUMBER_ID: "9876543210",
      WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS: "",
      WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED: "true",
      WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES: controlledRecipientHash,
      WHATSAPP_CATALOG_RECIPIENT_HASH_KEY: controlledRecipientHashKey,
      GCLOUD_PROJECT: undefined,
      GOOGLE_CLOUD_PROJECT: undefined,
    },
    () => {
      assert.throws(
        whatsappProductListRuntimeConfig,
        /WHATSAPP_CATALOG_SYNC_REQUIRED/,
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
  assert.match(deliverySource, /priceMinor: input\.projection\.priceMinor/);
  assert.match(
    deliverySource,
    /resolvedMerchantWhatsAppCatalogProductResponse\(\{/,
  );
  assert.ok(
    (deliverySource.match(/whatsappNativeCatalogAccessReason/g) ?? []).length >=
      3,
  );
  assert.ok(
    (deliverySource.match(/req\.body\?\.recipientPhone/g) ?? []).length >= 2,
  );
  assert.ok(
    (deliverySource.match(/req\.body\?\.senderPhoneNumberId/g) ?? []).length >=
      2,
  );
  assert.doesNotMatch(deliverySource, /req\.body\?\.productRetailerIds/);
  assert.equal(deliverySource.includes("supplierCatalogProducts"), false);
});

test("every development catalogue entrypoint enforces the merchant canary", () => {
  const queueSource = readFileSync(join(sourceRoot, "catalogQueue.ts"), "utf8");
  const statusSource = readFileSync(
    join(sourceRoot, "catalogStatus.ts"),
    "utf8",
  );
  assert.match(
    queueSource,
    /whatsappCatalogMerchantAllowed\(config, merchantId\)/,
  );
  assert.match(
    statusSource,
    /whatsappCatalogMerchantAllowed\(config, merchantId\)/,
  );
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

test("native send and detail fail closed for missing or paused merchants", () => {
  assert.equal(
    merchantAvailableForNativeCatalog({ exists: false, isPaused: false }),
    false,
  );
  assert.equal(
    merchantAvailableForNativeCatalog({ exists: true, isPaused: true }),
    false,
  );
  assert.equal(
    merchantAvailableForNativeCatalog({ exists: true, isPaused: false }),
    true,
  );
  const deliverySource = readFileSync(
    join(sourceRoot, "nativeProductListDelivery.ts"),
    "utf8",
  );
  assert.ok(
    (deliverySource.match(/merchantAvailableForNativeCatalog/g) ?? []).length >=
      3,
  );
  assert.match(deliverySource, /reason: "merchant_unavailable"/);
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

test("catalog resolution serializes exact owned and supplier wire contracts", () => {
  const decision = buildMerchantCatalogDecision({
    merchantId: "merchant_a",
    productId: "product_1",
    product,
  });
  assert.equal(decision.action, "upsert");
  assert.ok(decision.projection);
  const base = {
    productId: "product_1",
    retailerId: decision.retailerId,
    projection: decision.projection,
  };

  assert.deepEqual(
    resolvedMerchantWhatsAppCatalogProductResponse({
      ...base,
      supplier: { isDropshipListing: false },
    }),
    {
      outcome: "found",
      product: {
        id: "product_1",
        retailerId: decision.retailerId,
        name: "Maize Meal 5 kg",
        description: "Merchant product",
        imageUrl: "https://images.example.test/maize.jpg",
        price: 122.54,
        priceMinor: 12_254,
        currency: "ZAR",
        availability: "in stock",
        isDropshipListing: false,
      },
    },
  );

  assert.deepEqual(
    resolvedMerchantWhatsAppCatalogProductResponse({
      ...base,
      supplier: {
        isDropshipListing: true,
        commerceListingId: "listing_1",
      },
    }),
    {
      outcome: "found",
      product: {
        id: "product_1",
        retailerId: decision.retailerId,
        name: "Maize Meal 5 kg",
        description: "Merchant product",
        imageUrl: "https://images.example.test/maize.jpg",
        price: 122.54,
        priceMinor: 12_254,
        currency: "ZAR",
        availability: "in stock",
        isDropshipListing: true,
        commerceListingId: "listing_1",
      },
    },
  );
});

test("supplier metadata requires an exact server-owned merchant binding", () => {
  assert.equal(
    nativeCatalogProductAllowedByMerchantFeature(product, false),
    true,
  );
  assert.equal(
    nativeCatalogProductAllowedByMerchantFeature(
      { ...product, isDropshipListing: true },
      false,
    ),
    false,
  );
  assert.equal(
    nativeCatalogProductAllowedByMerchantFeature(
      { ...product, isDropshipListing: true },
      true,
    ),
    true,
  );
  assert.deepEqual(nativeCatalogProductKind(product), { kind: "owned" });
  assert.deepEqual(
    nativeCatalogProductKind({
      ...product,
      isDropshipListing: true,
      commerceListingId: "listing_1",
    }),
    { kind: "supplier", commerceListingId: "listing_1" },
  );
  assert.deepEqual(
    nativeCatalogProductKind({
      ...product,
      isDropshipListing: true,
      commerceListingId: "../foreign",
    }),
    { kind: "invalid_supplier" },
  );

  const binding = {
    exists: true,
    requestedMerchantId: "merchant_a",
    requestedProductId: "product_1",
    expectedPriceMinor: 12_254,
    listing: {
      active: true,
      supplierId: "cj_dropshipping",
      sellerId: "merchant_a",
      sellerProductId: "product_1",
      sellPriceMinor: 12_254,
      supplierProductCostMinor: 4_200,
    },
  };
  assert.equal(nativeCatalogSupplierListingMatches(binding), true);
  assert.equal(
    nativeCatalogSupplierListingMatches({
      ...binding,
      listing: { ...binding.listing, sellerId: "merchant_b" },
    }),
    false,
  );
  assert.equal(
    nativeCatalogSupplierListingMatches({
      ...binding,
      listing: { ...binding.listing, sellerProductId: "foreign_product" },
    }),
    false,
  );
  assert.equal(
    nativeCatalogSupplierListingMatches({
      ...binding,
      listing: { ...binding.listing, sellPriceMinor: 12_255 },
    }),
    false,
  );
});

test("merchant completeness requires every eligible revision to be Meta-accepted", () => {
  const merchantId = "merchant_a";
  const merchant = {
    whatsappOrdering: { orderingUrl: "https://shop.example.test/merchant-a" },
  };
  const products = [
    { id: "product_1", data: product },
    {
      id: "product_2",
      data: { ...product, name: "Rice 2 kg", sellingPrice: 77.5 },
    },
  ];
  const decisions = products.map(({ id, data }) =>
    buildMerchantCatalogDecision({
      merchantId,
      productId: id,
      product: data,
      merchant,
    }),
  );
  const mappings = decisions.map((decision, index) => ({
    merchantId,
    productId: products[index].id,
    retailerId: decision.retailerId,
    status: "active",
    metaPolicyStatus: "accepted",
    lastAppliedRevision: decision.revision,
  }));

  const complete = summarizeMerchantWhatsAppCatalogCompleteness({
    merchantId,
    merchant,
    products,
    mappings,
  });
  assert.equal(complete.merchantId, merchantId);
  assert.equal(complete.eligibleProducts, 2);
  assert.equal(complete.activeAcceptedProducts, 2);
  assert.equal(complete.missingProducts, 0);
  assert.equal(complete.staleProducts, 0);
  assert.equal(complete.unexpectedActiveMappings, 0);
  assert.equal(complete.pendingOutboxJobs, 0);
  assert.match(complete.eligibleSetDigest, /^[a-f0-9]{64}$/);
  assert.equal(complete.activeAcceptedSetDigest, complete.eligibleSetDigest);
  assert.equal(complete.complete, true);

  const stale = summarizeMerchantWhatsAppCatalogCompleteness({
    merchantId,
    merchant,
    products,
    mappings: [
      mappings[0],
      { ...mappings[1], lastAppliedRevision: "f".repeat(64) },
      {
        ...mappings[0],
        productId: "foreign_product",
        retailerId: `spz_${"e".repeat(32)}`,
      },
    ],
  });
  assert.equal(stale.complete, false);
  assert.equal(stale.activeAcceptedProducts, 1);
  assert.equal(stale.missingProducts, 1);
  assert.equal(stale.staleProducts, 1);
  assert.equal(stale.unexpectedActiveMappings, 1);

  for (const status of ["pending_delete", "rejected", "failed"]) {
    const unsafeDelete = summarizeMerchantWhatsAppCatalogCompleteness({
      merchantId,
      merchant,
      products: [],
      mappings: [
        {
          ...mappings[0],
          status,
          metaPolicyStatus: "accepted",
        },
      ],
    });
    assert.equal(unsafeDelete.complete, false, status);
    assert.equal(unsafeDelete.unexpectedActiveMappings, 1, status);
  }

  for (const status of ["pending", "processing", "submitted", "retry"]) {
    const pendingOutbox = summarizeMerchantWhatsAppCatalogCompleteness({
      merchantId,
      merchant,
      products,
      mappings,
      outboxStatuses: [status],
    });
    assert.equal(pendingOutbox.complete, false, status);
    assert.equal(pendingOutbox.pendingOutboxJobs, 1, status);
  }
});

test("native cart request accepts one or ten unique items and rejects bad batches", () => {
  const one = catalogCartFixture(1);
  const request = {
    merchantId: one.merchantId,
    customerId: "customer_1",
    recipientPhone: "082 123 4567",
    senderPhoneNumberId: "9876543210",
    catalogId: "1234567890",
    idempotencyKey: "native-cart:conversation-1",
    items: one.requests,
  };
  assert.equal(parseWhatsAppCatalogCartRequest(request)?.items.length, 1);
  assert.equal(
    parseWhatsAppCatalogCartRequest({
      ...request,
      senderPhoneNumberId: undefined,
    }),
    undefined,
  );

  const ten = catalogCartFixture(WHATSAPP_CATALOG_CART_MAX_ITEMS);
  assert.equal(
    parseWhatsAppCatalogCartRequest({ ...request, items: ten.requests })?.items
      .length,
    10,
  );
  assert.equal(
    parseWhatsAppCatalogCartRequest({ ...request, items: [] }),
    undefined,
  );
  assert.equal(
    parseWhatsAppCatalogCartRequest({
      ...request,
      items: [...ten.requests, one.requests[0]],
    }),
    undefined,
  );
  assert.equal(
    parseWhatsAppCatalogCartRequest({
      ...request,
      items: [one.requests[0], one.requests[0]],
    }),
    undefined,
  );
});

test("native cart binds its controlled recipient to the merchant customer", () => {
  assert.equal(
    customerMatchesWhatsAppRecipient({
      customerExists: true,
      customerNumber: "082 123 4567",
      recipient: controlledRecipient,
    }),
    true,
  );
  assert.equal(
    customerMatchesWhatsAppRecipient({
      customerExists: true,
      customerNumber: "082 000 0000",
      recipient: controlledRecipient,
    }),
    false,
  );
  assert.equal(
    customerMatchesWhatsAppRecipient({
      customerExists: false,
      customerNumber: controlledRecipient,
      recipient: controlledRecipient,
    }),
    false,
  );
});

test("native cart plans complete one- and ten-line replacements", () => {
  const one = planCatalogCart(catalogCartFixture(1));
  assert.equal(one.lineCount, 1);
  assert.equal(one.itemsCount, 1);
  assert.equal(one.totalMinor, 1_000);
  assert.equal(one.total, 10);
  assert.match(one.items[0].catalogRevision, /^[a-f0-9]{64}$/);

  const ten = planCatalogCart(catalogCartFixture(10));
  assert.equal(ten.lineCount, 10);
  assert.equal(new Set(ten.items.map((item) => item.productId)).size, 10);
  assert.equal(new Set(ten.items.map((item) => item.retailerId)).size, 10);
  assert.equal(
    ten.totalMinor,
    ten.items.reduce(
      (total, item) => total + item.quantity * item.priceMinor,
      0,
    ),
  );
});

test("native cart fingerprint is stable by content and tenant-bound", () => {
  const fixture = storedNativeCartFixture(10);
  assert.equal(
    nativeCatalogCartFingerprint({
      merchantId: fixture.merchantId,
      customerId: fixture.customerId,
      catalogId: fixture.catalogId,
      items: [...fixture.plan.items].reverse(),
    }),
    fixture.fingerprint,
  );
  assert.notEqual(
    nativeCatalogCartFingerprint({
      merchantId: fixture.merchantId,
      customerId: "customer_2",
      catalogId: fixture.catalogId,
      items: fixture.plan.items,
    }),
    fixture.fingerprint,
  );
  assert.match(
    nativeCatalogCartStateDocumentId({
      merchantId: fixture.merchantId,
      customerId: fixture.customerId,
    }),
    /^[a-f0-9]{64}$/,
  );
});

test("stored native cart revalidates one and ten lines at canonical minor prices", () => {
  const one = storedNativeCartFixture(1);
  one.products[0] = { ...one.products[0], sellingPrice: 999.99 };
  const oneResult = planStoredCart(one);
  assert.equal(oneResult.plan.totalMinor, 1_000);
  assert.equal(oneResult.plan.total, 10);

  const ten = storedNativeCartFixture(10);
  const tenResult = planStoredCart(ten);
  assert.equal(tenResult.plan.lineCount, 10);
  assert.equal(tenResult.fingerprint, ten.fingerprint);
});

test("stored native cart rejects altered content and server-state rollback", () => {
  for (const mutate of [
    (fixture) => {
      fixture.lines[9].quantity += 1;
    },
    (fixture) => {
      fixture.lines[9].catalogPriceMinor += 1;
    },
    (fixture) => {
      fixture.lines[9].catalogRevision = "f".repeat(64);
    },
    (fixture) => {
      fixture.summary.nativeCartFingerprint = "e".repeat(64);
    },
    (fixture) => {
      fixture.state.fingerprint = "d".repeat(64);
    },
  ]) {
    const fixture = storedNativeCartFixture(10);
    mutate(fixture);
    assert.throws(
      () => planStoredCart(fixture),
      (error) => error instanceof WhatsAppCatalogCartValidationError,
    );
  }
});

test("native cart rejects a late cross-merchant item before planning", () => {
  const fixture = catalogCartFixture(10);
  fixture.mappings[9] = {
    ...fixture.mappings[9],
    merchantId: "merchant_b",
  };
  assert.throws(
    () =>
      validateCatalogCartMappings({
        merchantId: fixture.merchantId,
        items: fixture.requests,
        mappings: fixture.mappings,
      }),
    (error) => {
      assert.ok(error instanceof WhatsAppCatalogCartValidationError);
      assert.equal(error.reason, "merchant_mismatch");
      assert.equal(error.failedItemIndex, 9);
      return true;
    },
  );
});

test("native cart distinguishes stale mapping, price and quantity failures", () => {
  const stale = catalogCartFixture(1);
  stale.resolved[0] = {
    ...stale.resolved[0],
    lastAppliedRevision: "f".repeat(64),
  };
  assert.throws(
    () => planCatalogCart(stale),
    (error) => {
      assert.equal(error.reason, "stale_mapping");
      return true;
    },
  );

  const repriced = catalogCartFixture(1);
  repriced.products[0] = { ...repriced.products[0], sellPriceMinor: 1_001 };
  assert.throws(
    () => planCatalogCart(repriced),
    (error) => {
      assert.equal(error.reason, "price_changed");
      return true;
    },
  );

  const unavailable = catalogCartFixture(1);
  unavailable.products[0] = {
    ...unavailable.products[0],
    whatsappListed: false,
  };
  assert.throws(
    () => planCatalogCart(unavailable),
    (error) => {
      assert.equal(error.reason, "product_unavailable");
      return true;
    },
  );

  const insufficient = catalogCartFixture(1);
  insufficient.resolved[0] = { ...insufficient.resolved[0], quantity: 51 };
  assert.throws(
    () => planCatalogCart(insufficient),
    (error) => {
      assert.equal(error.reason, "quantity_unavailable");
      return true;
    },
  );
});

test("native cart idempotency returns exact duplicates and rejects key reuse", () => {
  const cart = { currency: "ZAR", total: 10, items: [] };
  assert.deepEqual(
    decideCatalogCartIdempotency({
      exists: false,
      fingerprint: "a".repeat(64),
    }),
    { action: "apply" },
  );
  assert.deepEqual(
    decideCatalogCartIdempotency({
      exists: true,
      existingFingerprint: "a".repeat(64),
      existingCart: cart,
      fingerprint: "a".repeat(64),
    }),
    { action: "duplicate", cart },
  );
  assert.deepEqual(
    decideCatalogCartIdempotency({
      exists: true,
      existingFingerprint: "b".repeat(64),
      existingCart: cart,
      fingerprint: "a".repeat(64),
    }),
    { action: "idempotency_conflict" },
  );
});

test("late cart validation failure cannot stage any Firestore write", () => {
  const fixture = catalogCartFixture(10);
  const original = structuredClone(fixture);
  fixture.products[9] = {
    ...fixture.products[9],
    sellPriceMinor: fixture.requests[9].expectedPriceMinor + 1,
  };
  assert.throws(() => planCatalogCart(fixture), /price_changed/);
  assert.deepEqual(fixture.requests, original.requests);
  assert.deepEqual(fixture.resolved, original.resolved);

  const source = readFileSync(
    join(sourceRoot, "..", "ecommerce", "replaceWhatsAppCatalogCart.ts"),
    "utf8",
  );
  const transactionStart = source.indexOf("db.runTransaction");
  const allItemPreflight = source.indexOf(
    "const plan = planWhatsAppCatalogCartReplacement",
    transactionStart,
  );
  const beforePreflight = source.slice(transactionStart, allItemPreflight);
  assert.doesNotMatch(beforePreflight, /tx\.(?:set|create|update|delete)\(/);
  assert.ok(
    source.indexOf("existingCartItems.docs.forEach", allItemPreflight) >
      allItemPreflight,
  );
});

test("native cart endpoint is authenticated, atomic and rollout-gated", () => {
  const source = readFileSync(
    join(sourceRoot, "..", "ecommerce", "replaceWhatsAppCatalogCart.ts"),
    "utf8",
  );
  assert.match(source, /replaceWhatsAppCatalogCartBotHttp/);
  assert.match(source, /requireBotRequest/);
  assert.match(source, /whatsappNativeCatalogAccessReason/);
  assert.match(source, /customerMatchesWhatsAppRecipient/);
  assert.match(source, /customer_recipient_mismatch/);
  assert.match(
    source,
    /request\.senderPhoneNumberId !== config\.phoneNumberId/,
  );
  assert.match(source, /WHATSAPP_CATALOG_CART_STATES/);
  assert.match(source, /nativeCartFingerprint/);
  assert.match(source, /validateCatalogCartMappings/);
  assert.match(source, /planWhatsAppCatalogCartReplacement/);
  assert.match(source, /db\.runTransaction/);
  assert.match(source, /whatsappCatalogCartReplacements/);
  assert.doesNotMatch(source, /addWhatsAppCatalogProductToCartBotHttp/);
  for (const code of [
    "INVALID_REQUEST",
    "CONFIGURATION_BLOCKED",
    "CATALOG_MISMATCH",
    "CART_WRITE_FAILED",
  ]) {
    assert.match(source, new RegExp(`code: "${code}"`));
  }
  assert.match(source, /code: error\.reason\.toUpperCase\(\)/);
  const authSource = readFileSync(
    join(sourceRoot, "..", "security", "requestAuth.ts"),
    "utf8",
  );
  assert.match(authSource, /code: "AUTHENTICATION_REQUIRED"/);
});

test("native checkout revalidates state and creates the sale in one transaction", () => {
  const checkoutSource = readFileSync(
    join(sourceRoot, "..", "ecommerce", "checkoutCart.ts"),
    "utf8",
  );
  assert.match(checkoutSource, /claimedNativeCartFingerprint/);
  assert.match(checkoutSource, /planStoredNativeCatalogCart/);
  assert.match(checkoutSource, /tx\.get\(stateRef\)/);
  assert.match(checkoutSource, /tx\.create\(saleRef, saleData\)/);
  assert.match(checkoutSource, /nativeCartPlan\?\.fingerprint/);
  assert.match(checkoutSource, /NATIVE_CATALOG_CART_CHANGED/);
  assert.match(checkoutSource, /cartSource: "whatsapp_native_catalog"/);
});

test("native Paystack reservation keeps canonical minor-unit pricing", () => {
  const reservationSource = readFileSync(
    join(sourceRoot, "..", "payments", "v2", "inventoryReservations.ts"),
    "utf8",
  );
  assert.match(reservationSource, /merchantProductSellPriceMinor/);
  assert.match(reservationSource, /saleItem\?\.priceMinor/);
  assert.match(reservationSource, /saleData\.subtotalMinor/);
  const checkoutSource = readFileSync(
    join(sourceRoot, "..", "ecommerce", "checkoutCart.ts"),
    "utf8",
  );
  assert.match(
    checkoutSource,
    /cancelFailedNativeInventoryReservationAtomically\(\{/,
  );
});

test("delivery monitor binds the controlled-recipient HMAC secret", () => {
  const statusSource = readFileSync(
    join(sourceRoot, "nativeProductListStatus.ts"),
    "utf8",
  );
  assert.match(
    statusSource,
    /monitorWhatsAppProductListDeliveries[\s\S]*secrets:\s*\["WHATSAPP_CATALOG_RECIPIENT_HASH_KEY"\]/,
  );
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
    "whatsappCatalogCartReplacements",
    "whatsappCatalogCartStates",
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
