import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import admin from "firebase-admin";
import { buildCatalogCacheDocument } from "../lib/commerce/cjCatalogCache.js";

export const QA_SELLER_UID = "qa-seller-owner";
export const QA_SECONDARY_STORE_ID = "qa-seller-store-2";
export const QA_SELLER_PHONE = "+27648370009";
export const QA_PROJECT_PATTERN = /^demo-[a-z0-9][a-z0-9-]*$/;

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = path.resolve(SCRIPT_DIR, "../..");

function requiredLocalEndpoint(value, name) {
  const raw = String(value ?? "").trim();
  if (!raw || raw.includes("://")) {
    throw new Error(`${name} must be an explicit loopback host:port.`);
  }
  let url;
  try {
    url = new URL(`http://${raw}`);
  } catch {
    throw new Error(`${name} must be an explicit loopback host:port.`);
  }
  const localHosts = new Set(["127.0.0.1", "localhost", "[::1]"]);
  if (!localHosts.has(url.hostname) || !url.port) {
    throw new Error(`${name} must be an explicit loopback host:port.`);
  }
  return raw;
}

/** Refuses every non-local or production-shaped target before Admin starts. */
export function validateQaSeedEnvironment(env = process.env) {
  const projectCandidates = [
    env.QA_FIREBASE_PROJECT_ID,
    env.GCLOUD_PROJECT,
    env.GOOGLE_CLOUD_PROJECT,
  ]
    .map((value) => String(value ?? "").trim())
    .filter(Boolean);
  const distinctProjects = [...new Set(projectCandidates)];
  if (
    distinctProjects.length !== 1 ||
    !QA_PROJECT_PATTERN.test(distinctProjects[0])
  ) {
    throw new Error(
      "Local QA seed refused: set one matching demo-* Firebase project id.",
    );
  }

  const deviceHost = String(env.QA_DEVICE_FIREBASE_HOST ?? "10.0.2.2").trim();
  if (!["10.0.2.2", "127.0.0.1", "localhost", "::1"].includes(deviceHost)) {
    throw new Error("QA_DEVICE_FIREBASE_HOST must stay on the local machine.");
  }

  return {
    projectId: distinctProjects[0],
    firestoreHost: requiredLocalEndpoint(
      env.FIRESTORE_EMULATOR_HOST,
      "FIRESTORE_EMULATOR_HOST",
    ),
    authHost: requiredLocalEndpoint(
      env.FIREBASE_AUTH_EMULATOR_HOST,
      "FIREBASE_AUTH_EMULATOR_HOST",
    ),
    storageHost: requiredLocalEndpoint(
      env.FIREBASE_STORAGE_EMULATOR_HOST,
      "FIREBASE_STORAGE_EMULATOR_HOST",
    ),
    deviceHost,
  };
}

const catalogSpecs = [
  [
    "qa_home_lamp",
    "Rechargeable emergency lamp",
    "Home",
    "Black",
    "electronics.png",
    620,
    310,
    "8-15",
  ],
  [
    "qa_home_dryer",
    "Foldable indoor clothes dryer",
    "Home",
    "White",
    "tools.png",
    1_180,
    540,
    "12-20",
  ],
  [
    "qa_fashion_bag",
    "Everyday crossbody shoulder bag",
    "Fashion",
    "Brown",
    "apparel.png",
    760,
    360,
    "10-18",
  ],
  [
    "qa_fashion_shoes",
    "Lightweight everyday sneakers",
    "Fashion",
    "Size 7",
    "apparel.png",
    1_020,
    480,
    "11-19",
  ],
  [
    "qa_beauty_brushes",
    "Complete makeup brush set",
    "Beauty",
    "Rose",
    "medicine.png",
    430,
    270,
    "9-16",
  ],
  [
    "qa_beauty_mirror",
    "Rechargeable LED makeup mirror",
    "Beauty",
    "White",
    "jewellery.png",
    890,
    410,
    "10-17",
  ],
  [
    "qa_electronics_earbuds",
    "Wireless pocket earbuds",
    "Electronics",
    "Black",
    "electronics.png",
    840,
    290,
    "8-14",
  ],
  [
    "qa_electronics_powerbank",
    "Compact fast-charge power bank",
    "Electronics",
    "10 000 mAh",
    "recharge.png",
    980,
    330,
    "9-15",
  ],
  [
    "qa_baby_feeding",
    "Baby silicone feeding set",
    "Baby",
    "Sage",
    "groceries.png",
    580,
    300,
    "10-17",
  ],
  [
    "qa_baby_organizer",
    "Portable baby essentials organiser",
    "Baby",
    "Grey",
    "apparel.png",
    740,
    390,
    "11-18",
  ],
  [
    "qa_accessory_bottle",
    "Insulated stainless travel bottle",
    "Accessories",
    "750 ml",
    "travel.png",
    690,
    380,
    "10-16",
  ],
  [
    "qa_accessory_phone_stand",
    "Adjustable desktop phone stand",
    "Accessories",
    "Silver",
    "electronics.png",
    390,
    250,
    "8-14",
  ],
];

export function buildQaCatalogDocuments({
  nowMs = Date.now(),
  imageUrls = {},
} = {}) {
  const verifiedAt = new Date(nowMs).toISOString();
  const fx = {
    rate: 18,
    rateMicros: 18_000_000,
    date: verifiedAt.slice(0, 10),
    bufferBps: 300,
  };

  return catalogSpecs.map(
    (
      [
        productId,
        title,
        category,
        option,
        imageFile,
        productUsd,
        shippingUsd,
        aging,
      ],
      index,
    ) => {
      const image = imageUrls[imageFile] ?? "";
      const productCostMinor = Math.round(productUsd * 18 * 1.03);
      const shippingCostMinor = Math.round(shippingUsd * 18 * 1.03);
      const variant = {
        variantId: `${productId}_variant`,
        productId,
        sku: `QA-${String(index + 1).padStart(3, "0")}`,
        name: option,
        option,
        image,
        productCostUsdMinor: productUsd,
        estimatedProductCostMinor: productCostMinor,
      };
      const product = {
        productId,
        productSku: variant.sku,
        title,
        image,
        category,
        productCostUsdMinor: productUsd,
        estimatedProductCostMinor: productCostMinor,
      };
      const details = {
        ...product,
        description: `${title} supplied through the local Spaza One QA catalogue.`,
        images: image ? [image] : [],
        status: "3",
        variants: [variant],
        fx,
      };
      const document = buildCatalogCacheDocument(
        product,
        {
          product: details,
          variant,
          originCountryCode: "CN",
          stock: 40 + index,
          quantity: 1,
          logisticName: "Spaza One QA delivery",
          logisticAging: `${aging} days`,
          productCostUsdMinor: productUsd,
          shippingCostUsdMinor: shippingUsd,
          productCostMinor,
          shippingCostMinor,
          landedCostMinor: productCostMinor + shippingCostMinor,
          currency: "ZAR",
          fx,
          verifiedAt,
        },
        nowMs,
        category,
      );
      return { id: `cj_${productId}`, productId, imageFile, document };
    },
  );
}

function storageMediaUrl({ projectId, storageHost, deviceHost, objectName }) {
  const port = new URL(`http://${storageHost}`).port;
  const bucket = `${projectId}.appspot.com`;
  return `http://${deviceHost}:${port}/v0/b/${bucket}/o/${encodeURIComponent(objectName)}?alt=media`;
}

async function seedImages(bucket, target) {
  const files = [...new Set(catalogSpecs.map((spec) => spec[4]))];
  const urls = {};
  await Promise.all(
    files.map(async (fileName) => {
      const source = path.join(
        REPOSITORY_ROOT,
        "assets/images/business_categories",
        fileName,
      );
      if (!existsSync(source)) {
        throw new Error(`Missing local QA image asset: ${fileName}`);
      }
      const objectName = `products/${QA_SELLER_UID}/qa-seed-${fileName}`;
      await bucket.upload(source, {
        destination: objectName,
        metadata: {
          contentType: "image/png",
          cacheControl: "public,max-age=300",
          metadata: { source: "local-qa-seed" },
        },
      });
      urls[fileName] = storageMediaUrl({ ...target, objectName });
    }),
  );
  return urls;
}

async function upsertQaAuthUser(auth) {
  try {
    await auth.getUser(QA_SELLER_UID);
    await auth.updateUser(QA_SELLER_UID, {
      phoneNumber: QA_SELLER_PHONE,
      displayName: "QA Seller",
      disabled: false,
    });
  } catch (error) {
    if (error?.code !== "auth/user-not-found") throw error;
    await auth.createUser({
      uid: QA_SELLER_UID,
      phoneNumber: QA_SELLER_PHONE,
      displayName: "QA Seller",
    });
  }
}

function membership({ storeId, storeName, now }) {
  const common = {
    storeId,
    uid: QA_SELLER_UID,
    role: "owner",
    status: "active",
    displayName: "QA Seller",
    phoneLast4: "0009",
    joinedAt: now,
    updatedAt: now,
    source: "local-qa-seed",
    schemaVersion: 2,
  };
  return {
    store: common,
    operator: { ...common, storeName },
  };
}

async function seedFirestore(db, catalog, imageUrls) {
  const now = admin.firestore.Timestamp.now();
  const primaryName = "QA Corner Store";
  const secondaryName = "QA Market Annex";
  const primaryMembership = membership({
    storeId: QA_SELLER_UID,
    storeName: primaryName,
    now,
  });
  const secondaryMembership = membership({
    storeId: QA_SECONDARY_STORE_ID,
    storeName: secondaryName,
    now,
  });
  const phoneHash = createHash("sha256").update(QA_SELLER_PHONE).digest("hex");
  const batch = db.batch();

  batch.set(
    db.doc(`users/${QA_SELLER_UID}`),
    {
      name: "QA Seller",
      shopName: primaryName,
      mobileNumber: QA_SELLER_PHONE,
      mobileNumberNormalized: "0648370009",
      businessType: "Retail",
      businessCategory: "General dealer",
      referralCount: 0,
      qaSeed: true,
      updatedAt: now,
    },
    { merge: true },
  );
  batch.set(
    db.doc(`users/${QA_SELLER_UID}/wallet/current`),
    {
      virtualBalance: 100.0,
      cashAdvanceBalance: 0.0,
      salesVirtualBalance: 0.0,
      accountSuspended: false,
      qaSeed: true,
      updatedAt: now,
    },
    { merge: true },
  );
  batch.set(
    db.doc(`users/${QA_SELLER_UID}/customers/qa-customer-1`),
    {
      name: "Naledi QA Customer",
      number: "0820000001",
      category: "Customer",
      balance: 0.0,
      isNPA: false,
      ordersUnreadCount: 0,
      lastTransaction: {
        amount: 0.0,
        remarks: "No transactions yet",
        status: "PAID",
        type: "Payment",
        date: now,
        products: {},
      },
      qaSeed: true,
    },
    { merge: true },
  );
  batch.set(
    db.doc(`users/${QA_SELLER_UID}/products/qa-owned-product`),
    {
      name: "QA shop bread",
      description: "Seller-owned comparison product for local device QA.",
      cost: 12.0,
      sellingPrice: 16.0,
      group: "Groceries",
      company: primaryName,
      quantity: 20,
      image: imageUrls["groceries.png"],
      whatsappListed: true,
      isDropshipListing: false,
      qaSeed: true,
      createdAt: now,
      updatedAt: now,
    },
    { merge: true },
  );

  for (const [storeId, storeName, data] of [
    [QA_SELLER_UID, primaryName, primaryMembership],
    [QA_SECONDARY_STORE_ID, secondaryName, secondaryMembership],
  ]) {
    batch.set(
      db.doc(`stores/${storeId}`),
      {
        name: storeName,
        ownerUid: QA_SELLER_UID,
        status: "active",
        legacyUserPath: `users/${storeId}`,
        schemaVersion: 2,
        qaSeed: true,
        updatedAt: now,
      },
      { merge: true },
    );
    batch.set(
      db.doc(`stores/${storeId}/operators/${QA_SELLER_UID}`),
      data.store,
      { merge: true },
    );
    batch.set(
      db.doc(`operators/${QA_SELLER_UID}/stores/${storeId}`),
      data.operator,
      { merge: true },
    );
    batch.set(
      db.doc(`operatorPhoneLookup/${phoneHash}/stores/${storeId}`),
      {
        storeId,
        uid: QA_SELLER_UID,
        role: "owner",
        status: "active",
        storeName,
        updatedAt: now,
        qaSeed: true,
      },
      { merge: true },
    );
  }
  batch.set(
    db.doc(`users/${QA_SECONDARY_STORE_ID}`),
    {
      name: "QA Seller",
      shopName: secondaryName,
      ownerUid: QA_SELLER_UID,
      mobileNumber: QA_SELLER_PHONE,
      mobileNumberNormalized: "0648370009",
      qaSeed: true,
      updatedAt: now,
    },
    { merge: true },
  );
  batch.set(
    db.doc(`users/${QA_SECONDARY_STORE_ID}/wallet/current`),
    {
      virtualBalance: 0.0,
      cashAdvanceBalance: 0.0,
      salesVirtualBalance: 0.0,
      accountSuspended: false,
      qaSeed: true,
      updatedAt: now,
    },
    { merge: true },
  );

  for (const item of catalog) {
    batch.set(db.doc(`supplierCatalogProducts/${item.id}`), item.document);
  }
  await batch.commit();
}

export async function seedLocalQa(env = process.env) {
  const target = validateQaSeedEnvironment(env);
  process.env.GCLOUD_PROJECT = target.projectId;
  process.env.GOOGLE_CLOUD_PROJECT = target.projectId;
  process.env.FIRESTORE_EMULATOR_HOST = target.firestoreHost;
  process.env.FIREBASE_AUTH_EMULATOR_HOST = target.authHost;
  process.env.FIREBASE_STORAGE_EMULATOR_HOST = target.storageHost;
  if (admin.apps.length === 0) {
    admin.initializeApp({
      projectId: target.projectId,
      storageBucket: `${target.projectId}.appspot.com`,
    });
  }
  const bucket = admin.storage().bucket();
  const imageUrls = await seedImages(bucket, target);
  const catalog = buildQaCatalogDocuments({ imageUrls });
  await upsertQaAuthUser(admin.auth());
  await seedFirestore(admin.firestore(), catalog, imageUrls);
  return {
    projectId: target.projectId,
    sellerUid: QA_SELLER_UID,
    stores: 2,
    customers: 1,
    ownedProducts: 1,
    catalogProducts: catalog.length,
  };
}

const invokedDirectly =
  process.argv[1] &&
  pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url;

if (invokedDirectly) {
  try {
    const result = await seedLocalQa();
    console.log(
      `Local QA seed ready in ${result.projectId}: ` +
        `${result.stores} stores, ${result.customers} customer, ` +
        `${result.ownedProducts} owned product and ` +
        `${result.catalogProducts} catalogue products.`,
    );
    console.log(`Existing-seller UID: ${result.sellerUid}`);
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  } finally {
    await Promise.all(admin.apps.map((app) => app.delete()));
  }
}
