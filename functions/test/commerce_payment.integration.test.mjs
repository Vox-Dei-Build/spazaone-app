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
import { prepareCommerceCheckout } from "../lib/commerce/prepareCommerceCheckout.js";
import { processOrderCreatedNotificationOutbox } from "../lib/commerce/orderCreatedNotificationOutbox.js";

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
    "commerceCheckoutPreparations",
    "commerceOrderNotificationOutbox",
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
    redirect(code, location) {
      this.statusCode = code;
      this.headers.location = location;
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

async function botPrepare(body) {
  const response = responseRecorder();
  await prepareCommerceCheckout(
    {
      method: "POST",
      body: {
        merchantId: "seller-1",
        customerId: "customer-1",
        listingId: "listing-manual",
        ...body,
      },
      get(name) {
        return name.toLowerCase() === "x-pasella-bot-token"
          ? botSecret
          : undefined;
      },
    },
    response,
  );
  return response;
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
  process.env.ORDERING_WHATSAPP_NUMBER = "+27600167119";
  process.env.GEOCODING_API_KEY = "emulator-geocoding-key";
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
  await db.doc("users/seller-1").set({
    name: "Seller One",
  });
  await db.doc("users/seller-1/bankingDetails/default").set({
    bankName: "Village Bank",
    accountHolderName: "Seller One",
    accountNumber: "123456789",
    accountType: "Cheque",
    branchCode: "123456",
  });
});

after(async () => {
  axios.defaults.adapter = originalAxiosAdapter;
  delete process.env.PAYSTACK_SECRET_KEY;
  delete process.env.CJ_API_KEY;
  delete process.env.PASELLA_BOT_TOKEN;
  delete process.env.ORDERING_WHATSAPP_NUMBER;
  delete process.env.GEOCODING_API_KEY;
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
  assert.equal(response.body.paymentInstructions.method, "eft");
  assert.equal(
    response.body.paymentInstructions.banking.bankName,
    "Village Bank",
  );
  assert.equal(response.body.paymentInstructions.reference.length, 8);
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
  assert.equal(orders.docs[0].get("buyerPaymentPreference"), "eft");
  assert.equal(orders.docs[0].get("feeMinor"), 0);
  assert.equal(orders.docs[0].get("marginMinor"), 4_000);
  assert.equal(orders.docs[0].get("buyer.email"), "");
  const outbox = await db
    .doc(`commerceOrderNotificationOutbox/${orders.docs[0].id}_created`)
    .get();
  assert.equal(outbox.exists, true);
  assert.equal(outbox.get("status"), "delivered");
  assert.equal(outbox.get("attempts"), 1);
});

test("reused attempts repair and lease the durable order-created outbox", async () => {
  await seedManualListing();
  const checkoutAttemptId = "attempt-outbox-repair";
  const first = responseRecorder();
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  try {
    await createCommerceOrder(manualOrderRequest({ checkoutAttemptId }), first);
    assert.equal(first.statusCode, 200);
    const orderRef = db.doc(`commerceOrders/${first.body.orderId}`);
    const outboxRef = db.doc(
      `commerceOrderNotificationOutbox/${first.body.orderId}_created`,
    );
    const before = await orderRef.get();
    const historyBefore = before.get("notificationHistory").length;
    const unreadBefore = Number(
      (await db.doc("users/seller-1").get()).get("unreadCount"),
    );
    await outboxRef.delete();

    const responses = Array.from({ length: 8 }, () => responseRecorder());
    await Promise.all(
      responses.map((response) =>
        createCommerceOrder(
          manualOrderRequest({ checkoutAttemptId }),
          response,
        ),
      ),
    );
    assert.equal(
      responses.every((response) => response.statusCode === 200),
      true,
    );
    assert.equal(
      responses.every((response) => response.body.reused === true),
      true,
    );
    const repaired = await outboxRef.get();
    assert.equal(repaired.get("status"), "delivered");
    assert.equal(repaired.get("attempts"), 0);
    assert.equal(repaired.get("repairedAt") != null, true);
    const afterRepair = await orderRef.get();
    assert.equal(afterRepair.get("notificationHistory").length, historyBefore);

    await orderRef.update({
      notificationHistory: admin.firestore.FieldValue.delete(),
    });
    await outboxRef.set(
      {
        status: "pending",
        attempts: 0,
        leaseUntilMs: 0,
        deliveredAt: admin.firestore.FieldValue.delete(),
      },
      { merge: true },
    );
    const deliveryResponses = Array.from({ length: 8 }, () =>
      responseRecorder(),
    );
    await Promise.all(
      deliveryResponses.map((response) =>
        createCommerceOrder(
          manualOrderRequest({ checkoutAttemptId }),
          response,
        ),
      ),
    );
    assert.equal(
      deliveryResponses.every((response) => response.statusCode === 200),
      true,
    );
    const delivered = await outboxRef.get();
    assert.equal(delivered.get("status"), "delivered");
    assert.equal(delivered.get("attempts"), 1);
    const afterDelivery = await orderRef.get();
    assert.equal(afterDelivery.get("notificationHistory").length, 1);
    assert.equal(
      Number((await db.doc("users/seller-1").get()).get("unreadCount")),
      unreadBefore,
    );
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }
});

test("scheduled recovery drains an expired order-created delivery lease", async () => {
  await seedManualListing();
  const response = responseRecorder();
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  try {
    await createCommerceOrder(
      manualOrderRequest({ checkoutAttemptId: "attempt-scheduled-recovery" }),
      response,
    );
    assert.equal(response.statusCode, 200);
    const orderRef = db.doc(`commerceOrders/${response.body.orderId}`);
    const outboxRef = db.doc(
      `commerceOrderNotificationOutbox/${response.body.orderId}_created`,
    );
    const unreadBefore = Number(
      (await db.doc("users/seller-1").get()).get("unreadCount"),
    );
    await orderRef.update({
      notificationHistory: admin.firestore.FieldValue.delete(),
    });
    await outboxRef.set(
      {
        status: "delivering",
        attempts: 0,
        claimToken: "expired-claim",
        leaseUntilMs: Date.now() - 1,
        deliveredAt: admin.firestore.FieldValue.delete(),
      },
      { merge: true },
    );

    assert.equal(await processOrderCreatedNotificationOutbox(), 1);
    const recovered = await outboxRef.get();
    assert.equal(recovered.get("status"), "delivered");
    assert.equal(recovered.get("attempts"), 1);
    const recoveredOrder = await orderRef.get();
    assert.equal(recoveredOrder.get("notificationHistory").length, 1);
    assert.equal(
      Number((await db.doc("users/seller-1").get()).get("unreadCount")),
      unreadBefore,
    );
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }
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

test("one rural clarification safely falls back when geocoding is unavailable", async () => {
  await seedManualListing();
  const key = process.env.GEOCODING_API_KEY;
  delete process.env.GEOCODING_API_KEY;
  try {
    const first = await botPrepare({
      delivery: {
        kind: "location",
        latitude: -23.9045,
        longitude: 29.4689,
        plusCode: "5G7C7H2Q+4V",
      },
    });
    assert.equal(first.body.status, "needs_clarification");
    assert.equal(first.body.field, "address");

    const prepared = await botPrepare({
      delivery: {
        kind: "location",
        latitude: -23.9045,
        longitude: 29.4689,
        plusCode: "5G7C7H2Q+4V",
      },
      clarificationAnswer:
        "Nearest town: Polokwane, Limpopo, 0700; landmark near the clinic",
    });
    assert.equal(prepared.body.status, "ready");
    assert.equal(prepared.body.deliveryAddress.source, "manual_review");
    assert.equal(prepared.body.deliveryAddress.city, "Polokwane");
    assert.equal(prepared.body.deliveryAddress.province, "Limpopo");
    assert.equal(prepared.body.deliveryAddress.postalCode, "0700");
    assert.equal(prepared.body.deliveryAddress.plusCode, "5G7C7H2Q+4V");
    assert.deepEqual(prepared.body.deliveryAddress.location, {
      latitude: -23.9045,
      longitude: 29.4689,
    });
    assert.match(prepared.body.deliveryAddress.landmark, /clinic/i);
    assert.deepEqual(prepared.body.paymentOptions, ["eft", "pay_at_shop"]);
  } finally {
    process.env.GEOCODING_API_KEY = key;
  }
});

test("a WhatsApp rural pin reuses its supplied address without retyping known details", async () => {
  await seedManualListing();
  const key = process.env.GEOCODING_API_KEY;
  delete process.env.GEOCODING_API_KEY;
  try {
    const prepared = await botPrepare({
      delivery: {
        kind: "location",
        latitude: -30.54805172,
        longitude: 27.36525977,
        name: "Sona's Fresh bakes",
        address:
          "Masekeleng village Tienbank, Joe Gqabi District Municipality, 9762, Eastern Cape, ZA",
      },
    });
    assert.equal(prepared.body.status, "ready");
    assert.equal(prepared.body.deliveryAddress.source, "manual_review");
    assert.equal(
      prepared.body.deliveryAddress.city,
      "Masekeleng village Tienbank",
    );
    assert.equal(prepared.body.deliveryAddress.province, "Eastern Cape");
    assert.equal(prepared.body.deliveryAddress.postalCode, "9762");
    assert.equal(
      prepared.body.deliveryLabel,
      "Masekeleng village Tienbank, Joe Gqabi District Municipality, 9762, Eastern Cape, ZA",
    );
    assert.deepEqual(prepared.body.deliveryAddress.location, {
      latitude: -30.54805172,
      longitude: 27.36525977,
    });
  } finally {
    process.env.GEOCODING_API_KEY = key;
  }
});

test("zero-result fallback preserves typed rural directions and fails closed when insufficient", async () => {
  await seedManualListing();
  axios.defaults.adapter = async (config) => ({
    data: { status: "ZERO_RESULTS", results: [] },
    status: 200,
    statusText: "OK",
    headers: {},
    config,
  });
  const first = await botPrepare({
    delivery: { kind: "text", text: "Stand 12 Ga-Molepo near the clinic" },
  });
  assert.equal(first.body.status, "needs_clarification");
  const prepared = await botPrepare({
    delivery: { kind: "text", text: "Stand 12 Ga-Molepo near the clinic" },
    clarificationAnswer: "Polokwane, Limpopo, 0700",
  });
  assert.equal(prepared.body.status, "ready");
  assert.equal(
    prepared.body.deliveryAddress.originalText,
    "Stand 12 Ga-Molepo near the clinic",
  );
  assert.equal(
    prepared.body.deliveryAddress.line1,
    "Stand 12 Ga-Molepo near the clinic",
  );
  assert.equal(prepared.body.deliveryAddress.city, "Polokwane");

  const rejected = await botPrepare({
    delivery: { kind: "text", text: "Stand 12 Ga-Molepo" },
    clarificationAnswer: "Near the clinic, Limpopo, 0700",
  });
  assert.equal(rejected.body.status, "unavailable");
  assert.equal(rejected.body.reason, "address_details_invalid");
});

test("pay at shop is reachable but requires the customer's explicit choice", async () => {
  await seedManualListing();
  const missingChoice = responseRecorder();
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  try {
    await createCommerceOrder(
      manualOrderRequest({
        checkoutAttemptId: "attempt-payment-choice-required",
        paymentPreference: undefined,
      }),
      missingChoice,
    );
    assert.equal(missingChoice.statusCode, 409);
    assert.equal(missingChoice.body.code, "PAYMENT_OPTION_REQUIRED");

    const payAtShop = responseRecorder();
    await createCommerceOrder(
      manualOrderRequest({
        checkoutAttemptId: "attempt-pay-at-shop",
        paymentPreference: "pay_at_shop",
      }),
      payAtShop,
    );
    assert.equal(payAtShop.statusCode, 200);
    assert.deepEqual(payAtShop.body.paymentInstructions, {
      method: "pay_at_shop",
      reference: payAtShop.body.reference,
    });
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }
});

test("an existing merchant can explicitly disable pay at shop", async () => {
  await seedManualListing();
  const merchantRef = db.doc("users/seller-1");
  await merchantRef.set(
    { paymentOptions: { payAtShop: false } },
    { merge: true },
  );
  axios.defaults.adapter = async (config) => ({
    data: { status: "ZERO_RESULTS", results: [] },
    status: 200,
    statusText: "OK",
    headers: {},
    config,
  });
  try {
    const prepared = await botPrepare({
      delivery: { kind: "text", text: "Stand 12 Ga-Molepo" },
      clarificationAnswer: "Polokwane, Limpopo, 0700",
    });
    assert.equal(prepared.body.status, "ready");
    assert.deepEqual(prepared.body.paymentOptions, ["eft"]);

    const response = responseRecorder();
    process.env.COMMERCE_PAYMENTS_ENABLED = "false";
    try {
      await createCommerceOrder(
        manualOrderRequest({
          checkoutAttemptId: "attempt-disabled-pay-at-shop",
          paymentPreference: "pay_at_shop",
        }),
        response,
      );
    } finally {
      process.env.COMMERCE_PAYMENTS_ENABLED = "true";
    }
    assert.equal(response.statusCode, 409);
    assert.equal(response.body.code, "PAYMENT_OPTION_UNAVAILABLE");
  } finally {
    await merchantRef.update({
      paymentOptions: admin.firestore.FieldValue.delete(),
    });
  }
});

test("prepared checkout rejects a price changed after customer review", async () => {
  await seedManualListing();
  axios.defaults.adapter = async (config) => ({
    data: {
      status: "OK",
      results: [
        {
          formatted_address: "Stand 12, Ga-Molepo, Limpopo, 0727",
          plus_code: { global_code: "5G7C7H2Q+4V" },
          address_components: [
            { long_name: "Ga-Molepo", types: ["sublocality_level_1"] },
            { long_name: "Polokwane", types: ["locality"] },
            { long_name: "Limpopo", types: ["administrative_area_level_1"] },
            { long_name: "0727", types: ["postal_code"] },
          ],
        },
      ],
    },
    status: 200,
    statusText: "OK",
    headers: {},
    config,
  });
  const prepared = responseRecorder();
  await prepareCommerceCheckout(
    {
      method: "POST",
      body: {
        merchantId: "seller-1",
        customerId: "customer-1",
        listingId: "listing-manual",
        delivery: { kind: "text", text: "Stand 12 Ga-Molepo" },
        clarificationAnswer: "Near the clinic",
      },
      get(name) {
        return name.toLowerCase() === "x-pasella-bot-token"
          ? botSecret
          : undefined;
      },
    },
    prepared,
  );
  assert.equal(prepared.statusCode, 200);
  assert.equal(prepared.body.status, "ready");
  assert.equal(prepared.body.amountDueMinor, 14_000);
  assert.deepEqual(prepared.body.paymentOptions, ["eft", "pay_at_shop"]);
  assert.deepEqual(prepared.body.deliveryEstimate, {
    minDays: 10,
    maxDays: 20,
  });
  assert.equal(prepared.body.plusCode, "5G7C7H2Q+4V");

  const preparedSnapshot = await db
    .doc(`commerceCheckoutPreparations/${prepared.body.preparationId}`)
    .get();
  const expiredPreparationId = `${prepared.body.preparationId}-expired`;
  await db.doc(`commerceCheckoutPreparations/${expiredPreparationId}`).set({
    ...preparedSnapshot.data(),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1),
  });
  const expired = responseRecorder();
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  try {
    await createCommerceOrder(
      manualOrderRequest({
        checkoutAttemptId: "attempt-prepared-expired",
        preparationId: expiredPreparationId,
      }),
      expired,
    );
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }
  assert.equal(expired.statusCode, 409);
  assert.equal(expired.body.code, "CHECKOUT_PREPARATION_EXPIRED");

  const reboundPreparationId = `${prepared.body.preparationId}-rebound`;
  await db.doc(`commerceCheckoutPreparations/${reboundPreparationId}`).set({
    ...preparedSnapshot.data(),
    customerId: "customer-2",
  });
  const rebound = responseRecorder();
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  try {
    await createCommerceOrder(
      manualOrderRequest({
        checkoutAttemptId: "attempt-prepared-rebound",
        preparationId: reboundPreparationId,
      }),
      rebound,
    );
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }
  assert.equal(rebound.statusCode, 409);
  assert.equal(rebound.body.code, "CHECKOUT_PREPARATION_INVALID");

  await db.doc("commerceListings/listing-manual").update({
    sellPriceMinor: 15_000,
  });
  const before = (await db.collection("commerceOrders").get()).size;
  const response = responseRecorder();
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  try {
    await createCommerceOrder(
      manualOrderRequest({
        checkoutAttemptId: "attempt-prepared-price-change",
        preparationId: prepared.body.preparationId,
      }),
      response,
    );
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }
  assert.equal(response.statusCode, 409);
  assert.equal(response.body.code, "CHECKOUT_PREPARATION_CHANGED");
  assert.equal((await db.collection("commerceOrders").get()).size, before);
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

  assert.equal(response.statusCode, 302);
  assert.match(response.headers.location, /^https:\/\/wa\.me\//);
  assert.match(response.headers.location, /shop\+/i);
  assert.doesNotMatch(response.headers.location, /Paystack/i);
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

test("a prepared CJ quote serves concurrent final-create retries without supplier re-quoting", async () => {
  await db.doc("commerceListings/cj-prepared-listing").set({
    sellerId: "seller-1",
    sellerProductId: "seller-product-prepared",
    supplierId: "cj_dropshipping",
    supplierProductId: "cj-product-prepared",
    supplierVariantId: "cj-variant-prepared",
    markupMinor: 1_000,
    baseCostMinor: 1,
    sellPriceMinor: 2,
    title: "Prepared CJ lamp",
    images: [],
    active: true,
    fulfilmentMode: "seller_manual_cj_order",
  });
  let supplierCalls = 0;
  axios.defaults.adapter = async (config) => {
    const url = String(config.url ?? "");
    let data;
    if (url.includes("maps.googleapis.com")) {
      data = {
        status: "OK",
        results: [
          {
            formatted_address: "Stand 12, Ga-Molepo, Limpopo, 0700",
            plus_code: { global_code: "5G7C7H2Q+4V" },
            address_components: [
              { long_name: "Ga-Molepo", types: ["sublocality_level_1"] },
              { long_name: "Polokwane", types: ["locality"] },
              { long_name: "Limpopo", types: ["administrative_area_level_1"] },
              { long_name: "0700", types: ["postal_code"] },
            ],
          },
        ],
      };
    } else if (url.includes("authentication/getAccessToken")) {
      supplierCalls += 1;
      data = {
        result: true,
        data: {
          accessToken: "cj-prepared-token",
          accessTokenExpiryDate: "2027-08-03T00:00:00Z",
        },
      };
    } else if (url.includes("frankfurter.dev")) {
      data = { date: "2026-08-03", base: "USD", quote: "ZAR", rate: 18 };
    } else if (url.endsWith("/product/query")) {
      supplierCalls += 1;
      data = {
        result: true,
        data: {
          pid: "cj-product-prepared",
          productSku: "CJ-PREPARED",
          productNameEn: "Prepared CJ lamp",
          status: "3",
          variants: [
            {
              vid: "cj-variant-prepared",
              pid: "cj-product-prepared",
              variantSku: "CJ-PREPARED-BLK",
              variantKey: "Black",
              variantSellPrice: 5,
            },
          ],
        },
      };
    } else if (url.endsWith("/product/variant/queryByVid")) {
      supplierCalls += 1;
      data = {
        result: true,
        data: {
          vid: "cj-variant-prepared",
          pid: "cj-product-prepared",
          variantSku: "CJ-PREPARED-BLK",
          variantKey: "Black",
          variantSellPrice: 5,
          inventories: [{ countryCode: "CN", totalInventory: 10 }],
        },
      };
    } else if (url.endsWith("/logistic/freightCalculate")) {
      supplierCalls += 1;
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

  const prepared = await botPrepare({
    listingId: "cj-prepared-listing",
    delivery: { kind: "text", text: "Stand 12 Ga-Molepo" },
    clarificationAnswer: "Near the clinic",
  });
  assert.equal(prepared.body.status, "ready");
  const callsAfterPreparation = supplierCalls;
  assert.equal(callsAfterPreparation > 0, true);
  const preparation = await db
    .doc(`commerceCheckoutPreparations/${prepared.body.preparationId}`)
    .get();
  assert.equal(
    preparation.get("quoteReservation.productId"),
    "cj-product-prepared",
  );
  assert.equal(
    preparation.get("quoteReservation.expiresAtMs") <=
      preparation.get("expiresAt").toMillis(),
    true,
  );

  const responses = Array.from({ length: 10 }, () => responseRecorder());
  process.env.COMMERCE_PAYMENTS_ENABLED = "false";
  try {
    const tamperedPreparationId = `${prepared.body.preparationId}-tampered`;
    const preparedData = preparation.data();
    await db.doc(`commerceCheckoutPreparations/${tamperedPreparationId}`).set({
      ...preparedData,
      quoteReservation: {
        ...preparedData.quoteReservation,
        productCostMinor: preparedData.quoteReservation.productCostMinor + 100,
        landedCostMinor: preparedData.quoteReservation.landedCostMinor + 100,
      },
    });
    const tampered = responseRecorder();
    await createCommerceOrder(
      manualOrderRequest({
        listingId: "cj-prepared-listing",
        preparationId: tamperedPreparationId,
        checkoutAttemptId: "cj-prepared-tampered-attempt",
        paymentPreference: "eft",
      }),
      tampered,
    );
    assert.equal(tampered.statusCode, 409);
    assert.equal(tampered.body.code, "CHECKOUT_PREPARATION_CHANGED");
    assert.equal(supplierCalls, callsAfterPreparation);

    await Promise.all(
      responses.map((response) =>
        createCommerceOrder(
          manualOrderRequest({
            listingId: "cj-prepared-listing",
            preparationId: prepared.body.preparationId,
            checkoutAttemptId: "cj-prepared-concurrent-attempt",
            paymentPreference: "eft",
          }),
          response,
        ),
      ),
    );
  } finally {
    process.env.COMMERCE_PAYMENTS_ENABLED = "true";
  }
  assert.equal(
    responses.every((response) => response.statusCode === 200),
    true,
  );
  assert.equal(
    new Set(responses.map((response) => response.body.orderId)).size,
    1,
  );
  assert.equal(supplierCalls, callsAfterPreparation);
  const orders = await db
    .collection("commerceOrders")
    .where("listingId", "==", "cj-prepared-listing")
    .get();
  assert.equal(orders.size, 1);
  assert.equal(
    orders.docs[0].get("amountDueMinor"),
    prepared.body.amountDueMinor,
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
