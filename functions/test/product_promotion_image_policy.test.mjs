import assert from "node:assert/strict";
import test from "node:test";
import {
  isAuthorizedSupplierPromotionImage,
  productPromotionImageSource,
} from "../lib/merchant_hub/productPromotionImage.js";

const merchantId = "merchant-1";
const productId = "product-1";
const commerceListingId = "listing-1";
const imageUrl =
  "https://oss-cf.cjdropshipping.com/product/2026/08/image.jpg?width=800";

function validPolicyInput() {
  return {
    merchantId,
    productId,
    listingId: commerceListingId,
    imageUrl,
    product: {
      isDropshipListing: true,
      commerceListingId,
    },
    listing: {
      sellerId: merchantId,
      sellerProductId: productId,
      images: [imageUrl],
    },
  };
}

test("keeps the existing Firebase Storage image hosts", () => {
  assert.equal(
    productPromotionImageSource(
      "https://firebasestorage.googleapis.com/v0/b/app/o/product.jpg?alt=media",
    ),
    "firebase_storage",
  );
  assert.equal(
    productPromotionImageSource(
      "https://storage.googleapis.com/spaza-one/product.jpg",
    ),
    "firebase_storage",
  );
});

test("allows only the exact HTTPS CJ supplier hosts", () => {
  for (const allowedUrl of [
    imageUrl,
    "https://cf.cjdropshipping.com/product/image.png",
    "https://cdn.cjdropshipping.com/product/image.jpg",
    "https://cc-west-usa.oss-us-west-1.aliyuncs.com/product/image.png",
  ]) {
    assert.equal(productPromotionImageSource(allowedUrl), "verified_supplier");
  }

  for (const rejectedUrl of [
    "http://oss-cf.cjdropshipping.com/product/image.jpg",
    "https://images.oss-cf.cjdropshipping.com/product/image.jpg",
    "https://oss-cf.cjdropshipping.com.example.com/product/image.jpg",
    "https://cc-west-usa.oss-us-west-1.aliyuncs.com.example.com/image.png",
    "https://cjdropshipping.com/product/image.jpg",
    "https://example.com/product/image.jpg",
    "not-a-url",
  ]) {
    assert.equal(productPromotionImageSource(rejectedUrl), "rejected");
  }
});

test("authorizes a supplier image only through its bound commerce listing", () => {
  assert.equal(isAuthorizedSupplierPromotionImage(validPolicyInput()), true);
});

test("rejects seller-controlled or mismatched supplier image claims", () => {
  const valid = validPolicyInput();
  const invalidInputs = [
    { ...valid, product: { ...valid.product, isDropshipListing: false } },
    { ...valid, product: { ...valid.product, commerceListingId: "../unsafe" } },
    { ...valid, listingId: "another-listing" },
    { ...valid, listing: undefined },
    { ...valid, listing: { ...valid.listing, sellerId: "another-merchant" } },
    {
      ...valid,
      listing: { ...valid.listing, sellerProductId: "another-product" },
    },
    { ...valid, listing: { ...valid.listing, images: [] } },
    {
      ...valid,
      listing: {
        ...valid.listing,
        images: [`${imageUrl}&different=true`],
      },
    },
  ];

  for (const input of invalidInputs) {
    assert.equal(isAuthorizedSupplierPromotionImage(input), false);
  }
});
