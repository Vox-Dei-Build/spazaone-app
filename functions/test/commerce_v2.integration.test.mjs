import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { createRequire } from "node:module";
import admin from "firebase-admin";
import { createCommerceOrder } from "../lib/commerce/payment.js";
import { prepareCommerceCheckout } from "../lib/commerce/prepareCommerceCheckout.js";

const emulatorHost = String(process.env.FIRESTORE_EMULATOR_HOST ?? "");
const projectId = String(
  process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "",
);
if (!emulatorHost || !projectId.startsWith("demo-")) {
  throw new Error("Refusing commerce V2 integration without a demo emulator.");
}

const requireModule = createRequire(import.meta.url);
const axios = requireModule("axios");
const originalAdapter = axios.defaults.adapter;
const db = admin.firestore();
const botToken = "emulator-commerce-v2-bot";

function responseRecorder() {
  return {
    statusCode: 200,
    body: null,
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
    set() {
      return this;
    },
  };
}

function botRequest(body) {
  return {
    method: "POST",
    body,
    get(name) {
      return name.toLowerCase() === "x-pasella-bot-token"
        ? botToken
        : undefined;
    },
  };
}

function ok(config, data) {
  return {
    data,
    status: 200,
    statusText: "OK",
    headers: {},
    config,
  };
}

async function clear() {
  for (const collection of [
    "users",
    "commerceListings",
    "commerceCheckoutPreparations",
    "commerceCheckoutAttempts",
    "commerceOrders",
    "merchantPaymentProfiles",
    "paymentConfiguration",
    "paymentIntents",
    "supplierFundingReservations",
    "supplierFundingState",
    "operationsAlerts",
  ]) {
    await admin.firestore().recursiveDelete(db.collection(collection));
  }
}

function installProviderFakes() {
  axios.defaults.adapter = async (config) => {
    const url = String(config.url ?? "");
    if (url.includes("maps.googleapis.com")) {
      return ok(config, {
        status: "OK",
        results: [
          {
            formatted_address: "1 Main Road, Cape Town, 7925",
            address_components: [
              { long_name: "1", types: ["street_number"] },
              { long_name: "Main Road", types: ["route"] },
              { long_name: "Woodstock", types: ["sublocality_level_1"] },
              { long_name: "Cape Town", types: ["locality"] },
              {
                long_name: "Western Cape",
                types: ["administrative_area_level_1"],
              },
              { long_name: "7925", types: ["postal_code"] },
            ],
          },
        ],
      });
    }
    if (url.includes("authentication/getAccessToken")) {
      return ok(config, {
        result: true,
        data: {
          accessToken: "emulator-cj-v2-token",
          accessTokenExpiryDate: "2099-01-01T00:00:00.000Z",
        },
      });
    }
    if (url.includes("frankfurter.dev")) {
      return ok(config, {
        date: "2026-08-13",
        base: "USD",
        quote: "ZAR",
        rate: 18,
      });
    }
    if (url.endsWith("/product/query")) {
      return ok(config, {
        result: true,
        data: {
          pid: "cj-product-v2",
          productSku: "CJ-V2",
          productNameEn: "Rechargeable lamp",
          status: "3",
          variants: [
            {
              vid: "cj-variant-v2",
              pid: "cj-product-v2",
              variantSku: "CJ-V2-BLK",
              variantKey: "Black",
              variantSellPrice: 5,
            },
          ],
        },
      });
    }
    if (url.endsWith("/product/variant/queryByVid")) {
      return ok(config, {
        result: true,
        data: {
          vid: "cj-variant-v2",
          pid: "cj-product-v2",
          variantSku: "CJ-V2-BLK",
          variantKey: "Black",
          variantSellPrice: 5,
          inventories: [{ countryCode: "CN", totalInventory: 20 }],
        },
      });
    }
    if (url.endsWith("/logistic/freightCalculate")) {
      return ok(config, {
        result: true,
        data: [
          {
            logisticName: "CJPacket ZA",
            logisticAging: "8-14",
            logisticPrice: 2,
          },
        ],
      });
    }
    if (url === "/shopping/pay/getBalance") {
      return ok(config, { result: true, data: { amount: "1000.00" } });
    }
    if (url.includes("paystack.co/transaction/initialize")) {
      const input =
        typeof config.data === "string" ? JSON.parse(config.data) : config.data;
      return ok(config, {
        status: true,
        data: {
          authorization_url: "https://paystack.test/supplier-v2",
          reference: input.reference,
        },
      });
    }
    throw new Error(`Unexpected commerce V2 request: ${url}`);
  };
}

async function prepare({ quantity = 1, listingId = "listing-v2" } = {}) {
  const response = responseRecorder();
  await prepareCommerceCheckout(
    botRequest({
      merchantId: "seller-v2",
      customerId: "customer-v2",
      listingId,
      quantity,
      delivery: {
        kind: "text",
        text: "1 Main Road, Woodstock, Cape Town, Western Cape, 7925",
      },
    }),
    response,
  );
  return response;
}

before(async () => {
  process.env.SPAZAONE_ENVIRONMENT = "local";
  process.env.SPAZAONE_FIREBASE_PROJECT_ID = projectId;
  process.env.PAYMENTS_V2_MASTER_ENABLED = "true";
  process.env.PAYSTACK_SECRET_KEY = "sk_test_emulator_paystack_secret";
  process.env.PASELLA_BOT_TOKEN = botToken;
  process.env.CJ_API_KEY = "emulator-cj-secret";
  process.env.CJ_SANDBOX_MODE = "true";
  process.env.GEOCODING_API_KEY = "emulator-maps-secret";
  await clear();
  installProviderFakes();
  await Promise.all([
    db.doc("paymentConfiguration/global").set({
      emergencySuspended: false,
      capabilities: { supplier_order: true },
    }),
    db.doc("merchantPaymentProfiles/seller-v2").set({
      status: "enabled",
      bankVerificationStatus: "approved",
      paystackSubaccountCode: "ACCT_EMULATORV2",
      capabilities: { supplier_order: true },
    }),
    db.doc("users/seller-v2").set({ name: "Seller V2" }),
    db.doc("users/seller-v2/customers/customer-v2").set({
      name: "Buyer V2",
      number: "0820000000",
      category: "Customer",
    }),
    db.doc("commerceListings/listing-v2").set({
      sellerId: "seller-v2",
      sellerProductId: "seller-product-v2",
      supplierId: "cj_dropshipping",
      supplierProductId: "cj-product-v2",
      supplierVariantId: "cj-variant-v2",
      markupMinor: 1_000,
      title: "Rechargeable lamp · Black",
      images: ["https://example.test/lamp.jpg"],
      active: true,
      fulfilmentMode: "cj_automatic",
    }),
    db.doc("commerceListings/listing-tight-margin").set({
      sellerId: "seller-v2",
      sellerProductId: "seller-product-tight",
      supplierId: "cj_dropshipping",
      supplierProductId: "cj-product-v2",
      supplierVariantId: "cj-variant-v2",
      markupMinor: 500,
      title: "Rechargeable lamp · Tight margin",
      images: [],
      active: true,
      fulfilmentMode: "cj_automatic",
    }),
  ]);
});

after(async () => {
  axios.defaults.adapter = originalAdapter;
  for (const key of [
    "SPAZAONE_ENVIRONMENT",
    "SPAZAONE_FIREBASE_PROJECT_ID",
    "PAYMENTS_V2_MASTER_ENABLED",
    "PAYSTACK_SECRET_KEY",
    "PASELLA_BOT_TOKEN",
    "CJ_API_KEY",
    "CJ_SANDBOX_MODE",
    "GEOCODING_API_KEY",
  ]) {
    delete process.env[key];
  }
  await clear();
});

test("supplier preparation quotes quantity and exposes only profitable channels", async () => {
  const prepared = await prepare({ quantity: 5 });
  assert.equal(prepared.statusCode, 200);
  assert.equal(prepared.body.status, "ready");
  assert.equal(prepared.body.quantity, 5);
  assert.equal(prepared.body.maxQuantity, 20);
  assert.deepEqual(prepared.body.paymentOptions, [
    "card",
    "eft",
    "capitec_pay",
    "qr",
  ]);

  const tight = await prepare({ listingId: "listing-tight-margin" });
  assert.equal(tight.body.status, "ready");
  assert.deepEqual(tight.body.paymentOptions, ["eft", "capitec_pay"]);
});

test("supplier quantity and capability gates fail closed before initialization", async () => {
  const overCap = await prepare({ quantity: 21 });
  assert.equal(overCap.body.status, "unavailable");
  assert.equal(overCap.body.reason, "quantity_invalid");

  await db.doc("merchantPaymentProfiles/seller-v2").update({
    "capabilities.supplier_order": false,
  });
  const disabled = await prepare();
  assert.equal(disabled.body.status, "unavailable");
  assert.equal(disabled.body.reason, "online_payment_not_ready");
  assert.equal((await db.collection("commerceOrders").get()).empty, true);
  await db.doc("merchantPaymentProfiles/seller-v2").update({
    "capabilities.supplier_order": true,
  });
});

test("one prepared supplier checkout creates one funded Paystack intent", async () => {
  const prepared = await prepare({ quantity: 5 });
  assert.equal(prepared.body.status, "ready");
  const body = {
    merchantId: "seller-v2",
    customerId: "customer-v2",
    listingId: "listing-v2",
    orderChannel: "whatsapp",
    checkoutAttemptId: "supplier-v2-attempt",
    preparationId: prepared.body.preparationId,
    quantity: 5,
    paymentChannel: "eft",
    buyer: {
      name: "Buyer V2",
      phone: "0820000000",
      email: "buyer@example.test",
    },
    deliveryAddress: prepared.body.deliveryAddress,
  };
  const first = responseRecorder();
  await createCommerceOrder(botRequest(body), first);
  assert.equal(first.statusCode, 200);
  assert.equal(first.body.paymentMethod, "paystack");
  assert.equal(
    first.body.authorizationUrl,
    "https://paystack.test/supplier-v2",
  );

  const replay = responseRecorder();
  await createCommerceOrder(botRequest(body), replay);
  assert.equal(replay.statusCode, 200);
  assert.equal(replay.body.reused, true);
  assert.equal(replay.body.orderId, first.body.orderId);

  const orders = await db.collection("commerceOrders").get();
  assert.equal(orders.size, 1);
  assert.equal(orders.docs[0].get("quantity"), 5);
  assert.equal(orders.docs[0].get("requestedPaymentChannel"), "eft");
  assert.equal(orders.docs[0].get("paymentStatus"), "pending");
  const intents = await db.collection("paymentIntents").get();
  assert.equal(intents.size, 1);
  assert.equal(intents.docs[0].get("purpose"), "supplier_order");
  assert.equal(intents.docs[0].get("selectedChannel"), "eft");
  const reservations = await db.collection("supplierFundingReservations").get();
  assert.equal(reservations.size, 1);
  assert.equal(reservations.docs[0].get("status"), "active");
});
