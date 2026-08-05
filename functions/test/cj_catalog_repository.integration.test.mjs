import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import admin from "firebase-admin";
import { buildCatalogCacheDocument } from "../lib/commerce/cjCatalogCache.js";
import {
  catalogJobId,
  advanceCatalogDiscoveryPage,
  enqueueCatalogDemand,
  enqueueProductRefresh,
  searchCachedCatalog,
} from "../lib/commerce/cjCatalogRepository.js";

const emulatorHost = String(process.env.FIRESTORE_EMULATOR_HOST ?? "");
const emulatorProject = String(
  process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "",
);
if (!emulatorHost || !emulatorProject.startsWith("demo-")) {
  throw new Error(
    "Refusing catalogue integration test without a demo Firestore emulator.",
  );
}

const db = admin.firestore();
const collection = db.collection("supplierCatalogProducts");
const jobs = db.collection("supplierCatalogJobs");
const demand = db.collection("supplierCatalogDemand");
const fx = {
  rate: 18,
  rateMicros: 18_000_000,
  date: "2026-08-05",
  bufferBps: 300,
};

function cachedProduct(index) {
  const suffix = String(index).padStart(2, "0");
  const productId = `product_${suffix}`;
  const variant = {
    variantId: `variant_${suffix}`,
    productId,
    sku: `LAMP-${suffix}`,
    name: "Black",
    option: "Black",
    image: `https://example.test/${suffix}.jpg`,
    productCostUsdMinor: 500,
    estimatedProductCostMinor: 9_270,
  };
  const product = {
    productId,
    productSku: `LAMP-${suffix}`,
    title: `Rechargeable lamp ${suffix}`,
    image: variant.image,
    category: "Home lighting",
    productCostUsdMinor: 500,
    estimatedProductCostMinor: 9_270,
  };
  const details = {
    ...product,
    description: "Portable lamp",
    images: [variant.image],
    status: "3",
    variants: [variant],
    fx,
  };
  return buildCatalogCacheDocument(
    product,
    {
      product: details,
      variant,
      originCountryCode: "CN",
      stock: 20,
      logisticName: "CJPacket",
      logisticAging: "10-18 days",
      productCostUsdMinor: 500,
      shippingCostUsdMinor: 300,
      productCostMinor: 9_270,
      shippingCostMinor: 5_562,
      landedCostMinor: 14_832,
      currency: "ZAR",
      fx,
      verifiedAt: "2026-08-05T10:00:00.000Z",
    },
    1_000 + index,
    "home",
  );
}

before(async () => {
  await Promise.all(
    [collection, jobs, demand].map((target) =>
      admin.firestore().recursiveDelete(target),
    ),
  );
  const batch = db.batch();
  for (let index = 0; index < 49; index += 1) {
    batch.set(
      collection.doc(`cj_product_${String(index).padStart(2, "0")}`),
      cachedProduct(index),
    );
  }
  const inactive = cachedProduct(49);
  batch.set(collection.doc("cj_product_49"), {
    ...inactive,
    active: false,
    activeSearchTokens: [],
  });
  await batch.commit();
});

after(async () => {
  await Promise.all(
    [collection, jobs, demand].map((target) =>
      admin.firestore().recursiveDelete(target),
    ),
  );
});

test("catalog search cursor pages are stable and exclude inactive products", async () => {
  const first = await searchCachedCatalog("lamp", 1);
  const cursorSecond = await searchCachedCatalog("lamp", 2, first.nextCursor);
  const legacySecond = await searchCachedCatalog("lamp", 2);

  assert.equal(first.totalProducts, 49);
  assert.equal(first.totalPages, 3);
  assert.equal(first.products.length, 24);
  assert.equal(first.hasMore, true);
  assert.ok(first.nextCursor);
  assert.equal(cursorSecond.products.length, 24);
  assert.equal(cursorSecond.hasMore, true);
  assert.deepEqual(
    cursorSecond.products.map((product) => product.productId),
    legacySecond.products.map((product) => product.productId),
  );
  assert.equal(
    first.products.some((firstProduct) =>
      cursorSecond.products.some(
        (secondProduct) => secondProduct.productId === firstProduct.productId,
      ),
    ),
    false,
  );
  assert.equal(
    [...first.products, ...cursorSecond.products].some(
      (product) => product.productId === "product_49",
    ),
    false,
  );
});

test("catalog discovery advances beyond the old ten-page ceiling", async () => {
  await advanceCatalogDiscoveryPage("Kitchen", 10, 50);
  // Demand IDs are intentionally hashed; query by its normalized public value
  // so this test does not duplicate the hashing implementation.
  let matching = await demand.where("query", "==", "kitchen").get();
  assert.equal(matching.size, 1);
  assert.equal(matching.docs[0].data().nextSupplierPage, 11);

  await advanceCatalogDiscoveryPage("Kitchen", 50, 50);
  matching = await demand.where("query", "==", "kitchen").get();
  assert.equal(matching.docs[0].data().nextSupplierPage, 1);
});

test("catalog jobs expose a single-field pending queue selector", async () => {
  await enqueueCatalogDemand("Furniture");
  const discovery = await jobs
    .doc(catalogJobId("discover_query", "furniture"))
    .get();
  assert.equal(discovery.data()?.status, "pending");
  assert.equal(discovery.data()?.queueBand, "background");
  assert.equal(discovery.data()?.pendingQueueBand, "background");

  await enqueueProductRefresh({
    product: {
      productId: "queued-product",
      title: "Queued product",
    },
    query: "furniture",
    priority: 45,
  });
  const refresh = await jobs
    .doc(catalogJobId("refresh_product", "queued-product"))
    .get();
  assert.equal(refresh.data()?.status, "pending");
  assert.equal(refresh.data()?.queueBand, "demand");
  assert.equal(refresh.data()?.pendingQueueBand, "demand");
});
