import assert from "node:assert/strict";
import { test } from "node:test";
import { validateOrderingLinkAuditOptions } from "../scripts/audit-ordering-links.mjs";

test("ordering-link audit requires an explicit development project", () => {
  assert.throws(
    () => validateOrderingLinkAuditOptions([]),
    /DEVELOPMENT_PROJECT_REQUIRED/,
  );
  assert.throws(
    () => validateOrderingLinkAuditOptions(["--project", "pasella-ledger"]),
    /DEVELOPMENT_PROJECT_REQUIRED/,
  );
});

test("ordering-link repair requires an auditable run id", () => {
  assert.throws(
    () =>
      validateOrderingLinkAuditOptions([
        "--project",
        "spazaone-dev",
        "--execute",
      ]),
    /RUN_ID_REQUIRED/,
  );
  const options = validateOrderingLinkAuditOptions([
    "--project",
    "spazaone-dev",
    "--execute",
    "--run-id",
    "ordering-link-repair-20260814-a",
  ]);
  assert.equal(options.execute, true);
  assert.equal(options.projectId, "spazaone-dev");
});

test("ordering-link audit is dry-run by default", () => {
  const options = validateOrderingLinkAuditOptions(["--project=spazaone-dev"]);
  assert.equal(options.execute, false);
});
