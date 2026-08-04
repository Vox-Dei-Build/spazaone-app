import assert from "node:assert/strict";
import test from "node:test";
import {
  convertUsdMinorToZarMinor,
  normalizeCjAccessToken,
  normalizeCjProductDetails,
  normalizeCjSearchResponse,
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
