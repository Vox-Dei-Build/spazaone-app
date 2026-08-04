import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { createRequire } from "node:module";
import { after, before, test } from "node:test";
import admin from "firebase-admin";
import {
  createCommerceOrder,
  verifyCommercePaystackTransaction,
} from "../lib/commerce/payment.js";
import { commerceCheckout } from "../lib/commerce/checkoutPage.js";

const requireModule = createRequire(import.meta.url);
const axios = requireModule("axios");
const db = admin.firestore();
const secret = "emulator-commerce-paystack-secret";
const botSecret = "emulator-commerce-bot-secret";
const originalAxiosAdapter = axios.defaults.adapter;

async function clear() {
  for (const collectionName of [
    "commerceOrders",
    "commerceListings",
    "commerceCheckoutAttempts",
    "payments",
    "users",
  ]) {
    await admin.firestore().recursiveDelete(db.collection(collectionName));
  }
}

function verified(reference, amount = 14_000) {
  return {
    status: "success",
    reference,
    currency: "ZAR",
    amount,
    fees: 582,
    channel: "card",
    paid_at: "2026-08-03T10:00:00.000Z",
    metadata: {
      purpose: "commerce_order",
      orderId: "order-1",
      sellerId: "seller-1",
      listingId: "listing-1",
    },
  };
}

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
    headers: {},
    set(name, value) {
      this.headers[name] = value;
      return this;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
    send(body) {
      this.body = body;
      return this;
    },
  };
}

async function sendVerifiedWebhook(reference, amount = 14_000) {
  const body = { event: "charge.success", data: { reference } };
  const rawBody = Buffer.from(JSON.stringify(body));
  axios.defaults.adapter = async (config) => ({
    data: { status: true, data: verified(reference, amount) },
    status: 200,
    statusText: "OK",
    headers: {},
    config,
  });
  const request = {
    method: "POST",
    body,
    rawBody,
    get(name) {
      return name.toLowerCase() === "x-paystack-signature"
        ? createHmac("sha512", secret).update(rawBody).digest("hex")
        : undefined;
    },
  };
  const response = responseRecorder();
  await verifyCommercePaystackTransaction(request, response);
  return response;
}

before(async () => {
  process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  process.env.PAYSTACK_SECRET_KEY = secret;
  process.env.CJ_API_KEY = "emulator-cj-api-key";
  process.env.PASELLA_BOT_TOKEN = botSecret;
  await clear();
  await db.doc("commerceOrders/order-1").set({
    sellerId: "seller-1",
    listingId: "listing-1",
    buyer: { name: "Buyer", phone: "0820000000" },
    status: "pending_payment",
    paymentStatus: "pending",
    fulfilmentStatus: "pending",
    amountDueMinor: 14_000,
    marginMinor: 3_418,
    statusHistory: [],
  });
});

after(async () => {
  axios.defaults.adapter = originalAxiosAdapter;
  delete process.env.PAYSTACK_SECRET_KEY;
  delete process.env.CJ_API_KEY;
  delete process.env.PASELLA_BOT_TOKEN;
  delete process.env.COMMERCE_PAYMENTS_ENABLED;
  await clear();
});

test("WhatsApp bot creates an isolated manual order without a payment provider", async () => {
  await db.doc("commerceListings/listing-manual").set({
    sellerId: "seller-1",
    sellerProductId: "seller-product-manual",
    supplierId: "manual-supplier",
    supplierProductId: "supplier-product-manual",
    baseCostMinor: 10_000,
    sellPriceMinor: 14_000,
    title: "Manual dropship product",
    images: [],
    active: true,
    fulfilmentMode: "manual_supplier_order",
  });
  const orderCountBefore = (await db.collection("commerceOrders").get()).size;
  let providerCalled = false;
  axios.defaults.adapter = async () => {
    providerCalled = true;
    throw new Error("Provider must not be called for a manual order");
  };
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  const response = responseRecorder();
  const duplicateResponse = responseRecorder();
  const request = {
    method: "POST",
    body: {
      listingId: "listing-manual",
      merchantId: "seller-1",
      customerId: "customer-1",
      orderChannel: "whatsapp",
      paymentPreference: "transfer",
      checkoutAttemptId: "attempt-manual",
      buyer: {
        name: "Manual Buyer",
        phone: "0820000000",
      },
      deliveryAddress: {
        line1: "1 Private Road",
        suburb: "Woodstock",
        city: "Cape Town",
        province: "Western Cape",
        postalCode: "7925",
      },
    },
    get(name) {
      return name.toLowerCase() === "x-pasella-bot-token"
        ? botSecret
        : undefined;
    },
  };
  try {
    await createCommerceOrder(request, response);
    await createCommerceOrder(request, duplicateResponse);
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.paymentMethod, "manual");
  assert.match(response.body.confirmationUrl, /commerceCheckout/);
  assert.equal(duplicateResponse.statusCode, 200);
  assert.equal(duplicateResponse.body.reused, true);
  assert.equal(
    duplicateResponse.body.confirmationUrl,
    response.body.confirmationUrl,
  );
  assert.equal(providerCalled, false);
  assert.equal(
    (await db.collection("commerceOrders").get()).size,
    orderCountBefore + 1,
  );
  const orders = await db
    .collection("commerceOrders")
    .where("listingId", "==", "listing-manual")
    .get();
  assert.equal(orders.size, 1);
  assert.equal(
    orders.docs[0].get("paymentStatus"),
    "awaiting_manual_confirmation",
  );
  assert.equal(orders.docs[0].get("paymentMethod"), "manual");
  assert.equal(orders.docs[0].get("orderChannel"), "whatsapp");
  assert.equal(orders.docs[0].get("customerId"), "customer-1");
  assert.equal(orders.docs[0].get("buyerPaymentPreference"), "transfer");
  assert.equal(orders.docs[0].get("feeMinor"), 0);
  assert.equal(orders.docs[0].get("marginMinor"), 4_000);
  assert.equal(orders.docs[0].get("buyer.email"), "");
});

test("manual buyer ordering is not exposed as a public web form", async () => {
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  const response = responseRecorder();
  try {
    await commerceCheckout(
      { method: "GET", query: { listing: "listing-manual" } },
      response,
    );
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }

  assert.equal(response.statusCode, 503);
  assert.match(response.body, /Order through WhatsApp/i);
  assert.doesNotMatch(response.body, /<form/i);
  assert.doesNotMatch(response.body, /Paystack/i);
  assert.doesNotMatch(response.body, /pay securely/i);
});

test("CJ checkout ignores client pricing and snapshots the live landed quote", async () => {
  await db.doc("commerceListings/cj-listing").set({
    sellerId: "seller-1",
    sellerProductId: "seller-product-1",
    supplierId: "cj_dropshipping",
    supplierProductId: "cj-product-1",
    supplierVariantId: "cj-variant-1",
    markupMinor: 1_000,
    // Stale listing estimates must not be used for payment.
    baseCostMinor: 1,
    sellPriceMinor: 2,
    title: "CJ lamp · Black",
    images: ["https://example.test/lamp.jpg"],
    active: true,
    fulfilmentMode: "seller_manual_cj_order",
  });

  let paystackAmount = null;
  axios.defaults.adapter = async (config) => {
    const url = String(config.url ?? "");
    let data;
    if (url.includes("authentication/getAccessToken")) {
      data = {
        result: true,
        data: {
          accessToken: "cj-access-token",
          accessTokenExpiryDate: "2027-08-03T00:00:00Z",
        },
      };
    } else if (url.includes("frankfurter.dev")) {
      data = { date: "2026-08-03", base: "USD", quote: "ZAR", rate: 18 };
    } else if (url.endsWith("/product/query")) {
      data = {
        result: true,
        data: {
          pid: "cj-product-1",
          productSku: "CJ-LAMP",
          productNameEn: "CJ lamp",
          status: "3",
          variants: [
            {
              vid: "cj-variant-1",
              pid: "cj-product-1",
              variantSku: "CJ-LAMP-BLK",
              variantKey: "Black",
              variantSellPrice: 5,
            },
          ],
        },
      };
    } else if (url.endsWith("/product/variant/queryByVid")) {
      data = {
        result: true,
        data: {
          vid: "cj-variant-1",
          pid: "cj-product-1",
          variantSku: "CJ-LAMP-BLK",
          variantKey: "Black",
          variantSellPrice: 5,
          inventories: [{ countryCode: "CN", totalInventory: 10 }],
        },
      };
    } else if (url.endsWith("/logistic/freightCalculate")) {
      data = {
        result: true,
        data: [
          {
            logisticName: "CJPacket ZA",
            logisticAging: "8-14",
            logisticPrice: 2,
          },
        ],
      };
    } else if (url.includes("paystack.co/transaction/initialize")) {
      const body =
        typeof config.data === "string" ? JSON.parse(config.data) : config.data;
      paystackAmount = body.amount;
      data = {
        status: true,
        data: {
          authorization_url: "https://paystack.test/cj-checkout",
          reference: body.reference,
        },
      };
    } else {
      throw new Error(`Unexpected HTTP request: ${url}`);
    }
    return {
      data,
      status: 200,
      statusText: "OK",
      headers: {},
      config,
    };
  };

  const request = {
    method: "POST",
    body: {
      listingId: "cj-listing",
      checkoutAttemptId: "cj-attempt-1",
      amountDueMinor: 1,
      baseCostMinor: 1,
      marginMinor: 999_999,
      buyer: {
        name: "Buyer One",
        email: "buyer@example.test",
        phone: "0820000000",
      },
      deliveryAddress: {
        line1: "1 Main Road",
        line2: "",
        suburb: "Woodstock",
        city: "Cape Town",
        province: "Western Cape",
        postalCode: "7925",
        country: "ZA",
      },
    },
  };
  const response = responseRecorder();
  await createCommerceOrder(request, response);
  assert.equal(response.statusCode, 200);
  assert.equal(
    response.body.authorizationUrl,
    "https://paystack.test/cj-checkout",
  );
  assert.equal(paystackAmount, 13_978);

  const orders = await db
    .collection("commerceOrders")
    .where("listingId", "==", "cj-listing")
    .get();
  assert.equal(orders.size, 1);
  const order = orders.docs[0].data();
  assert.equal(order.baseCostMinor, 12_978);
  assert.equal(order.amountDueMinor, 13_978);
  assert.equal(order.supplierProductCostMinor, 9_270);
  assert.equal(order.supplierShippingCostMinor, 3_708);
  assert.equal(order.fxRateMicros, 18_000_000);
  assert.equal(order.logisticName, "CJPacket ZA");
  assert.equal(order.marginMinor, 419);
  assert.equal(
    (await db.doc("users/seller-1/sales/cj-listing").get()).exists,
    false,
  );
  assert.equal(
    (await db.doc("users/seller-1/wallet/current").get()).exists,
    false,
  );
});

test("duplicate verified callbacks transition and record payment once", async () => {
  const first = await sendVerifiedWebhook("commerce-ref-1");
  const duplicate = await sendVerifiedWebhook("commerce-ref-1");

  assert.equal(first.statusCode, 200);
  assert.equal(first.body.deduped, false);
  assert.equal(duplicate.statusCode, 200);
  assert.equal(duplicate.body.deduped, true);
  const order = await db.doc("commerceOrders/order-1").get();
  assert.equal(order.get("status"), "paid");
  assert.equal(order.get("paymentStatus"), "paid");
  assert.equal(order.get("payment.reference"), "commerce-ref-1");
  assert.equal(
    order.get("statusHistory").filter((item) => item.to === "paid").length,
    1,
  );
  assert.equal(
    (await db.doc("payments/paystackCommerce/processed/commerce-ref-1").get())
      .exists,
    true,
  );
  assert.equal(
    (await db.doc("users/seller-1/sales/order-1").get()).exists,
    false,
  );
  assert.equal(
    (await db.doc("users/seller-1/wallet/current").get()).exists,
    false,
  );
});

test("amount mismatch cannot mark another pending order paid", async () => {
  await db.doc("commerceOrders/order-1").set(
    {
      status: "pending_payment",
      paymentStatus: "pending",
      fulfilmentStatus: "pending",
      "payment.reference": admin.firestore.FieldValue.delete(),
      statusHistory: [],
    },
    { merge: true },
  );
  const response = await sendVerifiedWebhook("commerce-ref-bad", 1);
  assert.equal(response.statusCode, 400);
  assert.equal(
    (await db.doc("commerceOrders/order-1").get()).get("paymentStatus"),
    "pending",
  );
  assert.equal(
    (await db.doc("payments/paystackCommerce/processed/commerce-ref-bad").get())
      .exists,
    false,
  );
});
