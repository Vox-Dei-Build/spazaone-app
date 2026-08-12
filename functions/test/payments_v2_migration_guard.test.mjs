import assert from "node:assert/strict";
import test from "node:test";

import {
  validateMigrationOptions,
} from "../scripts/rehearse-payments-v2-migration.mjs";

test("payments migration is dry-run by default and requires a project", () => {
  assert.throws(() => validateMigrationOptions([]), /--project/);
  const options = validateMigrationOptions(
    ["--project", "demo-spazaone"],
    { FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080" },
  );
  assert.equal(options.execute, false);
  assert.equal(options.verify, false);
});

test("execute and verify require a stable run id", () => {
  assert.throws(
    () => validateMigrationOptions(
      ["--project", "spazaone-dev", "--execute"],
      {},
    ),
    /--run-id/,
  );
});

test("production apply fails without backup evidence and confirmation", () => {
  assert.throws(
    () => validateMigrationOptions([
      "--project", "pasella-ledger",
      "--execute",
      "--run-id", "payments-v2-001",
    ], {}),
    /backup evidence/i,
  );
});
