import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import admin from "firebase-admin";
import { updateNPAs } from "../lib/reports/scheduledTasks/updateNPAStatus.js";

const emulatorHost = String(process.env.FIRESTORE_EMULATOR_HOST ?? "");
const emulatorProject = String(
  process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "",
);
if (!emulatorHost || !emulatorProject.startsWith("demo-")) {
  throw new Error(
    "Refusing NPA integration test without a demo Firestore emulator.",
  );
}

const db = admin.firestore();

async function clear() {
  await Promise.all([
    db.recursiveDelete(db.collection("users")),
    db.recursiveDelete(db.collection("maintenanceState")),
  ]);
}

before(clear);
after(clear);

test("NPA repair prioritizes legacy debtors and revisits rows behind its cursor", async () => {
  const customers = db.collection("users/npa-test/customers");
  const writes = [
    customers.doc("correct-negative").set({ balance: -2000, isNPA: true }),
    customers.doc("wrong-negative").set({ balance: -1900, isNPA: false }),
    customers.doc("correct-settled").set({ balance: 0, isNPA: false }),
    customers.doc("wrong-settled").set({ balance: 20, isNPA: true }),
    customers.doc("zz-legacy-missing-flag").set({ balance: -1 }),
  ];
  for (let index = 0; index < 100; index += 1) {
    writes.push(
      customers.doc(`middle-correct-${index}`).set({
        balance: -1800 + index,
        isNPA: true,
      }),
    );
  }
  await Promise.all(writes);

  assert.deepEqual(await updateNPAs(), {
    scanned: 2,
    corrected: 2,
    legacyAudited: 100,
    legacyCorrected: 0,
  });
  assert.equal(
    (await customers.doc("wrong-negative").get()).get("isNPA"),
    true,
  );
  assert.equal(
    (await customers.doc("wrong-settled").get()).get("isNPA"),
    false,
  );
  assert.equal(
    (await customers.doc("zz-legacy-missing-flag").get()).get("isNPA"),
    undefined,
  );

  // This row sorts before the stored cursor. It is picked up on the next
  // bounded cycle rather than remaining missing indefinitely.
  await customers.doc("inserted-behind-cursor").set({ balance: -1950 });

  assert.deepEqual(await updateNPAs(), {
    scanned: 0,
    corrected: 0,
    legacyAudited: 3,
    legacyCorrected: 1,
  });
  assert.equal(
    (await customers.doc("zz-legacy-missing-flag").get()).get("isNPA"),
    true,
  );
  assert.equal(
    (await customers.doc("inserted-behind-cursor").get()).get("isNPA"),
    undefined,
  );

  await db
    .doc("maintenanceState/npaLegacyAudit")
    .set({ nextCycleAtMs: 0 }, { merge: true });

  assert.deepEqual(await updateNPAs(), {
    scanned: 0,
    corrected: 0,
    legacyAudited: 100,
    legacyCorrected: 1,
  });
  assert.equal(
    (await customers.doc("inserted-behind-cursor").get()).get("isNPA"),
    true,
  );
});
