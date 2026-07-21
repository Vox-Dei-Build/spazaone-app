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
  env = await initializeTestEnvironment({
    projectId: "demo-spazaone-multistore",
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
      setDoc(doc(db, "stores/storeB/operators/operator1"), {
        role: "operator",
        status: "disabled",
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

test("active operator can use assigned store and disabled membership cannot", async () => {
  const db = env.authenticatedContext("operator1").firestore();
  await assertSucceeds(getDoc(doc(db, "users/storeA/customers/customerA")));
  await assertSucceeds(
    setDoc(doc(db, "users/storeA/sales/sale1"), { total: 100 }),
  );
  await assertFails(getDoc(doc(db, "users/storeB/customers/customerB")));
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
