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

import {
  PriorNeedsReviewReceiptError,
  claimPriorNeedsReviewReceipt,
  loadPriorNeedsReviewReceipt,
} from "../scripts/prior-needs-review-receipt.mjs";
import {
  appCommitSourceSha256,
  buildNeedsReviewProductionWriteReceipt,
  canonicalJson,
} from "../scripts/production-write-receipt.mjs";
import {
  FROZEN_APP_MAIN_COMMIT,
  canonicalProductionCandidateManifestBytes,
} from "../scripts/production-candidate-manifest.mjs";
import { nativeCatalogTargetConfigurationDigestSha256 } from "../scripts/whatsapp-catalog-production-target.mjs";

const appCommit = "c".repeat(40);
const lane = "full-reconciliation";
const selector = "functions:runWhatsAppCatalogFullReconciliationBotHttp";
const operationInputSha256 = "4".repeat(64);
const actionAuthorizationSha256 = "5".repeat(64);
const actionAuthorizationClaimSha256 = "6".repeat(64);

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function candidateManifest() {
  return {
    schemaVersion: 1,
    kind: "spazaone_native_catalog_production_candidate",
    appCommit,
    governedMainCommit: FROZEN_APP_MAIN_COMMIT,
    gitTreeSha1: "e".repeat(40),
    immutableTargetConfigurationSha256:
      nativeCatalogTargetConfigurationDigestSha256(),
    operation: {
      kind: "full_reconciliation",
      lane,
      selector,
      inputSha256: operationInputSha256,
    },
    receipts: {
      appBuildLintReceiptSha256: "1".repeat(64),
      appWhatsAppCatalogTestsReceiptSha256: "2".repeat(64),
      independentProductionReviewReceiptSha256: "3".repeat(64),
    },
  };
}

function priorReceipt() {
  const manifest = candidateManifest();
  return buildNeedsReviewProductionWriteReceipt({
    kind: "spazaone_catalog_full_reconciliation",
    outcome: "needs_review",
    actionStartedAt: "2026-08-29T07:00:00.000Z",
    dispatchStartedAt: "2026-08-29T07:00:01.000Z",
    actionCompletedAt: "2026-08-29T07:00:02.000Z",
    verifiedAt: "2026-08-29T07:00:02.000Z",
    appCommit,
    lane,
    selector,
    sourceSha256: appCommitSourceSha256(appCommit),
    configurationSha256: nativeCatalogTargetConfigurationDigestSha256(),
    candidateManifest: manifest,
    candidateManifestSha256: sha256(
      canonicalProductionCandidateManifestBytes(manifest),
    ),
    operationInputSha256,
    actionAuthorizationSha256,
    actionAuthorizationClaimSha256,
    commandExitZero: false,
    readbackStatus: "needs_review",
    cleanupStatus: "not_applicable",
    remoteEvidence: null,
    errorCode: "CATALOG_RECONCILIATION_NEEDS_REVIEW",
  });
}

function expectedOperation(receipt) {
  return {
    lane: receipt.operation.lane,
    selector: receipt.operation.selector,
    sourceSha256: receipt.operation.sourceSha256,
    configurationSha256: receipt.operation.configurationSha256,
    candidateManifestSha256: receipt.operation.candidateManifestSha256,
    operationInputSha256: receipt.operation.operationInputSha256,
  };
}

async function writePrior(root, receipt = priorReceipt(), options = {}) {
  const receiptPath = path.join(root, options.name ?? "prior.json");
  const bytes = Buffer.from(
    options.pretty
      ? `${JSON.stringify(receipt, null, 2)}\n`
      : `${canonicalJson(receipt)}\n`,
    "utf8",
  );
  await writeFile(receiptPath, bytes, {
    flag: "wx",
    mode: options.mode ?? 0o600,
  });
  return { receipt, receiptPath, bytes };
}

test("exact prior needs_review receipt loads as a frozen operation-bound snapshot", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "prior-needs-review-load-")),
  );
  try {
    const { receipt, receiptPath } = await writePrior(root);
    const loaded = await loadPriorNeedsReviewReceipt({
      receiptPath,
      expectedPriorReceiptSha256: receipt.redactedReceiptSha256,
      expectedAppCommit: appCommit,
      expectedOperation: expectedOperation(receipt),
    });
    assert.equal(loaded.priorReceiptSha256, receipt.redactedReceiptSha256);
    assert.match(loaded.priorReceiptFileSha256, /^[a-f0-9]{64}$/);
    assert.match(loaded.operationBindingSha256, /^[a-f0-9]{64}$/);
    assert.equal(Object.isFrozen(loaded), true);
    assert.equal(Object.isFrozen(loaded.snapshot), true);
    assert.equal(loaded.snapshot.outcome, "needs_review");
    assert.equal(loaded.auditOnly, true);
    assert.equal(loaded.authorizesReviewedResume, false);
    assert.equal(loaded.trustedOriginVerified, false);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("prior loader rejects wrong mode, hardlinks, symlinks, noncanonical bytes, digest, app, and operation", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "prior-needs-review-adversarial-")),
  );
  try {
    const unsafe = await writePrior(root, priorReceipt(), {
      name: "unsafe.json",
      mode: 0o644,
    });
    await assert.rejects(
      loadPriorNeedsReviewReceipt({
        receiptPath: unsafe.receiptPath,
        expectedPriorReceiptSha256: unsafe.receipt.redactedReceiptSha256,
        expectedAppCommit: appCommit,
        expectedOperation: expectedOperation(unsafe.receipt),
      }),
      (error) =>
        error instanceof PriorNeedsReviewReceiptError &&
        error.code === "PRIOR_NEEDS_REVIEW_RECEIPT_UNSAFE",
    );

    const canonical = await writePrior(root, priorReceipt(), {
      name: "canonical.json",
    });
    const hardlinkPath = path.join(root, "hardlink.json");
    await link(canonical.receiptPath, hardlinkPath);
    await assert.rejects(
      loadPriorNeedsReviewReceipt({
        receiptPath: canonical.receiptPath,
        expectedPriorReceiptSha256: canonical.receipt.redactedReceiptSha256,
        expectedAppCommit: appCommit,
        expectedOperation: expectedOperation(canonical.receipt),
      }),
      (error) =>
        error instanceof PriorNeedsReviewReceiptError &&
        error.code === "PRIOR_NEEDS_REVIEW_RECEIPT_UNSAFE",
    );
    await rm(hardlinkPath);

    const symlinkPath = path.join(root, "symlink.json");
    await symlink(canonical.receiptPath, symlinkPath);
    await assert.rejects(
      loadPriorNeedsReviewReceipt({
        receiptPath: symlinkPath,
        expectedPriorReceiptSha256: canonical.receipt.redactedReceiptSha256,
        expectedAppCommit: appCommit,
        expectedOperation: expectedOperation(canonical.receipt),
      }),
      (error) =>
        error instanceof PriorNeedsReviewReceiptError &&
        error.code === "PRIOR_NEEDS_REVIEW_RECEIPT_UNSAFE",
    );

    const pretty = await writePrior(root, priorReceipt(), {
      name: "pretty.json",
      pretty: true,
    });
    await assert.rejects(
      loadPriorNeedsReviewReceipt({
        receiptPath: pretty.receiptPath,
        expectedPriorReceiptSha256: pretty.receipt.redactedReceiptSha256,
        expectedAppCommit: appCommit,
        expectedOperation: expectedOperation(pretty.receipt),
      }),
      (error) =>
        error instanceof PriorNeedsReviewReceiptError &&
        error.code === "PRIOR_NEEDS_REVIEW_RECEIPT_NONCANONICAL",
    );

    for (const overrides of [
      { expectedPriorReceiptSha256: "f".repeat(64) },
      { expectedAppCommit: "d".repeat(40) },
      {
        expectedOperation: {
          ...expectedOperation(canonical.receipt),
          operationInputSha256: "9".repeat(64),
        },
      },
    ]) {
      await assert.rejects(
        loadPriorNeedsReviewReceipt({
          receiptPath: canonical.receiptPath,
          expectedPriorReceiptSha256: canonical.receipt.redactedReceiptSha256,
          expectedAppCommit: appCommit,
          expectedOperation: expectedOperation(canonical.receipt),
          ...overrides,
        }),
        (error) =>
          error instanceof PriorNeedsReviewReceiptError &&
          /PRIOR_NEEDS_REVIEW_/.test(error.code),
      );
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("same-owner claims never authorize a reviewed resume", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "prior-needs-review-claim-")),
  );
  try {
    const { receipt, receiptPath } = await writePrior(root);
    const load = () =>
      loadPriorNeedsReviewReceipt({
        receiptPath,
        expectedPriorReceiptSha256: receipt.redactedReceiptSha256,
        expectedAppCommit: appCommit,
        expectedOperation: expectedOperation(receipt),
      });
    const first = await load();
    const nextReceiptPath = path.join(root, "closure.json");
    await assert.rejects(
      claimPriorNeedsReviewReceipt(first, {
        nextReceiptPath,
        actionAuthorizationSha256: "a".repeat(64),
      }),
      (error) =>
        error instanceof PriorNeedsReviewReceiptError &&
        error.code === "PRIOR_NEEDS_REVIEW_RESUME_AUTHORITY_NOT_AUTHORIZED",
    );
    assert.deepEqual((await readdir(root)).sort(), ["prior.json"]);
  } finally {
    await chmod(root, 0o700).catch(() => {});
    await rm(root, { recursive: true, force: true });
  }
});

test("prior receipt replacement cannot bypass the reviewed-resume hard stop", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "prior-needs-review-toctou-")),
  );
  try {
    const { receipt, receiptPath, bytes } = await writePrior(root);
    const loaded = await loadPriorNeedsReviewReceipt({
      receiptPath,
      expectedPriorReceiptSha256: receipt.redactedReceiptSha256,
      expectedAppCommit: appCommit,
      expectedOperation: expectedOperation(receipt),
    });
    await rename(receiptPath, `${receiptPath}.moved`);
    await writeFile(receiptPath, bytes, { flag: "wx", mode: 0o600 });
    await assert.rejects(
      claimPriorNeedsReviewReceipt(loaded, {
        nextReceiptPath: path.join(root, "closure.json"),
        actionAuthorizationSha256: "a".repeat(64),
      }),
      (error) =>
        error instanceof PriorNeedsReviewReceiptError &&
        error.code === "PRIOR_NEEDS_REVIEW_RESUME_AUTHORITY_NOT_AUTHORIZED",
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
