import assert from "node:assert/strict";
import test from "node:test";
import { validateDevelopmentBotCatalogOptions } from "../scripts/seed-development-bot-catalog.mjs";

test("development bot catalogue seed refuses production and implicit projects", () => {
  assert.throws(() => validateDevelopmentBotCatalogOptions([]));
  assert.throws(() =>
    validateDevelopmentBotCatalogOptions(["--project", "pasella-ledger"]),
  );
});

test("development bot catalogue seed is dry-run by default", () => {
  const options = validateDevelopmentBotCatalogOptions([
    "--project",
    "spazaone-dev",
  ]);
  assert.equal(options.execute, false);
  assert.equal(options.verify, false);
});

test("development bot catalogue writes require a stable run id", () => {
  assert.throws(() =>
    validateDevelopmentBotCatalogOptions([
      "--project",
      "spazaone-dev",
      "--execute",
    ]),
  );
  const options = validateDevelopmentBotCatalogOptions([
    "--project",
    "spazaone-dev",
    "--run-id",
    "whatsapp-ordering-v1",
    "--verify",
  ]);
  assert.equal(options.verify, true);
});
