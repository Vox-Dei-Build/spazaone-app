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

test("NPA repair reads and corrects only contradictory customer rows", async () => {
  const customers = db.collection("users/npa-test/customers");
  const writes = [
    customers.doc("correct-negative").set({ balance: -100, isNPA: true }),
    customers.doc("wrong-negative").set({ balance: -50, isNPA: false }),
    customers.doc("correct-settled").set({ balance: 0, isNPA: false }),
    customers.doc("wrong-settled").set({ balance: 20, isNPA: true }),
    customers.doc("zz-legacy-missing-flag").set({ balance: -10 }),
  ];
  for (let index = 0; index < 8; index += 1) {
    writes.push(
      customers.doc(`middle-correct-${index}`).set({
        balance: 0,
        isNPA: false,
      }),
    );
  }
  await Promise.all(writes);

  assert.deepEqual(await updateNPAs(), {
    scanned: 2,
    corrected: 2,
    legacyAudited: 10,
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

  assert.deepEqual(await updateNPAs(), {
    scanned: 0,
    corrected: 0,
    legacyAudited: 0,
    legacyCorrected: 0,
  });
});
