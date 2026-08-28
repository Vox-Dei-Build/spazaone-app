import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  chmod,
  link,
  lstat,
  mkdtemp,
  readFile,
  readdir,
  realpath,
  rename,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import * as authorizationModule from "../scripts/production-action-authorization.mjs";
import {
  ProductionActionAuthorizationError,
  claimProductionActionAuthorization,
  loadProductionActionAuthorization,
  productionActionIntentBindingSha256,
  validateProductionActionAuthorization,
} from "../scripts/production-action-authorization.mjs";
import {
  PRODUCTION_WRITE_AUTHORITY,
  PRODUCTION_WRITE_TARGET,
  canonicalJson,
} from "../scripts/production-write-receipt.mjs";
import { nativeCatalogTargetConfigurationDigestSha256 } from "../scripts/whatsapp-catalog-production-target.mjs";

const appCommit = "c".repeat(40);
const receiptPath = "/tmp/spazaone-action-receipt.json";
const clock = () => new Date("2026-08-29T08:04:00.000Z");
const operation = Object.freeze({
  kind: "spazaone_catalog_function_deployment",
  lane: "dark-new",
  selector: "functions:sendMerchantWhatsAppCatalogBotHttp",
  sourceSha256: "1".repeat(64),
  configurationSha256: nativeCatalogTargetConfigurationDigestSha256(),
  candidateManifestSha256: "2".repeat(64),
  operationInputSha256: "3".repeat(64),
});

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function authorization(overrides = {}) {
  const authorizationId = "a".repeat(32);
  const receiptPathSha256 = sha256(receiptPath);
  const priorReceiptSha256 = null;
  const oneShot = {
    authorizationId,
    receiptPathSha256,
    priorReceiptSha256,
    intentBindingSha256: productionActionIntentBindingSha256({
      authorizationId,
      appCommit,
      operation,
      receiptPathSha256,
      priorReceiptSha256,
    }),
    singleUse: true,
  };
  return {
    schemaVersion: 1,
    kind: "spazaone_production_action_authorization",
    decision: "authorized",
    issuedAt: "2026-08-29T08:00:00.000Z",
    expiresAt: "2026-08-29T08:10:00.000Z",
    authority: { ...PRODUCTION_WRITE_AUTHORITY },
    target: { ...PRODUCTION_WRITE_TARGET },
    appCommit,
    operation: { ...operation },
    oneShot,
    ...overrides,
  };
}

function canonicalBytes(document) {
  return Buffer.from(`${canonicalJson(document)}\n`, "utf8");
}

test("authorization contract has no local builder or issuer", () => {
  assert.equal(
    authorizationModule.buildProductionActionAuthorization,
    undefined,
  );
  assert.equal(
    authorizationModule.issueProductionActionAuthorization,
    undefined,
  );
  assert.equal(
    authorizationModule.persistProductionActionAuthorization,
    undefined,
  );
});

test("short-lived one-shot authorization binds the exact operation and durable receipt path", () => {
  const validated = validateProductionActionAuthorization(authorization(), {
    expectedAppCommit: appCommit,
    expectedOperation: operation,
    expectedReceiptPath: receiptPath,
    expectedPriorReceiptSha256: null,
    clock,
  });
  assert.equal(validated.authorizationId, "a".repeat(32));
  assert.equal(validated.receiptPathSha256, sha256(receiptPath));
  assert.equal(validated.priorReceiptSha256, null);
  assert.match(validated.intentBindingSha256, /^[a-f0-9]{64}$/);
  assert.equal(Object.isFrozen(validated), true);
  assert.equal(Object.isFrozen(validated.operation), true);
  assert.equal(validated.auditOnly, true);
  assert.equal(validated.authorizesProduction, false);
  assert.equal(validated.trustedOriginVerified, false);
});

test("authorization rejects expiry, excessive lifetime, path drift, operation drift, and target drift", () => {
  const cases = [
    [
      authorization({ expiresAt: "2026-08-29T08:04:00.000Z" }),
      { expectedReceiptPath: receiptPath },
    ],
    [
      authorization({ expiresAt: "2026-08-29T08:10:00.001Z" }),
      { expectedReceiptPath: receiptPath },
    ],
    [authorization(), { expectedReceiptPath: `${receiptPath}.other` }],
    [
      authorization(),
      {
        expectedReceiptPath: receiptPath,
        expectedOperation: { ...operation, lane: "configured-code" },
      },
    ],
    [
      authorization({
        target: { ...PRODUCTION_WRITE_TARGET, firebaseProjectId: "wrong" },
      }),
      { expectedReceiptPath: receiptPath },
    ],
  ];
  for (const [document, options] of cases) {
    assert.throws(
      () =>
        validateProductionActionAuthorization(document, {
          expectedAppCommit: appCommit,
          expectedOperation: operation,
          expectedReceiptPath: receiptPath,
          expectedPriorReceiptSha256: null,
          clock,
          ...options,
        }),
      (error) =>
        error instanceof ProductionActionAuthorizationError &&
        /PRODUCTION_ACTION_AUTHORIZATION_/.test(error.code),
    );
  }
  assert.throws(
    () =>
      validateProductionActionAuthorization(authorization(), {
        expectedAppCommit: appCommit,
        expectedOperation: operation,
        expectedReceiptPath: receiptPath,
        expectedPriorReceiptSha256: null,
        clock: () => new Date("invalid"),
      }),
    (error) =>
      error instanceof ProductionActionAuthorizationError &&
      error.code === "PRODUCTION_ACTION_AUTHORIZATION_BINDING_INVALID",
  );
});

test("secure loader requires canonical exact 0600 bytes, digest, owner, inode, and no links", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "action-authorization-")),
  );
  const document = authorization();
  const bytes = canonicalBytes(document);
  const authorizationPath = path.join(root, "authorization.json");
  try {
    await writeFile(authorizationPath, bytes, { flag: "wx", mode: 0o600 });
    const loaded = await loadProductionActionAuthorization({
      authorizationPath,
      expectedAuthorizationReceiptSha256: sha256(bytes),
      expectedAppCommit: appCommit,
      expectedOperation: operation,
      expectedReceiptPath: receiptPath,
      expectedPriorReceiptSha256: null,
      clock,
    });
    assert.equal(loaded.authorizationReceiptSha256, sha256(bytes));
    assert.equal(
      loaded.intentBindingSha256,
      document.oneShot.intentBindingSha256,
    );

    await chmod(authorizationPath, 0o644);
    await assert.rejects(
      loadProductionActionAuthorization({
        authorizationPath,
        expectedAuthorizationReceiptSha256: sha256(bytes),
        expectedAppCommit: appCommit,
        expectedOperation: operation,
        expectedReceiptPath: receiptPath,
        clock,
      }),
      (error) =>
        error instanceof ProductionActionAuthorizationError &&
        error.code === "PRODUCTION_ACTION_AUTHORIZATION_FILE_UNSAFE",
    );
    await chmod(authorizationPath, 0o600);

    const hardlinkPath = path.join(root, "hardlink.json");
    await link(authorizationPath, hardlinkPath);
    await assert.rejects(
      loadProductionActionAuthorization({
        authorizationPath,
        expectedAuthorizationReceiptSha256: sha256(bytes),
        expectedAppCommit: appCommit,
        expectedOperation: operation,
        expectedReceiptPath: receiptPath,
        clock,
      }),
      (error) =>
        error instanceof ProductionActionAuthorizationError &&
        error.code === "PRODUCTION_ACTION_AUTHORIZATION_FILE_UNSAFE",
    );
    await rm(hardlinkPath);

    const symlinkPath = path.join(root, "symlink.json");
    await symlink(authorizationPath, symlinkPath);
    await assert.rejects(
      loadProductionActionAuthorization({
        authorizationPath: symlinkPath,
        expectedAuthorizationReceiptSha256: sha256(bytes),
        expectedAppCommit: appCommit,
        expectedOperation: operation,
        expectedReceiptPath: receiptPath,
        clock,
      }),
      (error) =>
        error instanceof ProductionActionAuthorizationError &&
        error.code === "PRODUCTION_ACTION_AUTHORIZATION_FILE_UNSAFE",
    );

    assert.deepEqual(await readFile(authorizationPath), bytes);
  } finally {
    bytes.fill(0);
    await rm(root, { recursive: true, force: true });
  }
});

test("secure loader rejects semantically equal but non-canonical bytes and wrong digest", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "action-authorization-canonical-")),
  );
  const document = authorization();
  const pretty = Buffer.from(`${JSON.stringify(document, null, 2)}\n`, "utf8");
  const authorizationPath = path.join(root, "authorization.json");
  try {
    await writeFile(authorizationPath, pretty, { flag: "wx", mode: 0o600 });
    await assert.rejects(
      loadProductionActionAuthorization({
        authorizationPath,
        expectedAuthorizationReceiptSha256: sha256(pretty),
        expectedAppCommit: appCommit,
        expectedOperation: operation,
        expectedReceiptPath: receiptPath,
        clock,
      }),
      (error) =>
        error instanceof ProductionActionAuthorizationError &&
        error.code === "PRODUCTION_ACTION_AUTHORIZATION_CHANGED",
    );
    await assert.rejects(
      loadProductionActionAuthorization({
        authorizationPath,
        expectedAuthorizationReceiptSha256: "f".repeat(64),
        expectedAppCommit: appCommit,
        expectedOperation: operation,
        expectedReceiptPath: receiptPath,
        clock,
      }),
      (error) =>
        error instanceof ProductionActionAuthorizationError &&
        error.code === "PRODUCTION_ACTION_AUTHORIZATION_CHANGED",
    );
  } finally {
    pretty.fill(0);
    await rm(root, { recursive: true, force: true });
  }
});

test("same-owner action claims never become production authority", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "action-authorization-claim-")),
  );
  const outputPath = path.join(root, "production-receipt.json");
  const authorizationPath = path.join(root, "authorization.json");
  const base = authorization();
  base.oneShot.receiptPathSha256 = sha256(outputPath);
  base.oneShot.intentBindingSha256 = productionActionIntentBindingSha256({
    authorizationId: base.oneShot.authorizationId,
    appCommit,
    operation,
    receiptPathSha256: base.oneShot.receiptPathSha256,
    priorReceiptSha256: null,
  });
  const bytes = canonicalBytes(base);
  try {
    await writeFile(authorizationPath, bytes, { flag: "wx", mode: 0o600 });
    const load = () =>
      loadProductionActionAuthorization({
        authorizationPath,
        expectedAuthorizationReceiptSha256: sha256(bytes),
        expectedAppCommit: appCommit,
        expectedOperation: operation,
        expectedReceiptPath: outputPath,
        expectedPriorReceiptSha256: null,
        clock,
      });
    const first = await load();
    await assert.rejects(
      claimProductionActionAuthorization(first, {
        clock: () => new Date("2026-08-29T08:05:00.000Z"),
      }),
      (error) =>
        error instanceof ProductionActionAuthorizationError &&
        error.code === "PRODUCTION_ACTION_TRUSTED_ORIGIN_NOT_AUTHORIZED",
    );
    assert.deepEqual((await readdir(root)).sort(), ["authorization.json"]);
  } finally {
    bytes.fill(0);
    await rm(root, { recursive: true, force: true });
  }
});

test("audit receipt inode replacement cannot bypass the trusted-origin hard stop", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "action-authorization-toctou-")),
  );
  const outputPath = path.join(root, "production-receipt.json");
  const authorizationPath = path.join(root, "authorization.json");
  const movedPath = path.join(root, "authorization.moved.json");
  const document = authorization();
  document.oneShot.receiptPathSha256 = sha256(outputPath);
  document.oneShot.intentBindingSha256 = productionActionIntentBindingSha256({
    authorizationId: document.oneShot.authorizationId,
    appCommit,
    operation,
    receiptPathSha256: document.oneShot.receiptPathSha256,
    priorReceiptSha256: null,
  });
  const bytes = canonicalBytes(document);
  try {
    await writeFile(authorizationPath, bytes, { flag: "wx", mode: 0o600 });
    const loaded = await loadProductionActionAuthorization({
      authorizationPath,
      expectedAuthorizationReceiptSha256: sha256(bytes),
      expectedAppCommit: appCommit,
      expectedOperation: operation,
      expectedReceiptPath: outputPath,
      expectedPriorReceiptSha256: null,
      clock,
    });
    await rename(authorizationPath, movedPath);
    await writeFile(authorizationPath, bytes, { flag: "wx", mode: 0o600 });
    await assert.rejects(
      claimProductionActionAuthorization(loaded, {
        clock: () => new Date("2026-08-29T08:05:00.000Z"),
      }),
      (error) =>
        error instanceof ProductionActionAuthorizationError &&
        error.code === "PRODUCTION_ACTION_TRUSTED_ORIGIN_NOT_AUTHORIZED",
    );
  } finally {
    bytes.fill(0);
    await rm(root, { recursive: true, force: true });
  }
});
