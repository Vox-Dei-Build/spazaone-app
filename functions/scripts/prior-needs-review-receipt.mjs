import { createHash } from "node:crypto";
import { constants as fsConstants } from "node:fs";
import { lstat, open, realpath } from "node:fs/promises";
import path from "node:path";

import {
  canonicalJson,
  canonicalSha256,
  validateProductionWriteReceipt,
} from "./production-write-receipt.mjs";

const SHA1 = /^[a-f0-9]{40}$/;
const SHA256 = /^[a-f0-9]{64}$/;
const MAX_RECEIPT_BYTES = 256 * 1024;
const SAFE_FILE_MODE = 0o600;
const OPERATION_BINDING_KEYS = Object.freeze([
  "lane",
  "selector",
  "sourceSha256",
  "configurationSha256",
  "candidateManifestSha256",
  "operationInputSha256",
]);
const CLAIM_KEYS = Object.freeze([
  "schemaVersion",
  "kind",
  "claimedAt",
  "priorReceiptSha256",
  "priorReceiptFileSha256",
  "priorReceiptPathSha256",
  "nextReceiptPathSha256",
  "actionAuthorizationSha256",
  "operationBindingSha256",
]);

const defaultFs = Object.freeze({ lstat, open, realpath });
const loadedReceipts = new WeakMap();

export class PriorNeedsReviewReceiptError extends Error {
  constructor(code, { cause } = {}) {
    super(code, cause === undefined ? undefined : { cause });
    this.name = "PriorNeedsReviewReceiptError";
    this.code = code;
    this.retryAllowed = false;
  }
}

function fail(code, details) {
  throw new PriorNeedsReviewReceiptError(code, details);
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function canonicalPath(value, label) {
  if (
    typeof value !== "string" ||
    !path.isAbsolute(value) ||
    path.resolve(value) !== value
  ) {
    fail(`${label}_INVALID`);
  }
  return value;
}

function plainObject(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function sameIdentity(left, right) {
  return left.dev === right.dev && left.ino === right.ino;
}

function expectedUid(value) {
  const uid = value ?? process.geteuid?.();
  if (!Number.isSafeInteger(uid) || uid < 0) {
    fail("PRIOR_NEEDS_REVIEW_OWNER_UNAVAILABLE");
  }
  return uid;
}

function safeReceiptStat(stat, uid) {
  return (
    stat.isFile() &&
    !stat.isSymbolicLink() &&
    stat.uid === uid &&
    stat.nlink === 1 &&
    (stat.mode & 0o777) === SAFE_FILE_MODE &&
    stat.size >= 2 &&
    stat.size <= MAX_RECEIPT_BYTES
  );
}

function safeParentStat(stat, uid) {
  return (
    stat.isDirectory() &&
    !stat.isSymbolicLink() &&
    stat.uid === uid &&
    (stat.mode & 0o700) === 0o700 &&
    (stat.mode & 0o022) === 0
  );
}

function operationBinding(operation) {
  if (!plainObject(operation)) fail("PRIOR_NEEDS_REVIEW_OPERATION_INVALID");
  const binding = {};
  for (const key of OPERATION_BINDING_KEYS) {
    const value = operation[key];
    if (
      (key.endsWith("Sha256") && !SHA256.test(String(value ?? ""))) ||
      (!key.endsWith("Sha256") &&
        (typeof value !== "string" || value.length < 1))
    ) {
      fail("PRIOR_NEEDS_REVIEW_OPERATION_INVALID");
    }
    binding[key] = value;
  }
  return binding;
}

function assertExpectedOperation(receipt, expectedOperation) {
  const actual = operationBinding(receipt.operation);
  const expected = operationBinding(expectedOperation);
  if (canonicalJson(actual) !== canonicalJson(expected)) {
    fail("PRIOR_NEEDS_REVIEW_OPERATION_MISMATCH");
  }
  return Object.freeze(actual);
}

function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}

export async function loadPriorNeedsReviewReceipt({
  receiptPath,
  expectedPriorReceiptSha256,
  expectedAppCommit,
  expectedOperation,
  fsImpl = defaultFs,
  ownerUid,
} = {}) {
  canonicalPath(receiptPath, "PRIOR_NEEDS_REVIEW_RECEIPT_PATH");
  if (
    !SHA256.test(String(expectedPriorReceiptSha256 ?? "")) ||
    !SHA1.test(String(expectedAppCommit ?? ""))
  ) {
    fail("PRIOR_NEEDS_REVIEW_EXPECTATION_INVALID");
  }
  const uid = expectedUid(ownerUid);
  let handle;
  let bytes;
  try {
    const before = await fsImpl.lstat(receiptPath);
    if (
      !safeReceiptStat(before, uid) ||
      (await fsImpl.realpath(receiptPath)) !== receiptPath
    ) {
      fail("PRIOR_NEEDS_REVIEW_RECEIPT_UNSAFE");
    }
    handle = await fsImpl.open(
      receiptPath,
      fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW,
    );
    const opened = await handle.stat();
    bytes = await handle.readFile();
    const after = await handle.stat();
    const pathAfter = await fsImpl.lstat(receiptPath);
    if (
      !safeReceiptStat(opened, uid) ||
      !safeReceiptStat(after, uid) ||
      !safeReceiptStat(pathAfter, uid) ||
      !sameIdentity(before, opened) ||
      !sameIdentity(before, after) ||
      !sameIdentity(before, pathAfter) ||
      opened.size !== before.size ||
      after.size !== before.size ||
      pathAfter.size !== before.size
    ) {
      fail("PRIOR_NEEDS_REVIEW_RECEIPT_CHANGED");
    }
    const receipt = JSON.parse(bytes.toString("utf8"));
    const canonicalBytes = Buffer.from(`${canonicalJson(receipt)}\n`, "utf8");
    try {
      if (!bytes.equals(canonicalBytes)) {
        fail("PRIOR_NEEDS_REVIEW_RECEIPT_NONCANONICAL");
      }
    } finally {
      canonicalBytes.fill(0);
    }
    validateProductionWriteReceipt(receipt);
    if (
      receipt.outcome !== "needs_review" ||
      receipt.kind !== "spazaone_catalog_full_reconciliation" ||
      receipt.remoteWriteAttempted !== true ||
      receipt.needsReview !== true ||
      receipt.retryAllowed !== false ||
      receipt.appCommit !== expectedAppCommit ||
      receipt.redactedReceiptSha256 !== expectedPriorReceiptSha256 ||
      !new Set(["direct_write", "reviewed_resume_write"]).has(
        receipt.lineage.mode,
      )
    ) {
      fail("PRIOR_NEEDS_REVIEW_RECEIPT_BINDING_INVALID");
    }
    const binding = assertExpectedOperation(receipt, expectedOperation);
    const snapshot = deepFreeze(structuredClone(receipt));
    const descriptor = Object.freeze({
      auditOnly: true,
      authorizesReviewedResume: false,
      trustedOriginVerified: false,
      priorReceiptSha256: receipt.redactedReceiptSha256,
      priorReceiptFileSha256: sha256(bytes),
      priorReceiptPathSha256: sha256(receiptPath),
      operationBindingSha256: canonicalSha256(binding),
      operation: binding,
      snapshot,
    });
    loadedReceipts.set(descriptor, {
      receiptPath,
      parentPath: path.dirname(receiptPath),
      uid,
      fsImpl,
      receiptIdentity: {
        dev: before.dev,
        ino: before.ino,
        size: before.size,
        mode: before.mode & 0o777,
      },
    });
    return descriptor;
  } catch (error) {
    if (error instanceof PriorNeedsReviewReceiptError) throw error;
    fail("PRIOR_NEEDS_REVIEW_RECEIPT_UNREADABLE", { cause: error });
  } finally {
    try {
      await handle?.close();
    } catch (_) {
      // Preserve the primary validation result.
    }
    bytes?.fill?.(0);
  }
}

async function revalidateLoadedReceipt(state, loadedReceipt) {
  let handle;
  let bytes;
  try {
    const pathStat = await state.fsImpl.lstat(state.receiptPath);
    if (
      !safeReceiptStat(pathStat, state.uid) ||
      pathStat.dev !== state.receiptIdentity.dev ||
      pathStat.ino !== state.receiptIdentity.ino ||
      pathStat.size !== state.receiptIdentity.size ||
      (pathStat.mode & 0o777) !== state.receiptIdentity.mode ||
      (await state.fsImpl.realpath(state.receiptPath)) !== state.receiptPath
    ) {
      fail("PRIOR_NEEDS_REVIEW_RECEIPT_CHANGED");
    }
    handle = await state.fsImpl.open(
      state.receiptPath,
      fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW,
    );
    const opened = await handle.stat();
    bytes = await handle.readFile();
    const after = await handle.stat();
    if (
      !safeReceiptStat(opened, state.uid) ||
      !safeReceiptStat(after, state.uid) ||
      !sameIdentity(pathStat, opened) ||
      !sameIdentity(pathStat, after) ||
      sha256(bytes) !== loadedReceipt.priorReceiptFileSha256
    ) {
      fail("PRIOR_NEEDS_REVIEW_RECEIPT_CHANGED");
    }
  } catch (error) {
    if (error instanceof PriorNeedsReviewReceiptError) throw error;
    fail("PRIOR_NEEDS_REVIEW_RECEIPT_CHANGED", { cause: error });
  } finally {
    try {
      await handle?.close();
    } catch (_) {
      // Preserve the primary validation result.
    }
    bytes?.fill?.(0);
  }
}

function claimPathFor(parentPath, priorReceiptSha256) {
  return path.join(
    parentPath,
    `.${priorReceiptSha256}.reviewed-resume-claim.json`,
  );
}

export async function claimPriorNeedsReviewReceipt(
  loadedReceipt,
  { nextReceiptPath, actionAuthorizationSha256, clock = () => new Date() } = {},
) {
  void loadedReceipt;
  void nextReceiptPath;
  void actionAuthorizationSha256;
  void clock;
  // This locally self-attested receipt is audit evidence only. A same-owner
  // claim can be deleted and reused, so reviewed-resume authority stays off.
  fail("PRIOR_NEEDS_REVIEW_RESUME_AUTHORITY_NOT_AUTHORIZED");

  const state = loadedReceipts.get(loadedReceipt);
  if (!state) fail("PRIOR_NEEDS_REVIEW_RECEIPT_NOT_LOADED");
  canonicalPath(nextReceiptPath, "PRIOR_NEEDS_REVIEW_NEXT_RECEIPT_PATH");
  if (
    !SHA256.test(String(actionAuthorizationSha256 ?? "")) ||
    nextReceiptPath === state.receiptPath
  ) {
    fail("PRIOR_NEEDS_REVIEW_CLAIM_BINDING_INVALID");
  }
  const claimedAt = clock().toISOString();
  if (!Number.isFinite(Date.parse(claimedAt))) {
    fail("PRIOR_NEEDS_REVIEW_CLAIM_TIME_INVALID");
  }
  const claimPath = claimPathFor(
    state.parentPath,
    loadedReceipt.priorReceiptSha256,
  );
  const claim = {
    schemaVersion: 1,
    kind: "spazaone_prior_needs_review_resume_claim",
    claimedAt,
    priorReceiptSha256: loadedReceipt.priorReceiptSha256,
    priorReceiptFileSha256: loadedReceipt.priorReceiptFileSha256,
    priorReceiptPathSha256: loadedReceipt.priorReceiptPathSha256,
    nextReceiptPathSha256: sha256(nextReceiptPath),
    actionAuthorizationSha256,
    operationBindingSha256: loadedReceipt.operationBindingSha256,
  };
  if (
    JSON.stringify(Object.keys(claim).sort()) !==
    JSON.stringify([...CLAIM_KEYS].sort())
  ) {
    fail("PRIOR_NEEDS_REVIEW_CLAIM_INVALID");
  }
  const bytes = Buffer.from(`${canonicalJson(claim)}\n`, "utf8");
  let handle;
  let parentHandle;
  try {
    await revalidateLoadedReceipt(state, loadedReceipt);
    const parentBefore = await state.fsImpl.lstat(state.parentPath);
    if (
      !safeParentStat(parentBefore, state.uid) ||
      (await state.fsImpl.realpath(state.parentPath)) !== state.parentPath
    ) {
      fail("PRIOR_NEEDS_REVIEW_CLAIM_PARENT_UNSAFE");
    }
    parentHandle = await state.fsImpl.open(
      state.parentPath,
      fsConstants.O_RDONLY | fsConstants.O_DIRECTORY | fsConstants.O_NOFOLLOW,
    );
    const parentOpened = await parentHandle.stat();
    if (
      !safeParentStat(parentOpened, state.uid) ||
      !sameIdentity(parentBefore, parentOpened)
    ) {
      fail("PRIOR_NEEDS_REVIEW_CLAIM_PARENT_UNSAFE");
    }
    try {
      handle = await state.fsImpl.open(
        claimPath,
        fsConstants.O_CREAT |
          fsConstants.O_EXCL |
          fsConstants.O_RDWR |
          fsConstants.O_NOFOLLOW,
        SAFE_FILE_MODE,
      );
    } catch (error) {
      if (error?.code === "EEXIST") {
        fail("PRIOR_NEEDS_REVIEW_RECEIPT_ALREADY_CLAIMED");
      }
      throw error;
    }
    await handle.writeFile(bytes);
    await handle.sync();
    await parentHandle.sync();
    const opened = await handle.stat();
    const pathStat = await state.fsImpl.lstat(claimPath);
    const parentAfter = await state.fsImpl.lstat(state.parentPath);
    const parentOpenedAfter = await parentHandle.stat();
    const stored = Buffer.alloc(bytes.length);
    const extra = Buffer.alloc(1);
    try {
      const { bytesRead } = await handle.read(stored, 0, stored.length, 0);
      const { bytesRead: extraBytesRead } = await handle.read(
        extra,
        0,
        1,
        bytes.length,
      );
      if (
        !safeReceiptStat(opened, state.uid) ||
        !safeReceiptStat(pathStat, state.uid) ||
        opened.size !== bytes.length ||
        pathStat.size !== bytes.length ||
        !sameIdentity(opened, pathStat) ||
        !sameIdentity(parentBefore, parentAfter) ||
        !sameIdentity(parentBefore, parentOpenedAfter) ||
        !safeParentStat(parentAfter, state.uid) ||
        !safeParentStat(parentOpenedAfter, state.uid) ||
        bytesRead !== bytes.length ||
        extraBytesRead !== 0 ||
        !stored.equals(bytes)
      ) {
        fail("PRIOR_NEEDS_REVIEW_CLAIM_PERSISTENCE_UNCERTAIN");
      }
    } finally {
      stored.fill(0);
      extra.fill(0);
    }
    loadedReceipts.delete(loadedReceipt);
    return Object.freeze({
      claimPath,
      claimSha256: sha256(bytes),
      priorReceiptSha256: loadedReceipt.priorReceiptSha256,
      nextReceiptPathSha256: claim.nextReceiptPathSha256,
      actionAuthorizationSha256,
      operationBindingSha256: claim.operationBindingSha256,
    });
  } catch (error) {
    if (error instanceof PriorNeedsReviewReceiptError) throw error;
    fail("PRIOR_NEEDS_REVIEW_CLAIM_PERSISTENCE_UNCERTAIN", { cause: error });
  } finally {
    try {
      await handle?.close();
    } catch (_) {
      // Preserve the primary result.
    }
    try {
      await parentHandle?.close();
    } catch (_) {
      // Preserve the primary result.
    }
    bytes.fill(0);
  }
}
