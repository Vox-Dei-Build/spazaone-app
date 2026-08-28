import assert from "node:assert/strict";
import { createHash, randomBytes } from "node:crypto";
import { beforeEach, test } from "node:test";
import admin from "firebase-admin";
import { buildMerchantCatalogDecision } from "../lib/whatsapp/catalogProjection.js";
import {
  WhatsAppCatalogCartValidationError,
  replaceWhatsAppCatalogCartAtomically,
} from "../lib/ecommerce/replaceWhatsAppCatalogCart.js";
import {
  cancelFailedNativeInventoryReservationAtomically,
  nativeCatalogCheckoutHandler,
} from "../lib/ecommerce/checkoutCart.js";

const projectId = process.env.GCLOUD_PROJECT || "demo-spazaone-native-cart";
if (!admin.apps.length) admin.initializeApp({ projectId });
const db = admin.firestore();
const merchantId = "merchant_a";
const customerId = "customer_1";
const recipientPhone = "+27821234567";
const senderPhoneNumberId = "9876543210";
const catalogId = "1234567890";
const recipientHash = createHash("sha256")
  .update(`emulator-only\u0000${recipientPhone}`)
  .digest("hex");
// Generated per process. It exercises the bot-authenticated checkout branch
// without reading, storing, or passing any real credential.
const emulatorBotProof = randomBytes(32).toString("hex");
process.env.PASELLA_BOT_TOKEN = emulatorBotProof;

async function clear() {
  for (const collection of [
    "users",
    "whatsappCatalogMappings",
    "whatsappCatalogCartReplacements",
    "whatsappCatalogCartStates",
    "merchantCommerceSettings",
  ]) {
    await admin.firestore().recursiveDelete(db.collection(collection));
  }
}

async function seed(count = 10) {
  const merchant = {
    name: "Synthetic Merchant",
    whatsappOrdering: {
      orderingUrl: "https://shop.example.test/synthetic-merchant",
    },
  };
  await Promise.all([
    db.doc(`users/${merchantId}`).set(merchant),
    db.doc(`users/${merchantId}/customers/${customerId}`).set({
      number: "0821234567",
      name: "Synthetic Buyer",
    }),
  ]);
  const items = [];
  for (let index = 0; index < count; index += 1) {
    const productId = `product_${index + 1}`;
    const sellPriceMinor = 1_000 + index;
    const product = {
      name: `Synthetic Product ${index + 1}`,
      description: `Synthetic product ${index + 1}`,
      sellPriceMinor,
      sellingPrice: 999.99,
      imageUrl: `https://images.example.test/product-${index + 1}.jpg`,
      whatsappListed: true,
      quantity: 50,
    };
    const decision = buildMerchantCatalogDecision({
      merchantId,
      productId,
      product,
      merchant,
    });
    assert.equal(decision.action, "upsert");
    await Promise.all([
      db.doc(`users/${merchantId}/products/${productId}`).set(product),
      db.doc(`whatsappCatalogMappings/${decision.retailerId}`).set({
        status: "active",
        merchantId,
        productId,
        retailerId: decision.retailerId,
        lastAppliedRevision: decision.revision,
      }),
    ]);
    items.push({
      retailerId: decision.retailerId,
      quantity: (index % 3) + 1,
      expectedPriceMinor: sellPriceMinor,
    });
  }
  return { merchant, items };
}

function replacementBody(items, idempotencyKey) {
  return {
    merchantId,
    customerId,
    recipient: recipientPhone,
    senderPhoneNumberId,
    catalogId,
    idempotencyKey,
    items,
  };
}

async function replace(items, idempotencyKey) {
  return replaceWhatsAppCatalogCartAtomically({
    request: replacementBody(items, idempotencyKey),
    recipientHash,
  });
}

async function invokeCheckout(body) {
  let status = 200;
  let responseBody;
  const response = {
    status(code) {
      status = code;
      return this;
    },
    json(value) {
      responseBody = value;
      return this;
    },
    send(value) {
      responseBody = value;
      return this;
    },
  };
  const request = {
    method: "POST",
    body,
    get(name) {
      return name.toLowerCase() === "x-pasella-bot-token"
        ? emulatorBotProof
        : undefined;
    },
  };
  await nativeCatalogCheckoutHandler(request, response);
  return { status, body: responseBody };
}

beforeEach(clear);

test("ten-line replacement is idempotent and checks out at canonical prices", async () => {
  const { items } = await seed();
  const first = await replace(items, "native-cart:integration-1");
  assert.equal(first.outcome, "replaced");
  assert.equal(first.cart.lineCount, 10);
  assert.match(first.cart.nativeCartFingerprint, /^[a-f0-9]{64}$/);

  const duplicate = await replace(
    [...items].reverse(),
    "native-cart:integration-1",
  );
  assert.equal(duplicate.outcome, "duplicate");
  assert.equal(
    duplicate.cart.nativeCartFingerprint,
    first.cart.nativeCartFingerprint,
  );

  const checkout = await invokeCheckout({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey: "native-cart:integration-1",
    nativeCartFingerprint: first.cart.nativeCartFingerprint,
  });
  assert.equal(checkout.status, 200);
  assert.equal(checkout.body.success, true);
  const sale = await db
    .doc(`users/${merchantId}/sales/${checkout.body.saleId}`)
    .get();
  assert.equal(sale.get("cartSource"), "whatsapp_native_catalog");
  assert.equal(
    sale.get("nativeCartFingerprint"),
    first.cart.nativeCartFingerprint,
  );
  assert.equal(sale.get("subtotalMinor"), first.cart.totalMinor);
  assert.equal(sale.get("items").length, 10);
  assert.equal(sale.get("items")[0].priceMinor, 1_000);
});

test("late tenth-item failure leaves every existing cart document unchanged", async () => {
  const { items } = await seed();
  const initial = await replace(items, "native-cart:integration-before");
  assert.equal(initial.outcome, "replaced");
  const cartRef = db.doc(`users/${merchantId}/carts/${customerId}`);
  const beforeSummary = (await cartRef.get()).data();
  const beforeItems = (await cartRef.collection("items").get()).docs.map(
    (document) => ({ id: document.id, data: document.data() }),
  );

  await db.doc(`users/${merchantId}/products/product_10`).update({
    sellPriceMinor: items[9].expectedPriceMinor + 100,
  });
  await assert.rejects(
    replace(items, "native-cart:integration-late-failure"),
    (error) =>
      error instanceof WhatsAppCatalogCartValidationError &&
      error.reason === "price_changed" &&
      error.failedItemIndex === 9,
  );

  const afterSummary = (await cartRef.get()).data();
  const afterItems = (await cartRef.collection("items").get()).docs.map(
    (document) => ({ id: document.id, data: document.data() }),
  );
  assert.equal(
    afterSummary.nativeCartFingerprint,
    beforeSummary.nativeCartFingerprint,
  );
  assert.deepEqual(
    afterItems.map(({ id, data }) => [id, data.quantity, data.catalogRevision]),
    beforeItems.map(({ id, data }) => [
      id,
      data.quantity,
      data.catalogRevision,
    ]),
  );
});

test("checkout rejects a cart mutation before creating a sale or lock", async () => {
  const { items } = await seed();
  const replaced = await replace(items, "native-cart:integration-guard");
  assert.equal(replaced.outcome, "replaced");
  await db
    .doc(`users/${merchantId}/carts/${customerId}/items/product_10`)
    .update({ quantity: 49 });

  const checkout = await invokeCheckout({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey: "native-cart:integration-guard",
    nativeCartFingerprint: replaced.cart.nativeCartFingerprint,
  });
  assert.equal(checkout.status, 409);
  assert.equal(checkout.body.code, "NATIVE_CATALOG_CART_CHANGED");
  assert.equal(
    (await db.collection(`users/${merchantId}/sales`).get()).size,
    0,
  );
  assert.equal(
    (await db.doc(`users/${merchantId}/carts/${customerId}`).get()).get("lock"),
    undefined,
  );
});

test("concurrent native checkouts with distinct keys create exactly one sale", async () => {
  const { items } = await seed();
  const replaced = await replace(items, "native-cart:integration-race");
  assert.equal(replaced.outcome, "replaced");
  const request = (idempotencyKey) => ({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey,
    nativeCartFingerprint: replaced.cart.nativeCartFingerprint,
  });

  const responses = await Promise.all([
    invokeCheckout(request("native-cart:integration-race-a")),
    invokeCheckout(request("native-cart:integration-race-b")),
  ]);
  assert.deepEqual(
    responses.map((response) => response.status).sort(),
    [200, 409],
  );
  assert.equal(
    responses.find((response) => response.status === 409).body.code,
    "NATIVE_CATALOG_CART_CHANGED",
  );
  assert.equal(
    (await db.collection(`users/${merchantId}/sales`).get()).size,
    1,
  );
});

test("a locked native checkout cannot be replaced by a later catalogue cart", async () => {
  const { items } = await seed();
  const first = await replace(items, "native-cart:integration-locked");
  assert.equal(first.outcome, "replaced");
  const checkout = await invokeCheckout({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey: "native-cart:integration-locked",
    nativeCartFingerprint: first.cart.nativeCartFingerprint,
  });
  assert.equal(checkout.status, 200);

  await assert.rejects(
    replace(
      items.map((item, index) => ({
        ...item,
        quantity: index === 0 ? item.quantity + 1 : item.quantity,
      })),
      "native-cart:integration-locked-replace",
    ),
    (error) =>
      error instanceof WhatsAppCatalogCartValidationError &&
      error.reason === "cart_changed",
  );
  const cart = await db.doc(`users/${merchantId}/carts/${customerId}`).get();
  assert.equal(cart.get("lock").saleId, checkout.body.saleId);
  assert.equal(
    cart.get("nativeCartFingerprint"),
    first.cart.nativeCartFingerprint,
  );
});

test("native checkout rejects an idempotency receipt bound to another cart", async () => {
  const { items } = await seed(1);
  const replaced = await replace(items, "native-cart:integration-conflict");
  assert.equal(replaced.outcome, "replaced");
  await db
    .doc(
      `users/${merchantId}/checkoutIdempotency/${encodeURIComponent("native-cart:integration-conflict")}`,
    )
    .set({
      customerId: "another_customer",
      cartSig: "f".repeat(64),
      saleId: "another_sale",
    });

  const checkout = await invokeCheckout({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey: "native-cart:integration-conflict",
    nativeCartFingerprint: replaced.cart.nativeCartFingerprint,
  });
  assert.equal(checkout.status, 409);
  assert.equal(checkout.body.code, "IDEMPOTENCY_CONFLICT");
  assert.equal(
    (await db.collection(`users/${merchantId}/sales`).get()).size,
    0,
  );
});

test("failed native inventory reservation cancels sale and releases receipt and lock atomically", async () => {
  const { items } = await seed(1);
  const idempotencyKey = "native-cart:integration-reservation-failure";
  const replaced = await replace(items, idempotencyKey);
  assert.equal(replaced.outcome, "replaced");
  const checkout = await invokeCheckout({
    merchantId,
    customerId,
    paymentType: "Cash",
    fulfillmentType: "pickup",
    idempotencyKey,
    nativeCartFingerprint: replaced.cart.nativeCartFingerprint,
  });
  assert.equal(checkout.status, 200);
  const saleRef = db.doc(`users/${merchantId}/sales/${checkout.body.saleId}`);
  const receiptRef = db.doc(
    `users/${merchantId}/checkoutIdempotency/${encodeURIComponent(idempotencyKey)}`,
  );
  const cartRef = db.doc(`users/${merchantId}/carts/${customerId}`);

  await cancelFailedNativeInventoryReservationAtomically({
    saleRef,
    idempotencyRef: receiptRef,
    cartRef,
    saleId: checkout.body.saleId,
    reason: "INVENTORY_PRICE_CHANGED",
  });

  assert.equal((await saleRef.get()).get("status"), "cancelled");
  assert.equal((await receiptRef.get()).exists, false);
  assert.equal((await cartRef.get()).get("lock"), undefined);
});
