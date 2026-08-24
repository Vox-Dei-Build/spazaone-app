import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { createRequire } from "node:module";
import admin from "firebase-admin";
import {
  createCommerceOrder,
  getCommerceOrderStatus,
} from "../lib/commerce/payment.js";
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
let paystackInitializeCalls = 0;
let supplierFundingCalls = 0;

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
        // Keep the provider fake within the production freshness window. A
        // fixed date makes this integration test start calling the fallback
        // path as soon as the calendar advances, which tests time rather than
        // checkout behavior.
        date: new Date().toISOString().slice(0, 10),
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
      supplierFundingCalls += 1;
      return ok(config, { result: true, data: { amount: "1000.00" } });
    }
    if (url.includes("paystack.co/transaction/initialize")) {
      paystackInitializeCalls += 1;
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
    db.doc("users/seller-v2").set({
      name: "Seller V2",
      buildNumber: 88,
    }),
    db.doc("users/seller-v2/bankingDetails/primary").set({
      bankName: "Capitec Bank",
      accountHolderName: "Seller V2",
      accountNumber: "1234567890",
      accountType: "Savings",
      branchCode: "470010",
    }),
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

test("supplier preparation quotes quantity and offers merchant Cash/EFT", async () => {
  const prepared = await prepare({ quantity: 5 });
  assert.equal(prepared.statusCode, 200);
  assert.equal(prepared.body.status, "ready");
  assert.equal(prepared.body.quantity, 5);
  assert.equal(prepared.body.maxQuantity, 20);
  assert.deepEqual(prepared.body.paymentOptions, ["cash", "eft"]);
  assert.equal(prepared.body.onlinePaymentStatus, "coming_soon");

  const tight = await prepare({ listingId: "listing-tight-margin" });
  assert.equal(tight.body.status, "ready");
  assert.deepEqual(tight.body.paymentOptions, ["cash", "eft"]);
});

test("supplier quantity and manual-payment setup gates fail closed", async () => {
  const overCap = await prepare({ quantity: 21 });
  assert.equal(overCap.body.status, "unavailable");
  assert.equal(overCap.body.reason, "quantity_invalid");

  await db.doc("users/seller-v2").update({
    paymentOptions: { cash: false, eft: false },
  });
  const disabled = await prepare();
  assert.equal(disabled.body.status, "unavailable");
  assert.equal(disabled.body.reason, "payment_setup_required");
  assert.equal((await db.collection("commerceOrders").get()).empty, true);
  await db.doc("users/seller-v2").update({
    paymentOptions: { cash: true, eft: true },
  });
});

test("one prepared supplier checkout creates one manual EFT order only", async () => {
  paystackInitializeCalls = 0;
  supplierFundingCalls = 0;
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
    paymentOption: "eft",
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
  assert.equal(first.body.paymentMethod, "manual");
  assert.match(first.body.confirmationUrl, /order=/);
  assert.equal(first.body.paymentInstructions.method, "eft");
  assert.equal(first.body.paymentInstructions.bankName, "Capitec Bank");
  assert.equal(first.body.paymentInstructions.accountNumber, "1234567890");

  const confirmation = new URL(first.body.confirmationUrl);
  const publicStatus = responseRecorder();
  await getCommerceOrderStatus(
    {
      method: "GET",
      query: {
        order: confirmation.searchParams.get("order"),
        token: confirmation.searchParams.get("token"),
      },
    },
    publicStatus,
  );
  assert.equal(publicStatus.statusCode, 200);
  assert.equal(publicStatus.body.paymentMethod, "manual");
  assert.equal(publicStatus.body.paymentInstructions.method, "eft");
  assert.equal(
    publicStatus.body.paymentInstructions.accountNumber,
    "1234567890",
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
  assert.equal(orders.docs[0].get("paymentMethod"), "manual");
  assert.equal(
    orders.docs[0].get("paymentStatus"),
    "awaiting_manual_confirmation",
  );
  assert.equal(orders.docs[0].get("fulfilmentMode"), "seller_manual_cj_order");
  const intents = await db.collection("paymentIntents").get();
  assert.equal(intents.size, 0);
  const reservations = await db.collection("supplierFundingReservations").get();
  assert.equal(reservations.size, 0);
  assert.equal(paystackInitializeCalls, 0);
  assert.equal(supplierFundingCalls, 0);
});
