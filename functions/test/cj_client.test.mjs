import assert from "node:assert/strict";
import test from "node:test";
import {
  catalogProductWithZaDelivery,
  convertUsdMinorToZarMinor,
  createRequestScheduler,
  normalizeCjAccessToken,
  normalizeCjProductDetails,
  normalizeCjSearchResponse,
  normalizeUsdZarRate,
  prioritizedCjVariants,
  usdMinor,
} from "../lib/commerce/cjClient.js";

const fx = {
  rate: 18,
  rateMicros: 18_000_000,
  date: "2026-08-03",
  bufferBps: 300,
};

test("CJ access tokens preserve the current JWT-sized value", () => {
  const token = "x".repeat(566);
  assert.equal(normalizeCjAccessToken(token), token);
});

test("supplier requests are serialized and continue after a failed request", async () => {
  const schedule = createRequestScheduler(20);
  const starts = [];
  const first = schedule(async () => {
    starts.push(Date.now());
    throw new Error("expected failure");
  });
  const second = schedule(async () => {
    starts.push(Date.now());
    return "second";
  });
  const third = schedule(async () => {
    starts.push(Date.now());
    return "third";
  });

  await assert.rejects(first, /expected failure/);
  assert.equal(await second, "second");
  assert.equal(await third, "third");
  assert.equal(starts.length, 3);
  assert.ok(starts[1] - starts[0] >= 15);
  assert.ok(starts[2] - starts[1] >= 15);
});

test("USD/ZAR rates accept both documented Frankfurter response shapes", () => {
  const today = new Date().toISOString().slice(0, 10);
  assert.deepEqual(
    normalizeUsdZarRate({ date: today, rates: { ZAR: 16.4408 } }),
    { date: today, rate: 16.4408 },
  );
  assert.deepEqual(normalizeUsdZarRate({ date: today, rate: 16.4408 }), {
    date: today,
    rate: 16.4408,
  });
  assert.throws(
    () => normalizeUsdZarRate({ date: "2020-01-01", rate: 16 }),
    /CJ_FX_STALE/,
  );
});

test("CJ USD conversion uses integer minor units and the configured reserve", () => {
  assert.equal(usdMinor("2.50-4.00"), 250);
  assert.equal(convertUsdMinorToZarMinor(100, 18, 300), 1854);
  assert.throws(
    () => convertUsdMinorToZarMinor(100, Number.NaN, 300),
    /CJ_CONVERSION_INVALID/,
  );
});

test("CJ catalog normalization keeps only server-recognized product fields", () => {
  const result = normalizeCjSearchResponse(
    {
      pageNumber: 2,
      totalPages: 8,
      content: [
        {
          productList: [
            {
              id: "cj-product-1",
              sku: "CJ-ONE",
              nameEn: "Rechargeable lamp",
              bigImage: "https://example.test/lamp.jpg",
              sellPrice: "2.50-4.00",
              threeCategoryName: "Home",
              clientPrice: 1,
            },
            {
              id: "cj-product-bad",
              nameEn: "Missing price",
              bigImage: "javascript:alert(1)",
            },
          ],
        },
      ],
    },
    fx,
  );
  assert.equal(result.page, 2);
  assert.equal(result.totalPages, 8);
  assert.equal(result.products.length, 1);
  assert.deepEqual(result.products[0], {
    productId: "cj-product-1",
    productSku: "CJ-ONE",
    title: "Rechargeable lamp",
    image: "https://example.test/lamp.jpg",
    category: "Home",
    productCostUsdMinor: 250,
    estimatedProductCostMinor: 4635,
  });
});

test("CJ product details sanitize descriptions, images and variant pricing", () => {
  const product = normalizeCjProductDetails(
    {
      pid: "cj-product-1",
      productSku: "CJ-ONE",
      productNameEn: "Rechargeable lamp",
      bigImage: "https://example.test/lamp.jpg",
      productImageSet: [
        "http://example.test/not-secure.jpg",
        "https://example.test/lamp-2.jpg",
      ],
      description: "<p>Bright &amp; portable</p><script>steal()</script>",
      status: "3",
      variants: [
        {
          vid: "variant-1",
          pid: "cj-product-1",
          variantSku: "CJ-ONE-BLK",
          variantKey: "Black",
          variantImage: "https://example.test/black.jpg",
          variantSellPrice: 3.25,
        },
      ],
    },
    fx,
  );
  assert.equal(product.description, "Bright & portable");
  assert.deepEqual(product.images, [
    "https://example.test/lamp.jpg",
    "https://example.test/lamp-2.jpg",
  ]);
  assert.equal(product.variants[0].productCostUsdMinor, 325);
  assert.equal(product.variants[0].estimatedProductCostMinor, 6026);
});

test("catalogue eligibility exposes only the verified ZA variant preview", () => {
  const product = {
    productId: "cj-product-1",
    productSku: "CJ-ONE",
    title: "Rechargeable lamp",
    image: "https://example.test/lamp.jpg",
    category: "Home",
    productCostUsdMinor: 250,
    estimatedProductCostMinor: 4635,
  };
  const details = {
    productId: product.productId,
    productSku: product.productSku,
    title: product.title,
    description: "",
    images: [product.image],
    category: product.category,
    status: "3",
    variants: [],
    fx,
  };
  const variant = {
    variantId: "variant-za",
    productId: product.productId,
    sku: "CJ-ONE-ZA",
    name: "Black",
    option: "Black",
    image: product.image,
    productCostUsdMinor: 250,
    estimatedProductCostMinor: 4635,
  };
  const eligible = catalogProductWithZaDelivery(product, {
    product: details,
    variant,
    originCountryCode: "CN",
    stock: 20,
    logisticName: "CJPacket",
    logisticAging: "12-20",
    productCostUsdMinor: 250,
    shippingCostUsdMinor: 500,
    productCostMinor: 4635,
    shippingCostMinor: 9270,
    landedCostMinor: 13905,
    currency: "ZAR",
    fx,
    verifiedAt: "2026-08-04T10:00:00.000Z",
  });

  assert.equal(eligible.deliverableVariantId, "variant-za");
  assert.equal(eligible.estimatedDeliveryCostMinor, 9270);
  assert.equal(eligible.estimatedLandedCostMinor, 13905);
  assert.throws(
    () =>
      catalogProductWithZaDelivery(product, {
        product: details,
        variant,
        originCountryCode: "CN",
        stock: 20,
        logisticName: "CJPacket",
        logisticAging: "12-20",
        productCostUsdMinor: 0,
        shippingCostUsdMinor: 0,
        productCostMinor: 0,
        shippingCostMinor: 0,
        landedCostMinor: 0,
        currency: "ZAR",
        fx,
        verifiedAt: "2026-08-04T10:00:00.000Z",
      }),
    /CJ_QUOTE_INVALID/,
  );
  assert.throws(
    () =>
      catalogProductWithZaDelivery(
        { ...product, productId: "different-product" },
        { ...eligible, product: details, variant },
      ),
    /CJ_PRODUCT_MISMATCH/,
  );
});

test("cached deliverable variant is retried before catalogue alternatives", () => {
  const product = normalizeCjProductDetails(
    {
      pid: "cj-product-1",
      productNameEn: "Rechargeable lamp",
      status: "3",
      variants: [
        {
          vid: "variant-1",
          pid: "cj-product-1",
          variantKey: "Black",
          variantSellPrice: 3,
        },
        {
          vid: "variant-2",
          pid: "cj-product-1",
          variantKey: "White",
          variantSellPrice: 4,
        },
        {
          vid: "variant-3",
          pid: "cj-product-1",
          variantKey: "Blue",
          variantSellPrice: 5,
        },
      ],
    },
    fx,
  );
  assert.deepEqual(
    prioritizedCjVariants(product, "variant-3", 2).map(
      (variant) => variant.variantId,
    ),
    ["variant-3", "variant-1"],
  );
});
