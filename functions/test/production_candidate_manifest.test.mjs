import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  chmod,
  mkdtemp,
  realpath,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  FROZEN_APP_MAIN_COMMIT,
  ProductionCandidateManifestError,
  canonicalProductionCandidateManifestBytes,
  loadAndValidateProductionCandidateManifest,
} from "../scripts/production-candidate-manifest.mjs";
import { nativeCatalogTargetConfigurationDigestSha256 } from "../scripts/whatsapp-catalog-production-target.mjs";

const appCommit = "c".repeat(40);
const gitTreeSha1 = "e".repeat(40);
const operation = Object.freeze({
  kind: "function_deployment",
  lane: "dark-new",
  selector: "functions:onMerchantProductCatalogChange",
  inputSha256: "4".repeat(64),
});

function manifest(overrides = {}) {
  return {
    schemaVersion: 1,
    kind: "spazaone_native_catalog_production_candidate",
    appCommit,
    governedMainCommit: FROZEN_APP_MAIN_COMMIT,
    gitTreeSha1,
    immutableTargetConfigurationSha256:
      nativeCatalogTargetConfigurationDigestSha256(),
    operation: { ...operation },
    receipts: {
      appBuildLintReceiptSha256: "1".repeat(64),
      appWhatsAppCatalogTestsReceiptSha256: "2".repeat(64),
      independentProductionReviewReceiptSha256: "3".repeat(64),
    },
    ...overrides,
  };
}

async function fixture(document = manifest()) {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "production-candidate-manifest-")),
  );
  const manifestPath = path.join(root, "candidate.json");
  const bytes = canonicalProductionCandidateManifestBytes(document);
  await writeFile(manifestPath, bytes, { mode: 0o600, flag: "wx" });
  await chmod(manifestPath, 0o600);
  return {
    root,
    manifestPath,
    expectedManifestSha256: createHash("sha256").update(bytes).digest("hex"),
  };
}

function expected(reference, overrides = {}) {
  return {
    manifestPath: reference.manifestPath,
    expectedManifestSha256: reference.expectedManifestSha256,
    expectedAppCommit: appCommit,
    expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
    expectedOperation: operation,
    resolveGitTree: async () => gitTreeSha1,
    ...overrides,
  };
}

test("candidate manifest canonically binds reviewed commit, tree, target, operation, and receipts", async () => {
  const reference = await fixture();
  try {
    const result = await loadAndValidateProductionCandidateManifest(
      expected(reference),
    );
    assert.equal(result.manifestSha256, reference.expectedManifestSha256);
    assert.equal(result.appCommit, appCommit);
    assert.equal(result.gitTreeSha1, gitTreeSha1);
    assert.deepEqual(result.operation, operation);
    assert.deepEqual(result.receiptNames, [
      "appBuildLintReceiptSha256",
      "appWhatsAppCatalogTestsReceiptSha256",
      "independentProductionReviewReceiptSha256",
    ]);
    assert.match(result.receiptSetSha256, /^[a-f0-9]{64}$/);
    assert.deepEqual(result.authenticatedManifest, manifest());
    assert.equal(Object.isFrozen(result.authenticatedManifest), true);
    assert.equal(Object.isFrozen(result.authenticatedManifest.operation), true);
    assert.equal(Object.isFrozen(result.authenticatedManifest.receipts), true);
    assert.throws(() => {
      result.authenticatedManifest.operation.lane = "existing-code";
    }, TypeError);
  } finally {
    await rm(reference.root, { recursive: true, force: true });
  }
});

test("candidate manifest rejects noncanonical bytes and every reviewed binding drift", async () => {
  const noncanonical = await fixture();
  try {
    await writeFile(
      noncanonical.manifestPath,
      `${JSON.stringify(manifest(), null, 2)}\n`,
      { mode: 0o600 },
    );
    const bytes = await (
      await import("node:fs/promises")
    ).readFile(noncanonical.manifestPath);
    await assert.rejects(
      loadAndValidateProductionCandidateManifest(
        expected(noncanonical, {
          expectedManifestSha256: createHash("sha256")
            .update(bytes)
            .digest("hex"),
        }),
      ),
      (error) =>
        error instanceof ProductionCandidateManifestError &&
        error.code === "PRODUCTION_CANDIDATE_MANIFEST_CHANGED",
    );
  } finally {
    await rm(noncanonical.root, { recursive: true, force: true });
  }

  for (const [label, document, overrides, code] of [
    [
      "operation",
      manifest(),
      { expectedOperation: { ...operation, lane: "existing-code" } },
      "PRODUCTION_CANDIDATE_MANIFEST_BINDING_INVALID",
    ],
    [
      "operation input",
      manifest(),
      { expectedOperation: { ...operation, inputSha256: "5".repeat(64) } },
      "PRODUCTION_CANDIDATE_MANIFEST_BINDING_INVALID",
    ],
    [
      "tree",
      manifest(),
      { resolveGitTree: async () => "f".repeat(40) },
      "PRODUCTION_CANDIDATE_GIT_TREE_MISMATCH",
    ],
    [
      "receipts",
      manifest({
        receipts: {
          appBuildLintReceiptSha256: "1".repeat(64),
          appWhatsAppCatalogTestsReceiptSha256: "1".repeat(64),
          independentProductionReviewReceiptSha256: "3".repeat(64),
        },
      }),
      {},
      "PRODUCTION_CANDIDATE_MANIFEST_BINDING_INVALID",
    ],
  ]) {
    const reference = await fixture(document);
    try {
      await assert.rejects(
        loadAndValidateProductionCandidateManifest(
          expected(reference, overrides),
        ),
        (error) =>
          error instanceof ProductionCandidateManifestError &&
          error.code === code,
        label,
      );
    } finally {
      await rm(reference.root, { recursive: true, force: true });
    }
  }
});

test("candidate manifest rejects unsafe path aliases and writable files", async () => {
  const linked = await fixture();
  try {
    const alias = path.join(linked.root, "candidate-alias.json");
    await symlink(linked.manifestPath, alias);
    await assert.rejects(
      loadAndValidateProductionCandidateManifest(
        expected(linked, { manifestPath: alias }),
      ),
      (error) =>
        error instanceof ProductionCandidateManifestError &&
        error.code === "PRODUCTION_CANDIDATE_MANIFEST_FILE_UNSAFE",
    );
  } finally {
    await rm(linked.root, { recursive: true, force: true });
  }

  const writable = await fixture();
  try {
    await chmod(writable.manifestPath, 0o620);
    await assert.rejects(
      loadAndValidateProductionCandidateManifest(expected(writable)),
      (error) =>
        error instanceof ProductionCandidateManifestError &&
        error.code === "PRODUCTION_CANDIDATE_MANIFEST_FILE_UNSAFE",
    );
  } finally {
    await rm(writable.root, { recursive: true, force: true });
  }
});
