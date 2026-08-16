import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import admin from "firebase-admin";
import {
  buildCatalogCacheDocument,
  CATALOG_SNAPSHOT_MAX_AGE_MS,
} from "../lib/commerce/cjCatalogCache.js";
import {
  CATALOG_CURSOR_SCAN_LIMIT,
  catalogJobId,
  catalogSearchNeedsDiscovery,
  advanceCatalogDiscoveryPage,
  enqueueCatalogDemand,
  enqueueProductRefresh,
  getCachedCatalogDocument,
  getCachedCatalogProduct,
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
      quantity: 1,
      logisticName: "CJPacket",
      logisticAging: "10-18 days",
      productCostUsdMinor: 500,
      shippingCostUsdMinor: 300,
      productCostMinor: 9_270,
      shippingCostMinor: 5_562,
      landedCostMinor: 14_832,
      currency: "ZAR",
      fx,
      verifiedAt: new Date().toISOString(),
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

  assert.equal(first.totalProducts, 0);
  assert.equal(first.totalProductsExact, false);
  assert.equal(first.usableProductsLowerBound, 25);
  assert.equal(first.totalPages, 2);
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

test("scanner fills pages past stale raw rows and keeps a safe cursor", async () => {
  const refs = [];
  const batch = db.batch();
  const searchToken = "scannerunique";
  const staleVerifiedAt = new Date(
    Date.now() - CATALOG_SNAPSHOT_MAX_AGE_MS - 1,
  ).toISOString();

  // More than the discovery target's raw count proves stale rows cannot make
  // the catalogue appear sufficiently populated and suppress demand work.
  for (let index = 0; index < 100; index += 1) {
    const value = cachedProduct(1000 + index);
    value.activeSearchTokens = [searchToken];
    value.searchTokens = [searchToken];
    value.deliveryVerifiedAt = staleVerifiedAt;
    value.recommendedQuote = {
      ...value.recommendedQuote,
      verifiedAt: staleVerifiedAt,
    };
    const ref = collection.doc(
      `aa_scan_stale_${String(index).padStart(3, "0")}`,
    );
    refs.push(ref);
    batch.set(ref, value);
  }
  for (let index = 0; index < 30; index += 1) {
    const value = cachedProduct(2000 + index);
    value.activeSearchTokens = [searchToken];
    value.searchTokens = [searchToken];
    const ref = collection.doc(
      `bb_scan_fresh_${String(index).padStart(2, "0")}`,
    );
    refs.push(ref);
    batch.set(ref, value);
  }
  await batch.commit();

  try {
    const first = await searchCachedCatalog(searchToken, 1);
    assert.equal(first.products.length, 24);
    assert.equal(first.products[0].productId, "product_2000");
    assert.equal(first.products[23].productId, "product_2023");
    assert.equal(first.nextCursor, "bb_scan_fresh_23");
    assert.equal(first.hasMore, true);
    assert.equal(first.scanLimited, false);
    assert.equal(first.totalProducts, 0);
    assert.equal(first.totalProductsExact, false);
    assert.equal(first.usableProductsLowerBound, 25);
    // A normal full page with more cached products should not enqueue supplier
    // discovery merely because its bounded result cannot prove an exact total.
    assert.equal(catalogSearchNeedsDiscovery(first), false);

    const cursorSecond = await searchCachedCatalog(
      searchToken,
      2,
      first.nextCursor,
    );
    const legacySecond = await searchCachedCatalog(searchToken, 2);
    assert.deepEqual(
      cursorSecond.products.map((product) => product.productId),
      [
        "product_2024",
        "product_2025",
        "product_2026",
        "product_2027",
        "product_2028",
        "product_2029",
      ],
    );
    assert.deepEqual(
      legacySecond.products.map((product) => product.productId),
      cursorSecond.products.map((product) => product.productId),
    );
    assert.equal(cursorSecond.hasMore, false);
    assert.equal(cursorSecond.nextCursor, "");
    // Reaching the underfilled end should request discovery even though a
    // cursor result cannot report a globally exact catalogue total.
    assert.equal(catalogSearchNeedsDiscovery(cursorSecond), true);
  } finally {
    const cleanup = db.batch();
    refs.forEach((ref) => cleanup.delete(ref));
    await cleanup.commit();
  }
});

test("scan budget returns a forward cursor across an all-stale segment", async () => {
  const refs = [];
  const batch = db.batch();
  const searchToken = "scanbudget";
  const staleVerifiedAt = new Date(
    Date.now() - CATALOG_SNAPSHOT_MAX_AGE_MS - 1,
  ).toISOString();

  for (let index = 0; index < CATALOG_CURSOR_SCAN_LIMIT; index += 1) {
    const value = cachedProduct(3000 + index);
    value.activeSearchTokens = [searchToken];
    value.searchTokens = [searchToken];
    value.deliveryVerifiedAt = staleVerifiedAt;
    value.recommendedQuote = {
      ...value.recommendedQuote,
      verifiedAt: staleVerifiedAt,
    };
    const ref = collection.doc(
      `ca_budget_stale_${String(index).padStart(3, "0")}`,
    );
    refs.push(ref);
    batch.set(ref, value);
  }
  const fresh = cachedProduct(4000);
  fresh.activeSearchTokens = [searchToken];
  fresh.searchTokens = [searchToken];
  const freshRef = collection.doc("cb_budget_fresh_000");
  refs.push(freshRef);
  batch.set(freshRef, fresh);
  await batch.commit();

  try {
    const limited = await searchCachedCatalog(searchToken, 1, "b_cursor_start");
    assert.equal(limited.products.length, 0);
    assert.equal(limited.scanLimited, true);
    assert.equal(limited.hasMore, true);
    assert.equal(limited.nextCursor, "ca_budget_stale_239");
    assert.equal(limited.totalProductsExact, false);
    assert.equal(limited.rawProbePerformed, true);
    assert.equal(limited.rawDocumentsRead, CATALOG_CURSOR_SCAN_LIMIT + 1);

    const continued = await searchCachedCatalog(
      searchToken,
      2,
      limited.nextCursor,
    );
    assert.deepEqual(
      continued.products.map((product) => product.productId),
      ["product_4000"],
    );
    assert.equal(continued.hasMore, false);
  } finally {
    const cleanup = db.batch();
    refs.forEach((ref) => cleanup.delete(ref));
    await cleanup.commit();
  }
});

test("exact scan cap probes exhaustion without a false continuation", async () => {
  const refs = [];
  const batch = db.batch();
  const searchToken = "scanexactcap";
  const staleVerifiedAt = new Date(
    Date.now() - CATALOG_SNAPSHOT_MAX_AGE_MS - 1,
  ).toISOString();

  for (let index = 0; index < CATALOG_CURSOR_SCAN_LIMIT; index += 1) {
    const value = cachedProduct(5000 + index);
    value.activeSearchTokens = [searchToken];
    value.searchTokens = [searchToken];
    value.deliveryVerifiedAt = staleVerifiedAt;
    value.recommendedQuote = {
      ...value.recommendedQuote,
      verifiedAt: staleVerifiedAt,
    };
    const ref = collection.doc(
      `cc_exact_stale_${String(index).padStart(3, "0")}`,
    );
    refs.push(ref);
    batch.set(ref, value);
  }
  await batch.commit();

  try {
    const result = await searchCachedCatalog(searchToken, 1);
    assert.equal(result.products.length, 0);
    assert.equal(result.rawProbePerformed, true);
    assert.ok(result.rawDocumentsRead <= CATALOG_CURSOR_SCAN_LIMIT + 1);
    assert.equal(result.rawDocumentsRead, CATALOG_CURSOR_SCAN_LIMIT);
    assert.equal(result.scanLimited, false);
    assert.equal(result.hasMore, false);
    assert.equal(result.nextCursor, "");
    assert.equal(result.totalProductsExact, true);
    assert.equal(result.totalProducts, 0);
    assert.equal(result.totalPages, 1);
    assert.equal(catalogSearchNeedsDiscovery(result), true);
  } finally {
    const cleanup = db.batch();
    refs.forEach((ref) => cleanup.delete(ref));
    await cleanup.commit();
  }
});

test("stale delivery snapshots are rejected by detail and listing gates", async () => {
  const stale = cachedProduct(70);
  const staleVerifiedAt = new Date(
    Date.now() - CATALOG_SNAPSHOT_MAX_AGE_MS - 1,
  ).toISOString();
  stale.deliveryVerifiedAt = staleVerifiedAt;
  stale.recommendedQuote = {
    ...stale.recommendedQuote,
    verifiedAt: staleVerifiedAt,
  };
  const staleRef = collection.doc("cj_product_70");
  await staleRef.set(stale);

  try {
    assert.equal(await getCachedCatalogProduct("product_70"), null);
    // createDropshipListing consumes this same repository gate before any
    // seller product or commerce listing is written.
    assert.equal(await getCachedCatalogDocument("product_70"), null);
  } finally {
    await staleRef.delete();
  }
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
