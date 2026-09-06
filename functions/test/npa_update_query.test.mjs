import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

test("scheduled NPA repair queries only persisted contradictions", () => {
  const source = readFileSync(
    new URL(
      "../src/reports/scheduledTasks/updateNPAStatus.ts",
      import.meta.url,
    ),
    "utf8",
  );
  assert.match(
    source,
    /collectionGroup\("customers"\)[\s\S]*?\.where\("isNPA",\s*"==",\s*false\)[\s\S]*?\.where\("balance",\s*"<",\s*0\)[\s\S]*?\.orderBy\("balance",\s*"asc"\)/,
  );
  assert.match(
    source,
    /collectionGroup\("customers"\)[\s\S]*?\.where\("isNPA",\s*"==",\s*true\)[\s\S]*?\.where\("balance",\s*">=",\s*0\)[\s\S]*?\.orderBy\("balance",\s*"asc"\)/,
  );
  assert.match(
    source,
    /collectionGroup\("customers"\)[\s\S]*?\.where\("balance",\s*"<",\s*0\)[\s\S]*?\.orderBy\("balance",\s*"asc"\)[\s\S]*?\.limit\(LEGACY_NPA_AUDIT_BATCH_SIZE\)/,
  );
  assert.match(source, /const LEGACY_NPA_AUDIT_BATCH_SIZE = 100/);
  assert.match(source, /query = query\.startAfter\(cursor\)/);

  const indexes = JSON.parse(
    readFileSync(new URL("../../firestore.indexes.json", import.meta.url)),
  );
  const npaRepairIndex = indexes.indexes.find(
    (index) =>
      index.collectionGroup === "customers" &&
      index.queryScope === "COLLECTION_GROUP" &&
      JSON.stringify(index.fields) ===
        JSON.stringify([
          { fieldPath: "isNPA", order: "ASCENDING" },
          { fieldPath: "balance", order: "ASCENDING" },
          { fieldPath: "__name__", order: "ASCENDING" },
        ]),
  );
  assert.ok(npaRepairIndex);
});
