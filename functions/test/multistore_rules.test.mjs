import assert from "node:assert/strict";
import { after, before, beforeEach, test } from "node:test";
import { readFile } from "node:fs/promises";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  collectionGroup,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from "firebase/firestore";
import { getBytes, ref, uploadString } from "firebase/storage";

let env;

before(async () => {
  // Cross-service Storage rules use Firestore membership lookups. The test
  // project must therefore match the emulator hub project; a hard-coded
  // second demo project makes those lookups target an empty namespace.
  const projectId = process.env.GCLOUD_PROJECT || "demo-spazaone-multistore";
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: await readFile(
        new URL("../../firestore.rules", import.meta.url),
        "utf8",
      ),
    },
    storage: {
      rules: await readFile(
        new URL("../../storage.rules", import.meta.url),
        "utf8",
      ),
    },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, "users/storeA"), { shopName: "Alpha" }),
      setDoc(doc(db, "users/storeA/wallet/current"), {
        virtualBalance: 50,
        salesVirtualBalance: 900,
      }),
      setDoc(doc(db, "users/storeA/bankingDetails/default"), {
        bankName: "Test Bank",
        accountNumber: "1234567890",
      }),
      setDoc(doc(db, "users/storeA/customers/customerA"), { balance: -10 }),
      setDoc(
        doc(db, "users/storeA/customers/customerA/transactions/transactionA"),
        { status: "DUE", type: "Credit" },
      ),
      setDoc(doc(db, "users/storeB"), { shopName: "Beta" }),
      setDoc(doc(db, "users/storeB/customers/customerB"), { balance: -20 }),
      setDoc(
        doc(db, "users/storeB/customers/customerB/transactions/transactionB"),
        { status: "DUE", type: "Credit" },
      ),
      setDoc(doc(db, "stores/storeA"), { name: "Alpha", ownerUid: "ownerA" }),
      setDoc(doc(db, "stores/storeA/operators/operator1"), {
        role: "operator",
        status: "active",
      }),
      setDoc(doc(db, "stores/storeA/operators/admin1"), {
        role: "admin",
        status: "active",
      }),
      setDoc(doc(db, "stores/storeB/operators/operator1"), {
        role: "operator",
        status: "disabled",
      }),
      setDoc(doc(db, "stores/storeB/operators/operator2"), {
        role: "operator",
        status: "active",
      }),
      setDoc(doc(db, "campaignWalletBalances/storeA"), {
        balance: 50,
        shared: true,
      }),
      setDoc(doc(db, "campaignWalletAccess/storeA/members/operator2"), {
        walletStoreId: "storeA",
        storeIds: ["storeB"],
      }),
      setDoc(doc(db, "messagingTemplates/templateA"), {
        userId: "storeA",
        name: "Legacy template",
      }),
      setDoc(doc(db, "promotions/promotionA"), {
        merchantId: "storeA",
        status: "saved",
      }),
      setDoc(doc(db, "payoutRequests/payoutA"), {
        merchantId: "storeA",
        payoutStatus: "pending",
      }),
      setDoc(doc(db, "paymentReferences/referenceA"), {
        merchantId: "storeA",
      }),
      setDoc(doc(db, "paymentIntents/intentA"), {
        merchantId: "storeA",
        status: "paid",
      }),
      setDoc(doc(db, "paymentEvents/eventA"), {
        provider: "paystack",
      }),
      setDoc(doc(db, "merchantPaymentProfiles/storeA"), {
        merchantId: "storeA",
        status: "enabled",
      }),
      setDoc(doc(db, "merchantCommerceSettings/storeA"), {
        merchantId: "storeA",
        delivery: { enabled: true, flatFeeMinor: 500 },
      }),
      setDoc(doc(db, "settlements/settlementA"), { merchantId: "storeA" }),
      setDoc(doc(db, "refundCases/refundA"), { merchantId: "storeA" }),
      setDoc(doc(db, "inventoryReservations/reservationA"), {
        merchantId: "storeA",
      }),
      setDoc(doc(db, "supplierFulfilments/fulfilmentA"), {
        merchantId: "storeA",
      }),
      setDoc(doc(db, "supplierFundingReservations/reservationA"), {
        merchantId: "storeA",
      }),
      setDoc(doc(db, "supplierFundingState/cj"), {
        provider: "cj",
      }),
      setDoc(doc(db, "operationsAlerts/alertA"), {
        merchantId: "storeA",
      }),
      setDoc(doc(db, "supplierCancellationRequests/requestA"), {
        merchantId: "storeA",
      }),
      setDoc(doc(db, "paymentOperations/operationA"), {
        merchantId: "storeA",
      }),
      setDoc(doc(db, "financialReconciliationRuns/runA"), {
        status: "balanced",
      }),
      setDoc(doc(db, "paymentConfiguration/global"), { enabled: false }),
      setDoc(
        doc(db, "paymentSecurityBudgets/settlement_bank_validation_2026-08-13"),
        { attemptCount: 1 },
      ),
      setDoc(doc(db, "campaignCreditPurchases/purchaseA"), {
        merchantId: "storeA",
      }),
      setDoc(doc(db, "campaignCreditRecoveryCases/recoveryA"), {
        merchantId: "storeA",
      }),
      setDoc(doc(db, "repaymentPlans/planA"), { merchantId: "storeA" }),
      setDoc(doc(db, "customerPaymentRequests/requestA"), {
        merchantId: "storeA",
      }),
      setDoc(doc(db, "customerPaymentRequestState/stateA"), {
        merchantId: "storeA",
      }),
      setDoc(doc(db, "paymentRequestWalletReservations/requestA"), {
        storeId: "storeA",
      }),
      setDoc(doc(db, "commerceNotificationOutbox/noticeA"), {
        state: "pending",
      }),
      setDoc(doc(db, "commerceListings/listingA"), {
        sellerId: "storeA",
        active: true,
        sellPriceMinor: 14000,
      }),
      setDoc(doc(db, "commerceOrders/orderA"), {
        sellerId: "storeA",
        status: "paid",
        amountDueMinor: 14000,
        marginMinor: 3418,
      }),
      setDoc(doc(db, "supplierCatalogProducts/cj_productA"), {
        active: true,
        title: "Supplier product",
      }),
      setDoc(doc(db, "supplierCatalogJobs/jobA"), {
        status: "pending",
      }),
      setDoc(doc(db, "supplierCatalogDemand/queryA"), { count: 1 }),
      setDoc(doc(db, "supplierIntegrationState/cjRequestGate"), {
        nextAllowedAtMs: 1,
      }),
    ]);
  });
});

after(async () => {
  await env.cleanup();
});

test("legacy owner keeps access to own nested data but not another store", async () => {
  const db = env.authenticatedContext("storeA").firestore();
  await assertSucceeds(getDoc(doc(db, "users/storeA/customers/customerA")));
  await assertSucceeds(
    setDoc(doc(db, "users/storeA/products/product1"), { name: "Bread" }),
  );
  await assertFails(getDoc(doc(db, "users/storeB/customers/customerB")));
});

test("supplier and WhatsApp catalogue internals remain server-only", async () => {
  for (const db of [
    env.authenticatedContext("storeA").firestore(),
    env.authenticatedContext("admin-user", { isAdmin: true }).firestore(),
    env.unauthenticatedContext().firestore(),
  ]) {
    await assertFails(getDoc(doc(db, "supplierCatalogProducts/cj_productA")));
    await assertFails(getDoc(doc(db, "supplierCatalogJobs/jobA")));
    await assertFails(getDoc(doc(db, "supplierCatalogDemand/queryA")));
    await assertFails(
      getDoc(doc(db, "supplierIntegrationState/cjRequestGate")),
    );
    await assertFails(getDoc(doc(db, "whatsappCatalogMappings/spz_item")));
    await assertFails(getDoc(doc(db, "whatsappCatalogOutbox/spz_item")));
    await assertFails(
      getDoc(doc(db, "whatsappCatalogSyncState/productReconciliation")),
    );
    await assertFails(
      getDoc(doc(db, "whatsappCatalogReconciliationRuns/runA")),
    );
    await assertFails(
      getDoc(doc(db, "whatsappProductListDeliveries/deliveryA")),
    );
    await assertFails(
      getDoc(doc(db, "whatsappProductListRecipientState/recipientA")),
    );
    await assertFails(
      getDoc(doc(db, "whatsappCatalogCartReplacements/replacementA")),
    );
    await assertFails(getDoc(doc(db, "whatsappCatalogCartStates/stateA")));
  }
});

test("active operator can use assigned store and disabled membership cannot", async () => {
  const db = env.authenticatedContext("operator1").firestore();
  await assertSucceeds(getDoc(doc(db, "users/storeA/customers/customerA")));
  await assertSucceeds(
    setDoc(doc(db, "users/storeA/sales/sale1"), { total: 100 }),
  );
  await assertFails(getDoc(doc(db, "users/storeB/customers/customerB")));
});

test("only owners and admins can alter settlement banking details", async () => {
  const operator = env.authenticatedContext("operator1").firestore();
  const adminDb = env.authenticatedContext("admin1").firestore();
  const legacyOwner = env.authenticatedContext("storeA").firestore();
  const bankingPath = "users/storeA/bankingDetails/default";
  await assertSucceeds(getDoc(doc(operator, bankingPath)));
  await assertFails(
    updateDoc(doc(operator, bankingPath), { accountNumber: "9999999999" }),
  );
  await assertSucceeds(
    updateDoc(doc(adminDb, bankingPath), { reference: "Admin approved" }),
  );
  await assertSucceeds(
    updateDoc(doc(legacyOwner, bankingPath), { reference: "Owner approved" }),
  );
});

test("operator cannot grant itself membership or inspect phone invites", async () => {
  const db = env.authenticatedContext("operator1").firestore();
  await assertFails(
    setDoc(doc(db, "stores/storeB/operators/operator1"), {
      role: "owner",
      status: "active",
    }),
  );
  await assertFails(getDoc(doc(db, "operatorInvites/hash/stores/storeA")));
});

test("shared operator sees campaign balance but not canonical sales fields", async () => {
  const db = env.authenticatedContext("operator2").firestore();
  const projection = await assertSucceeds(
    getDoc(doc(db, "campaignWalletBalances/storeA")),
  );
  assert.equal(projection.get("balance"), 50);
  await assertFails(getDoc(doc(db, "users/storeA/wallet/current")));
  await assertFails(
    updateDoc(doc(db, "campaignWalletBalances/storeA"), { balance: 999 }),
  );
  await assertFails(
    getDoc(doc(db, "campaignWalletAccess/storeA/members/operator2")),
  );
});

test("Payments V2 truth is server-only for owners, operators and admins", async () => {
  const paths = [
    "paymentIntents/intentA",
    "paymentEvents/eventA",
    "merchantPaymentProfiles/storeA",
    "settlements/settlementA",
    "refundCases/refundA",
    "inventoryReservations/reservationA",
    "supplierFulfilments/fulfilmentA",
    "supplierFundingReservations/reservationA",
    "supplierFundingState/cj",
    "operationsAlerts/alertA",
    "supplierCancellationRequests/requestA",
    "paymentOperations/operationA",
    "financialReconciliationRuns/runA",
    "financialMigrationRuns/runA",
    "schemaMetadata/paymentsV2",
    "developmentSeedRuns/runA",
    "paymentConfiguration/global",
    "paymentSecurityBudgets/settlement_bank_validation_2026-08-13",
    "paymentAdministrationAudit/auditA",
    "paymentAdministrationRequests/requestA",
    "paymentOperationsNotifications/notificationA",
    "paymentMonitoringIncidents/incidentA",
    "merchantCommerceSettings/storeA",
    "campaignCreditPurchases/purchaseA",
    "campaignCreditRecoveryCases/recoveryA",
    "repaymentPlans/planA",
    "customerPaymentRequests/requestA",
    "customerPaymentRequestState/stateA",
    "paymentRequestWalletReservations/requestA",
    "commerceNotificationOutbox/noticeA",
  ];
  for (const client of [
    env.authenticatedContext("storeA").firestore(),
    env.authenticatedContext("operator1").firestore(),
    env.authenticatedContext("spaza-admin", { spazaAdmin: true }).firestore(),
    env.unauthenticatedContext().firestore(),
  ]) {
    for (const path of paths) {
      await assertFails(getDoc(doc(client, path)));
      await assertFails(setDoc(doc(client, path), { forged: true }));
    }
  }
});

test("operator can update only notification fields on its own membership", async () => {
  const db = env.authenticatedContext("operator1").firestore();
  const ownMembership = doc(db, "stores/storeA/operators/operator1");
  await assertSucceeds(
    updateDoc(ownMembership, {
      fcmToken: "device-a",
      fcmTokens: ["device-a"],
      notificationUpdatedAt: new Date(),
    }),
  );
  await assertFails(updateDoc(ownMembership, { role: "owner" }));

  const otherDb = env.authenticatedContext("ownerA").firestore();
  await assertFails(
    updateDoc(doc(otherDb, "stores/storeA/operators/operator1"), {
      fcmToken: "owner-device",
    }),
  );
});

test("promotion ownership follows store membership", async () => {
  const operatorDb = env.authenticatedContext("operator1").firestore();
  await assertSucceeds(
    setDoc(doc(operatorDb, "promotions/promoA"), {
      merchantId: "storeA",
      status: "saved",
    }),
  );
  await assertFails(
    setDoc(doc(operatorDb, "promotions/promoB"), {
      merchantId: "storeB",
      status: "saved",
    }),
  );
});

test("notification history follows the selected store boundary", async () => {
  const db = env.authenticatedContext("operator1").firestore();
  await assertSucceeds(
    setDoc(doc(db, "notifications/storeA/customer_notifications/n1"), {
      message: "Alpha",
    }),
  );
  await assertFails(
    setDoc(doc(db, "notifications/storeB/customer_notifications/n2"), {
      message: "Beta",
    }),
  );
});

test("unauthenticated clients cannot read customer financial data", async () => {
  const db = env.unauthenticatedContext().firestore();
  // Transitional root-profile lookup stays available for released login code.
  await assertSucceeds(getDoc(doc(db, "users/storeA")));
  await assertFails(getDoc(doc(db, "users/storeA/customers/customerA")));
});

test("commerce orders are seller-scoped, admin-readable and server-written", async () => {
  const sellerDb = env.authenticatedContext("storeA").firestore();
  const operatorDb = env.authenticatedContext("operator1").firestore();
  const otherDb = env.authenticatedContext("operator2").firestore();
  const adminDb = env
    .authenticatedContext("spaza-admin", { spazaAdmin: true })
    .firestore();
  const publicDb = env.unauthenticatedContext().firestore();

  await assertSucceeds(getDoc(doc(sellerDb, "commerceOrders/orderA")));
  await assertSucceeds(getDoc(doc(operatorDb, "commerceOrders/orderA")));
  await assertSucceeds(
    getDocs(
      query(
        collection(operatorDb, "commerceOrders"),
        where("sellerId", "==", "storeA"),
      ),
    ),
  );
  await assertFails(getDoc(doc(otherDb, "commerceOrders/orderA")));
  await assertFails(
    getDocs(
      query(
        collection(otherDb, "commerceOrders"),
        where("sellerId", "==", "storeA"),
      ),
    ),
  );
  await assertSucceeds(getDoc(doc(adminDb, "commerceOrders/orderA")));
  await assertFails(getDoc(doc(publicDb, "commerceOrders/orderA")));
  await assertFails(
    updateDoc(doc(sellerDb, "commerceOrders/orderA"), { marginMinor: 999999 }),
  );
  await assertFails(
    setDoc(doc(sellerDb, "commerceOrders/forged"), {
      sellerId: "storeA",
      status: "delivered",
    }),
  );
});

test("released app keeps its authenticated transaction collection-group report", async () => {
  const legacyDb = env.authenticatedContext("storeA").firestore();
  const dueCredits = query(
    collectionGroup(legacyDb, "transactions"),
    where("status", "==", "DUE"),
  );
  const snapshot = await assertSucceeds(getDocs(dueCredits));
  assert.equal(snapshot.size, 2);

  const unauthenticatedDb = env.unauthenticatedContext().firestore();
  await assertFails(
    getDocs(
      query(
        collectionGroup(unauthenticatedDb, "transactions"),
        where("status", "==", "DUE"),
      ),
    ),
  );
});

test("released app keeps its legacy root collection query shapes", async () => {
  const publicDb = env.unauthenticatedContext().firestore();
  const phoneLookup = query(
    collection(publicDb, "users"),
    where("shopName", "==", "Alpha"),
  );
  const phoneLookupSnapshot = await assertSucceeds(getDocs(phoneLookup));
  assert.equal(phoneLookupSnapshot.size, 1);

  const legacyDb = env.authenticatedContext("storeA").firestore();
  await assertSucceeds(
    updateDoc(doc(legacyDb, "users/storeA"), { shopName: "Alpha Updated" }),
  );

  for (const [collectionName, ownerField] of [
    ["messagingTemplates", "userId"],
    ["promotions", "merchantId"],
    ["payoutRequests", "merchantId"],
    ["paymentReferences", "merchantId"],
  ]) {
    const ownedQuery = query(
      collection(legacyDb, collectionName),
      where(ownerField, "==", "storeA"),
    );
    const ownedSnapshot = await assertSucceeds(getDocs(ownedQuery));
    assert.equal(ownedSnapshot.size, 1, collectionName);
  }

  await assertSucceeds(
    setDoc(doc(legacyDb, "successfulWhatsAppNumbers/27820000000"), {
      reachable: true,
    }),
  );
  await assertFails(
    getDoc(doc(publicDb, "successfulWhatsAppNumbers/27820000000")),
  );
});

test("storage writes are store scoped while product reads stay public", async () => {
  const operatorStorage = env.authenticatedContext("operator1").storage();
  await assertSucceeds(
    uploadString(ref(operatorStorage, "products/storeA/bread.jpg"), "alpha"),
  );
  await assertFails(
    uploadString(ref(operatorStorage, "products/storeB/bread.jpg"), "beta"),
  );

  const publicStorage = env.unauthenticatedContext().storage();
  const bytes = await assertSucceeds(
    getBytes(ref(publicStorage, "products/storeA/bread.jpg")),
  );
  assert.equal(Buffer.from(bytes).toString(), "alpha");
  await assertFails(
    getBytes(ref(publicStorage, "profile_images/storeA/customer.jpg")),
  );

  await assertSucceeds(
    uploadString(
      ref(operatorStorage, "profile_images/storeA/customer.jpg"),
      "profile",
    ),
  );
  await assertSucceeds(
    uploadString(ref(operatorStorage, "whatsapp_media/legacy.jpg"), "media"),
  );
});

test("stock invoice images and PDFs are private and store scoped", async () => {
  const operatorStorage = env.authenticatedContext("operator1").storage();
  const ownInvoice = ref(
    operatorStorage,
    "stock_invoices/storeA/sale1/invoice.jpg",
  );
  await assertSucceeds(
    uploadString(ownInvoice, "private invoice", "raw", {
      contentType: "image/jpeg",
    }),
  );
  await assertSucceeds(getBytes(ownInvoice));
  await assertSucceeds(
    uploadString(
      ref(operatorStorage, "stock_invoices/storeA/sale1/invoice.png"),
      "png invoice",
      "raw",
      { contentType: "image/png" },
    ),
  );
  await assertSucceeds(
    uploadString(
      ref(operatorStorage, "stock_invoices/storeA/sale1/invoice.pdf"),
      "%PDF-1.7 invoice",
      "raw",
      { contentType: "application/pdf" },
    ),
  );

  await assertFails(
    uploadString(
      ref(operatorStorage, "stock_invoices/storeB/sale1/invoice.jpg"),
      "cross-store invoice",
      "raw",
      { contentType: "image/jpeg" },
    ),
  );
  await assertFails(
    getBytes(ref(operatorStorage, "stock_invoices/storeB/sale1/invoice.jpg")),
  );

  const publicStorage = env.unauthenticatedContext().storage();
  await assertFails(
    getBytes(ref(publicStorage, "stock_invoices/storeA/sale1/invoice.jpg")),
  );
  await assertFails(
    uploadString(
      ref(operatorStorage, "stock_invoices/storeA/sale1/invoice.txt"),
      "not an image",
      "raw",
      { contentType: "text/plain" },
    ),
  );
  await assertFails(
    uploadString(
      ref(operatorStorage, "stock_invoices/storeA/sale1/too-large.pdf"),
      "x".repeat(5 * 1024 * 1024 + 1),
      "raw",
      { contentType: "application/pdf" },
    ),
  );
});

test("catalogue status callable requires App Check and denies cross-store access", async () => {
  process.env.WHATSAPP_CATALOG_STATUS_CURSOR_SECRET =
    "local-emulator-catalogue-cursor-secret-32-bytes";
  const { getWhatsAppCatalogSyncStatusV2 } = await import(
    "../lib/whatsapp/catalogStatus.js"
  );
  const run = getWhatsAppCatalogSyncStatusV2.run;
  const app = { appId: "local-app-check" };

  await assert.rejects(
    run({ storeId: "storeA" }, { app }),
    (error) => error?.code === "unauthenticated",
  );
  await assert.rejects(
    run({ storeId: "storeA" }, { auth: { uid: "storeA", token: {} } }),
    (error) => error?.code === "failed-precondition",
  );
  await assert.rejects(
    run(
      { storeId: "storeA" },
      { auth: { uid: "operator2", token: {} }, app, rawRequest: {} },
    ),
    (error) => error?.code === "permission-denied",
  );
});

test("catalogue status callable paginates and detects catalogue drift", async () => {
  process.env.WHATSAPP_CATALOG_STATUS_CURSOR_SECRET =
    "local-emulator-catalogue-cursor-secret-32-bytes";
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(
        doc(db, "users/storeA"),
        {
          whatsappOrdering: {
            orderingUrl: "https://shop.example.test/store-a",
          },
        },
        { merge: true },
      ),
      ...["a", "b", "c"].map((id) =>
        setDoc(doc(db, `users/storeA/products/${id}`), {
          name: `Product ${id}`,
          sellingPrice: 10,
          image: `https://cdn.example.test/${id}.jpg`,
          whatsappListed: true,
        }),
      ),
    ]);
  });
  const { getWhatsAppCatalogSyncStatusV2 } = await import(
    "../lib/whatsapp/catalogStatus.js"
  );
  const run = getWhatsAppCatalogSyncStatusV2.run;
  const context = {
    auth: { uid: "storeA", token: {} },
    app: { appId: "local-app-check" },
    rawRequest: {},
  };
  const first = await run({ storeId: "storeA", pageSize: 2 }, context);
  assert.deepEqual(
    first.products.map((product) => product.productId),
    ["a", "b"],
  );
  assert.equal(typeof first.nextPageToken, "string");
  assert.equal(first.retryPermitted, false);

  await assert.rejects(
    run(
      {
        storeId: "storeA",
        pageSize: 2,
        pageToken: `${first.nextPageToken.slice(0, -1)}x`,
      },
      context,
    ),
    (error) =>
      error?.code === "invalid-argument" &&
      error?.details?.reason === "INVALID_PAGE_TOKEN",
  );

  await env.withSecurityRulesDisabled(async (emulatorContext) => {
    await updateDoc(
      doc(emulatorContext.firestore(), "users/storeA/products/c"),
      { name: "Changed product c" },
    );
  });
  await assert.rejects(
    run(
      {
        storeId: "storeA",
        pageSize: 2,
        pageToken: first.nextPageToken,
      },
      context,
    ),
    (error) =>
      error?.code === "failed-precondition" &&
      error?.details?.reason === "CATALOG_CHANGED",
  );
});
