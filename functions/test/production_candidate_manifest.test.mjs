import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmod,
  mkdtemp,
  readFile,
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
  createCanonicalProductionCandidateManifest,
  loadAndValidateProductionCandidateManifest,
} from "../scripts/production-candidate-manifest.mjs";
import { nativeCatalogTargetConfigurationDigestSha256 } from "../scripts/whatsapp-catalog-production-target.mjs";

const appCommit = "c".repeat(40);
const gitTreeSha1 = "e".repeat(40);
const creatorPath = path.resolve(
  "scripts/create-whatsapp-catalog-production-candidate.mjs",
);
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

test("candidate creator derives receipt and operation digests from exact owner-only files", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "production-candidate-creator-")),
  );
  const evidenceReceiptPaths = {
    appBuildLintReceiptSha256: path.join(root, "build-lint.json"),
    appWhatsAppCatalogTestsReceiptSha256: path.join(root, "catalog-tests.json"),
    independentProductionReviewReceiptSha256: path.join(root, "review.json"),
  };
  const operationInputBytes = Buffer.from("exact-operation-input\n", "utf8");
  const manifestPath = path.join(root, "candidate.json");
  try {
    const evidenceBytes = [
      Buffer.from('{"outcome":"verified","suite":"build-lint"}\n'),
      Buffer.from('{"outcome":"verified","suite":"catalog-tests"}\n'),
      Buffer.from('{"outcome":"verified","suite":"review"}\n'),
    ];
    await Promise.all(
      Object.values(evidenceReceiptPaths).map((receiptPath, index) =>
        writeFile(receiptPath, evidenceBytes[index], {
          flag: "wx",
          mode: 0o600,
        }),
      ),
    );
    const result = await createCanonicalProductionCandidateManifest({
      manifestPath,
      expectedAppCommit: appCommit,
      expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
      operation: {
        kind: operation.kind,
        lane: operation.lane,
        selector: operation.selector,
      },
      operationInputBytes,
      evidenceReceiptPaths,
      resolveAuthority: async () => appCommit,
      resolveGitTree: async () => gitTreeSha1,
    });
    const document = JSON.parse(await readFile(manifestPath, "utf8"));
    assert.equal(result.outcome, "created");
    assert.equal(result.remoteWriteAttempted, false);
    assert.equal(
      document.operation.inputSha256,
      createHash("sha256").update(operationInputBytes).digest("hex"),
    );
    for (const [index, name] of [
      "appBuildLintReceiptSha256",
      "appWhatsAppCatalogTestsReceiptSha256",
      "independentProductionReviewReceiptSha256",
    ].entries()) {
      assert.equal(
        document.receipts[name],
        createHash("sha256").update(evidenceBytes[index]).digest("hex"),
      );
    }
    await assert.rejects(
      createCanonicalProductionCandidateManifest({
        manifestPath,
        expectedAppCommit: appCommit,
        expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
        operation: {
          kind: operation.kind,
          lane: operation.lane,
          selector: operation.selector,
        },
        operationInputBytes,
        evidenceReceiptPaths,
        resolveAuthority: async () => appCommit,
        resolveGitTree: async () => gitTreeSha1,
      }),
      (error) =>
        error instanceof ProductionCandidateManifestError &&
        error.code === "PRODUCTION_CANDIDATE_OUTPUT_WRITE_FAILED",
    );
  } finally {
    operationInputBytes.fill(0);
    await rm(root, { recursive: true, force: true });
  }
});

test("candidate creator rejects caller digest self-attestation and unsafe evidence", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "production-candidate-unsafe-")),
  );
  const manifestPath = path.join(root, "candidate.json");
  const operationInputBytes = Buffer.from("input", "utf8");
  const evidenceReceiptPaths = {
    appBuildLintReceiptSha256: "1".repeat(64),
    appWhatsAppCatalogTestsReceiptSha256: "2".repeat(64),
    independentProductionReviewReceiptSha256: "3".repeat(64),
  };
  try {
    await assert.rejects(
      createCanonicalProductionCandidateManifest({
        manifestPath,
        expectedAppCommit: appCommit,
        expectedCurrentMainCommit: FROZEN_APP_MAIN_COMMIT,
        operation: {
          kind: operation.kind,
          lane: operation.lane,
          selector: operation.selector,
        },
        operationInputBytes,
        evidenceReceiptPaths,
        resolveAuthority: async () => appCommit,
        resolveGitTree: async () => gitTreeSha1,
      }),
      (error) =>
        error instanceof ProductionCandidateManifestError &&
        error.code === "PRODUCTION_CANDIDATE_EVIDENCE_PATH_INVALID",
    );
  } finally {
    operationInputBytes.fill(0);
    await rm(root, { recursive: true, force: true });
  }
});

test("candidate CLI rejects non-exact reconciliation input before authority access", () => {
  const commonArguments = [
    creatorPath,
    "--operation-kind",
    "full_reconciliation",
    "--lane",
    "full-reconciliation",
    "--expected-app-commit",
    appCommit,
    "--expected-current-main-commit",
    FROZEN_APP_MAIN_COMMIT,
    "--output-path",
    "/private/tmp/rejected-production-candidate.json",
    "--app-build-lint-receipt-path",
    "/private/tmp/build-lint-receipt.json",
    "--app-whatsapp-catalog-tests-receipt-path",
    "/private/tmp/catalog-tests-receipt.json",
    "--independent-production-review-receipt-path",
    "/private/tmp/review-receipt.json",
  ];
  const result = spawnSync(process.execPath, commonArguments, {
    cwd: path.resolve("."),
    encoding: "utf8",
    input:
      '{"pageSize":200,"pollMs":65000,"maxSteps":10000,"maxElapsedMs":86400000,"requestTimeoutMs":570000}\n',
  });
  assert.equal(result.status, 1);
  assert.equal(
    JSON.parse(result.stderr).code,
    "PRODUCTION_CANDIDATE_OPERATION_INPUT_INVALID",
  );
  assert.equal(result.stdout, "");
});
