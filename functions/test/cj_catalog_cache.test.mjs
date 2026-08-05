import assert from "node:assert/strict";
import test from "node:test";
import {
  buildCatalogCacheDocument,
  catalogDetailsPayload,
  catalogQueryWords,
  catalogSearchTokens,
  isUsableCatalogDocument,
} from "../lib/commerce/cjCatalogCache.js";

const fx = {
  rate: 18,
  rateMicros: 18_000_000,
  date: "2026-08-04",
  bufferBps: 300,
};

function fixture({
  productId = "cj-product-1",
  title = "Rechargeable bedside lamp",
  category = "Home lighting",
  variantId = "variant-black",
  checkedAtMs = 1_000,
  sourceQuery = "bedside lights",
} = {}) {
  const product = {
    productId,
    productSku: `${productId}-sku`,
    title,
    image: `https://example.test/${productId}.jpg`,
    category,
    productCostUsdMinor: 250,
    estimatedProductCostMinor: 4_635,
  };
  const otherVariant = {
    variantId: "variant-white",
    productId,
    sku: `${productId}-white`,
    name: "White",
    option: "White",
    image: "https://example.test/white.jpg",
    productCostUsdMinor: 275,
    estimatedProductCostMinor: 5_099,
  };
  const recommendedVariant = {
    variantId,
    productId,
    sku: `${productId}-black`,
    name: "Black",
    option: "Black",
    image: "https://example.test/black.jpg",
    productCostUsdMinor: 250,
    estimatedProductCostMinor: 4_635,
  };
  const details = {
    productId,
    productSku: product.productSku,
    title,
    description: "Portable warm light",
    images: [product.image],
    category,
    status: "3",
    // Deliberately put the selected variant second: the cache should promote it.
    variants: [otherVariant, recommendedVariant],
    fx,
  };
  const quote = {
    product: details,
    variant: recommendedVariant,
    originCountryCode: "CN",
    stock: 25,
    logisticName: "CJPacket",
    logisticAging: "12-20 days",
    productCostUsdMinor: 250,
    shippingCostUsdMinor: 500,
    productCostMinor: 4_635,
    shippingCostMinor: 9_270,
    landedCostMinor: 13_905,
    currency: "ZAR",
    fx,
    verifiedAt: "2026-08-04T10:00:00.000Z",
  };
  return {
    product,
    quote,
    document: buildCatalogCacheDocument(
      product,
      quote,
      checkedAtMs,
      sourceQuery,
    ),
  };
}

test("catalog cache snapshots the verified ZA quote and promotes its variant", () => {
  const { document } = fixture();

  assert.equal(document.active, true);
  assert.equal(document.destinationCountryCode, "ZA");
  assert.equal(document.deliverableVariantId, "variant-black");
  assert.equal(document.details.variants[0].variantId, "variant-black");
  assert.equal(document.recommendedQuote.variant.variantId, "variant-black");
  assert.equal(document.recommendedQuote.landedCostMinor, 13_905);
  assert.deepEqual(document.sourceQueries, ["bedside lights"]);
  assert.deepEqual(document.activeSearchTokens, document.searchTokens);
  assert.equal("product" in document.recommendedQuote, false);

  const payload = catalogDetailsPayload(document);
  assert.equal(payload.recommendedVariantId, "variant-black");
  assert.equal(payload.variants.length, 1);
  assert.equal(payload.variants[0].variantId, "variant-black");
  assert.equal(payload.recommendedQuote.landedCostMinor, 13_905);
  assert.equal(payload.catalogueSnapshot, true);
  assert.equal(isUsableCatalogDocument(document), true);
});

test("catalog cache rejects mismatched products and unusable prices", () => {
  const { product, quote } = fixture();
  assert.throws(
    () =>
      buildCatalogCacheDocument(
        { ...product, productId: "another-product" },
        quote,
        1_000,
      ),
    /CJ_QUOTE_INVALID/,
  );
  assert.throws(
    () =>
      buildCatalogCacheDocument(
        product,
        { ...quote, landedCostMinor: 0 },
        1_000,
      ),
    /CJ_QUOTE_INVALID/,
  );
  for (const invalidQuote of [
    { ...quote, stock: 0 },
    { ...quote, currency: "USD" },
    { ...quote, landedCostMinor: quote.landedCostMinor + 1 },
    {
      ...quote,
      variant: { ...quote.variant, productId: "another-product" },
    },
  ]) {
    assert.throws(
      () => buildCatalogCacheDocument(product, invalidQuote, 1_000),
      /CJ_QUOTE_INVALID/,
    );
  }
});

test("catalog refresh preserves a bounded set of source-query associations", () => {
  const { product, quote } = fixture();
  const document = buildCatalogCacheDocument(
    product,
    quote,
    2_000,
    "lighting",
    ["home", "bedside lights", "home"],
  );

  assert.deepEqual(document.sourceQueries, [
    "home",
    "bedside lights",
    "lighting",
  ]);
  assert.ok(document.activeSearchTokens.includes("lighting"));
});

test("catalog token normalization is case-insensitive and bounded", () => {
  assert.deepEqual(catalogQueryWords("  LAMPS, lamps & Décor "), [
    "lamps",
    "decor",
  ]);
  const tokens = catalogSearchTokens("Rechargeable");
  assert.ok(tokens.includes("re"));
  assert.ok(tokens.includes("rechargeable"));
  assert.ok(tokens.length <= 240);
});

test("core product fields stay searchable after many discovery synonyms", () => {
  const { product, quote } = fixture({
    title: "Rechargeable camping lantern",
    category: "Outdoor lighting",
  });
  const document = buildCatalogCacheDocument(
    product,
    quote,
    2_000,
    "portable travel equipment bundle",
    [
      "seasonal bestseller collection",
      "summer holiday accessories",
      "lightweight adventure equipment",
      "family camping essentials",
      "outdoor recreation supplies",
      "rechargeable emergency products",
      "weekend travel collection",
      "popular gift recommendations",
    ],
  );

  assert.ok(document.searchTokens.length <= 240);
  assert.ok(document.searchTokens.includes("lantern"));
  assert.ok(document.searchTokens.includes("outdoor"));
});
