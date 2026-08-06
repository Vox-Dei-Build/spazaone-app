import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { createRequire } from "node:module";
import { after, before, test } from "node:test";
import admin from "firebase-admin";
import {
  applyVerifiedCommercePayment,
  createCommerceOrder,
  verifyCommercePaystackTransaction,
} from "../lib/commerce/payment.js";
import { commerceCheckout } from "../lib/commerce/checkoutPage.js";

const emulatorHost = String(process.env.FIRESTORE_EMULATOR_HOST ?? "");
const emulatorProject = String(
  process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "",
);
if (!emulatorHost || !emulatorProject.startsWith("demo-")) {
  throw new Error(
    "Refusing commerce integration test without a demo Firestore emulator.",
  );
}

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

function verified(reference, amount = 14_000, metadataOverrides = {}) {
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
      ...metadataOverrides,
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

async function seedManualListing() {
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
}

function manualOrderRequest(overrides = {}) {
  return {
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
      ...overrides,
    },
    get(name) {
      return name.toLowerCase() === "x-pasella-bot-token"
        ? botSecret
        : undefined;
    },
  };
}

async function sendVerifiedWebhook(
  reference,
  amount = 14_000,
  metadataOverrides = {},
) {
  const body = { event: "charge.success", data: { reference } };
  const rawBody = Buffer.from(JSON.stringify(body));
  axios.defaults.adapter = async (config) => ({
    data: {
      status: true,
      data: verified(reference, amount, metadataOverrides),
    },
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
    paymentMethod: "paystack",
    payment: { provider: "paystack", reference: "commerce-ref-1" },
    amountDueMinor: 14_000,
    marginMinor: 3_418,
    statusHistory: [],
  });
  await db.doc("users/seller-1/customers/customer-1").set({
    name: "Manual Buyer",
    number: "0820000000",
    category: "Customer",
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
  await seedManualListing();
  const orderCountBefore = (await db.collection("commerceOrders").get()).size;
  let providerCalled = false;
  axios.defaults.adapter = async () => {
    providerCalled = true;
    throw new Error("Provider must not be called for a manual order");
  };
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  const response = responseRecorder();
  const duplicateResponse = responseRecorder();
  const request = manualOrderRequest();
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

test("a reused checkout attempt cannot cross customer identity", async () => {
  await seedManualListing();
  await db.doc("users/seller-1/customers/customer-2").set({
    name: "Second Buyer Record",
    number: "0820000000",
    category: "Customer",
  });
  const attempt = "attempt-customer-race";
  const firstResponse = responseRecorder();
  const secondResponse = responseRecorder();
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  try {
    await Promise.all([
      createCommerceOrder(
        manualOrderRequest({ checkoutAttemptId: attempt }),
        firstResponse,
      ),
      createCommerceOrder(
        manualOrderRequest({
          checkoutAttemptId: attempt,
          customerId: "customer-2",
        }),
        secondResponse,
      ),
    ]);
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }

  assert.deepEqual(
    [firstResponse.statusCode, secondResponse.statusCode].sort(),
    [200, 400],
  );
  const successful =
    firstResponse.statusCode === 200 ? firstResponse : secondResponse;
  const order = await db.doc(`commerceOrders/${successful.body.orderId}`).get();
  assert.equal(order.exists, true);
  assert.equal(
    order.get("customerId"),
    firstResponse.statusCode === 200 ? "customer-1" : "customer-2",
  );
});

test("WhatsApp order rejects a customer id bound to another phone", async () => {
  await seedManualListing();
  const before = (await db.collection("commerceOrders").get()).size;
  const response = responseRecorder();
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  try {
    await createCommerceOrder(
      manualOrderRequest({
        checkoutAttemptId: "attempt-customer-mismatch",
        buyer: { name: "Wrong Buyer", phone: "0830000000" },
      }),
      response,
    );
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }
  assert.equal(response.statusCode, 400);
  assert.equal((await db.collection("commerceOrders").get()).size, before);
});

test("manual supplier orders reject client quantities above one", async () => {
  await seedManualListing();
  const before = (await db.collection("commerceOrders").get()).size;
  const response = responseRecorder();
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  try {
    await createCommerceOrder(
      manualOrderRequest({
        checkoutAttemptId: "attempt-quantity-tamper",
        quantity: 2,
      }),
      response,
    );
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }
  assert.equal(response.statusCode, 400);
  assert.equal((await db.collection("commerceOrders").get()).size, before);
});

test("manual supplier orders require a valid South African address", async () => {
  await seedManualListing();
  const response = responseRecorder();
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  try {
    await createCommerceOrder(
      manualOrderRequest({
        checkoutAttemptId: "attempt-invalid-address",
        deliveryAddress: {
          line1: "1 Private Road",
          suburb: "Woodstock",
          city: "Cape Town",
          province: "Atlantis",
          postalCode: "12345",
        },
      }),
      response,
    );
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }
  assert.equal(response.statusCode, 400);
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

test("a verified provider event cannot pay a manual WhatsApp order", async () => {
  await db.doc("commerceOrders/manual-webhook-order").set({
    sellerId: "seller-1",
    listingId: "listing-manual",
    customerId: "customer-1",
    buyer: { name: "Manual Buyer", phone: "0820000000" },
    status: "pending_payment",
    paymentStatus: "awaiting_manual_confirmation",
    fulfilmentStatus: "pending",
    paymentMethod: "manual",
    payment: { provider: "manual", reference: "manual-reference" },
    amountDueMinor: 14_000,
    statusHistory: [],
  });

  const response = await sendVerifiedWebhook(
    "provider-ref-for-manual-order",
    14_000,
    {
      orderId: "manual-webhook-order",
      listingId: "listing-manual",
    },
  );
  assert.equal(response.statusCode, 400);
  const order = await db.doc("commerceOrders/manual-webhook-order").get();
  assert.equal(order.get("status"), "pending_payment");
  assert.equal(order.get("paymentStatus"), "awaiting_manual_confirmation");
  assert.equal(
    (
      await db
        .doc(
          "payments/paystackCommerce/processed/provider-ref-for-manual-order",
        )
        .get()
    ).exists,
    false,
  );
});

test("the disabled payment gate rejects even a Paystack-bound verified event", async () => {
  const reference = "provider-ref-while-disabled";
  await db.doc("commerceOrders/disabled-paystack-order").set({
    sellerId: "seller-1",
    listingId: "listing-disabled",
    buyer: { name: "Digital Buyer", phone: "0820000000" },
    status: "pending_payment",
    paymentStatus: "pending",
    fulfilmentStatus: "pending",
    paymentMethod: "paystack",
    payment: { provider: "paystack", reference },
    amountDueMinor: 14_000,
    statusHistory: [],
  });
  const event = verified(reference, 14_000, {
    orderId: "disabled-paystack-order",
    listingId: "listing-disabled",
  });

  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  try {
    await assert.rejects(
      applyVerifiedCommercePayment(event),
      /COMMERCE_PAYMENTS_DISABLED/,
    );
    const response = await sendVerifiedWebhook(reference, 14_000, {
      orderId: "disabled-paystack-order",
      listingId: "listing-disabled",
    });
    assert.equal(response.statusCode, 503);
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }

  const order = await db.doc("commerceOrders/disabled-paystack-order").get();
  assert.equal(order.get("status"), "pending_payment");
  assert.equal(order.get("paymentStatus"), "pending");
  assert.equal(
    (await db.doc(`payments/paystackCommerce/processed/${reference}`).get())
      .exists,
    false,
  );
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
      payment: { provider: "paystack", reference: "commerce-ref-bad" },
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
