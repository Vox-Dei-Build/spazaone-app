import { createHash } from "node:crypto";
import { constants as fsConstants } from "node:fs";
import { lstat, open, realpath } from "node:fs/promises";
import path from "node:path";

import {
  PRODUCTION_WRITE_AUTHORITY,
  PRODUCTION_WRITE_TARGET,
  canonicalJson,
  canonicalSha256,
} from "./production-write-receipt.mjs";

const SHA1 = /^[a-f0-9]{40}$/;
const SHA256 = /^[a-f0-9]{64}$/;
const MAX_AUTHORIZATION_BYTES = 64 * 1024;
const MAX_AUTHORIZATION_LIFETIME_MS = 10 * 60 * 1000;
const SAFE_FILE_MODE = 0o600;
const AUTHORIZATION_KEYS = Object.freeze([
  "schemaVersion",
  "kind",
  "decision",
  "issuedAt",
  "expiresAt",
  "authority",
  "target",
  "appCommit",
  "operation",
  "oneShot",
]);
const OPERATION_KEYS = Object.freeze([
  "kind",
  "lane",
  "selector",
  "sourceSha256",
  "configurationSha256",
  "candidateManifestSha256",
  "operationInputSha256",
]);
const ONE_SHOT_KEYS = Object.freeze([
  "authorizationId",
  "receiptPathSha256",
  "priorReceiptSha256",
  "intentBindingSha256",
  "singleUse",
]);

const defaultFs = Object.freeze({ lstat, open, realpath });
const loadedAuthorizations = new WeakMap();

export class ProductionActionAuthorizationError extends Error {
  constructor(code) {
    super(code);
    this.name = "ProductionActionAuthorizationError";
    this.code = code;
    this.retryAllowed = false;
  }
}

function fail(code) {
  throw new ProductionActionAuthorizationError(code);
}

function plainObject(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function exactKeys(value, expected, label) {
  if (!plainObject(value)) fail(`${label}_INVALID`);
  const actual = Object.keys(value).sort();
  const approved = [...expected].sort();
  if (
    actual.length !== approved.length ||
    actual.some((key, index) => key !== approved[index])
  ) {
    fail(`${label}_KEYSET_INVALID`);
  }
}

function exactObject(value, expected, label) {
  exactKeys(value, Object.keys(expected), label);
  for (const [key, expectedValue] of Object.entries(expected)) {
    if (value[key] !== expectedValue) fail(`${label}_BINDING_INVALID`);
  }
}

function absoluteCanonicalPath(value, label) {
  if (
    typeof value !== "string" ||
    !path.isAbsolute(value) ||
    path.resolve(value) !== value
  ) {
    fail(`${label}_INVALID`);
  }
  return value;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function sameIdentity(left, right) {
  return left.dev === right.dev && left.ino === right.ino;
}

function ownerUid() {
  const uid = process.geteuid?.();
  if (!Number.isSafeInteger(uid) || uid < 0) {
    fail("PRODUCTION_ACTION_AUTHORIZATION_OWNER_UNAVAILABLE");
  }
  return uid;
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

function operationBinding(input) {
  return {
    kind: input.kind,
    lane: input.lane,
    selector: input.selector,
    sourceSha256: input.sourceSha256,
    configurationSha256: input.configurationSha256,
    candidateManifestSha256: input.candidateManifestSha256,
    operationInputSha256: input.operationInputSha256,
  };
}

export function productionActionIntentBindingSha256({
  authorizationId,
  appCommit,
  operation,
  receiptPathSha256,
  priorReceiptSha256,
} = {}) {
  if (
    typeof authorizationId !== "string" ||
    !/^[a-f0-9]{32}$/.test(authorizationId) ||
    !SHA1.test(String(appCommit ?? "")) ||
    !plainObject(operation) ||
    !SHA256.test(String(receiptPathSha256 ?? "")) ||
    (priorReceiptSha256 !== null &&
      !SHA256.test(String(priorReceiptSha256 ?? "")))
  ) {
    fail("PRODUCTION_ACTION_AUTHORIZATION_INTENT_BINDING_INVALID");
  }
  exactKeys(
    operation,
    OPERATION_KEYS,
    "PRODUCTION_ACTION_AUTHORIZATION_OPERATION",
  );
  for (const key of OPERATION_KEYS.slice(3)) {
    if (!SHA256.test(String(operation[key] ?? ""))) {
      fail("PRODUCTION_ACTION_AUTHORIZATION_INTENT_BINDING_INVALID");
    }
  }
  if (
    !new Set([
      "spazaone_catalog_function_deployment",
      "spazaone_catalog_policy_deployment",
      "spazaone_catalog_full_reconciliation",
    ]).has(operation.kind) ||
    typeof operation.lane !== "string" ||
    !operation.lane ||
    typeof operation.selector !== "string" ||
    !operation.selector
  ) {
    fail("PRODUCTION_ACTION_AUTHORIZATION_INTENT_BINDING_INVALID");
  }
  return canonicalSha256({
    schemaVersion: 1,
    authorizationId,
    appCommit,
    operation,
    receiptPathSha256,
    priorReceiptSha256,
  });
}

/**
 * Structurally validates a caller-supplied action audit receipt. A local JSON
 * file and caller-supplied digest do not establish a trusted origin and never
 * authorize a production action. No authority issuer exists in this module.
 */
export function validateProductionActionAuthorization(
  document,
  {
    expectedAppCommit,
    expectedOperation,
    expectedReceiptPath,
    expectedPriorReceiptSha256 = null,
    clock = () => new Date(),
  } = {},
) {
  exactKeys(document, AUTHORIZATION_KEYS, "PRODUCTION_ACTION_AUTHORIZATION");
  exactObject(
    document.authority,
    PRODUCTION_WRITE_AUTHORITY,
    "PRODUCTION_ACTION_AUTHORIZATION_AUTHORITY",
  );
  exactObject(
    document.target,
    PRODUCTION_WRITE_TARGET,
    "PRODUCTION_ACTION_AUTHORIZATION_TARGET",
  );
  exactKeys(
    document.operation,
    OPERATION_KEYS,
    "PRODUCTION_ACTION_AUTHORIZATION_OPERATION",
  );
  exactKeys(
    expectedOperation,
    OPERATION_KEYS,
    "EXPECTED_PRODUCTION_ACTION_AUTHORIZATION_OPERATION",
  );
  exactKeys(
    document.oneShot,
    ONE_SHOT_KEYS,
    "PRODUCTION_ACTION_AUTHORIZATION_ONE_SHOT",
  );
  const receiptPath = absoluteCanonicalPath(
    expectedReceiptPath,
    "EXPECTED_PRODUCTION_ACTION_AUTHORIZATION_RECEIPT_PATH",
  );
  const issuedAtMs = Date.parse(document.issuedAt);
  const expiresAtMs = Date.parse(document.expiresAt);
  const nowMs = clock().getTime();
  const expectedReceiptPathSha256 = sha256(receiptPath);
  const expectedIntentBindingSha256 = productionActionIntentBindingSha256({
    authorizationId: document.oneShot.authorizationId,
    appCommit: document.appCommit,
    operation: document.operation,
    receiptPathSha256: document.oneShot.receiptPathSha256,
    priorReceiptSha256: document.oneShot.priorReceiptSha256,
  });
  if (
    document.schemaVersion !== 1 ||
    document.kind !== "spazaone_production_action_authorization" ||
    document.decision !== "authorized" ||
    !Number.isFinite(issuedAtMs) ||
    !Number.isFinite(expiresAtMs) ||
    !Number.isFinite(nowMs) ||
    issuedAtMs > nowMs ||
    nowMs >= expiresAtMs ||
    expiresAtMs - issuedAtMs < 1 ||
    expiresAtMs - issuedAtMs > MAX_AUTHORIZATION_LIFETIME_MS ||
    document.appCommit !== expectedAppCommit ||
    !SHA1.test(String(document.appCommit ?? "")) ||
    canonicalJson(document.operation) !== canonicalJson(expectedOperation) ||
    document.oneShot.singleUse !== true ||
    !/^[a-f0-9]{32}$/.test(String(document.oneShot.authorizationId ?? "")) ||
    document.oneShot.receiptPathSha256 !== expectedReceiptPathSha256 ||
    document.oneShot.priorReceiptSha256 !== expectedPriorReceiptSha256 ||
    document.oneShot.intentBindingSha256 !== expectedIntentBindingSha256
  ) {
    fail("PRODUCTION_ACTION_AUTHORIZATION_BINDING_INVALID");
  }
  return Object.freeze({
    auditOnly: true,
    authorizesProduction: false,
    trustedOriginVerified: false,
    authorizationId: document.oneShot.authorizationId,
    expiresAt: document.expiresAt,
    intentBindingSha256: document.oneShot.intentBindingSha256,
    receiptPathSha256: document.oneShot.receiptPathSha256,
    priorReceiptSha256: document.oneShot.priorReceiptSha256,
    operation: Object.freeze(operationBinding(document.operation)),
  });
}

export async function loadProductionActionAuthorization({
  authorizationPath,
  expectedAuthorizationReceiptSha256,
  expectedAppCommit,
  expectedOperation,
  expectedReceiptPath,
  expectedPriorReceiptSha256 = null,
  clock,
  fsImpl = defaultFs,
} = {}) {
  absoluteCanonicalPath(
    authorizationPath,
    "PRODUCTION_ACTION_AUTHORIZATION_PATH",
  );
  if (!SHA256.test(String(expectedAuthorizationReceiptSha256 ?? ""))) {
    fail("PRODUCTION_ACTION_AUTHORIZATION_DIGEST_INVALID");
  }
  let handle;
  let bytes;
  try {
    const before = await fsImpl.lstat(authorizationPath);
    if (
      !before.isFile() ||
      before.isSymbolicLink() ||
      before.nlink !== 1 ||
      before.size < 2 ||
      before.size > MAX_AUTHORIZATION_BYTES ||
      (before.mode & 0o777) !== 0o600 ||
      (typeof process.geteuid === "function" &&
        before.uid !== process.geteuid()) ||
      (await fsImpl.realpath(authorizationPath)) !== authorizationPath
    ) {
      fail("PRODUCTION_ACTION_AUTHORIZATION_FILE_UNSAFE");
    }
    handle = await fsImpl.open(
      authorizationPath,
      fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW,
    );
    const opened = await handle.stat();
    bytes = await handle.readFile();
    const after = await handle.stat();
    const pathAfter = await fsImpl.lstat(authorizationPath);
    const document = JSON.parse(bytes.toString("utf8"));
    const canonicalBytes = Buffer.from(`${canonicalJson(document)}\n`, "utf8");
    try {
      if (
        opened.dev !== before.dev ||
        opened.ino !== before.ino ||
        opened.size !== before.size ||
        opened.nlink !== 1 ||
        (opened.mode & 0o777) !== 0o600 ||
        after.dev !== before.dev ||
        after.ino !== before.ino ||
        after.size !== before.size ||
        after.nlink !== 1 ||
        pathAfter.dev !== before.dev ||
        pathAfter.ino !== before.ino ||
        pathAfter.size !== before.size ||
        pathAfter.nlink !== 1 ||
        !bytes.equals(canonicalBytes) ||
        sha256(bytes) !== expectedAuthorizationReceiptSha256
      ) {
        fail("PRODUCTION_ACTION_AUTHORIZATION_CHANGED");
      }
    } finally {
      canonicalBytes.fill(0);
    }
    const validated = validateProductionActionAuthorization(document, {
      expectedAppCommit,
      expectedOperation,
      expectedReceiptPath,
      expectedPriorReceiptSha256,
      clock,
    });
    const descriptor = Object.freeze({
      ...validated,
      authorizationReceiptSha256: expectedAuthorizationReceiptSha256,
    });
    loadedAuthorizations.set(descriptor, {
      authorizationPath,
      parentPath: path.dirname(expectedReceiptPath),
      expectedReceiptPath,
      fsImpl,
      uid: ownerUid(),
      authorizationReceiptSha256: expectedAuthorizationReceiptSha256,
      authorizationIdentity: {
        dev: before.dev,
        ino: before.ino,
        size: before.size,
        mode: before.mode & 0o777,
      },
    });
    return descriptor;
  } catch (error) {
    if (error instanceof ProductionActionAuthorizationError) throw error;
    fail("PRODUCTION_ACTION_AUTHORIZATION_UNREADABLE");
  } finally {
    try {
      await handle?.close();
    } catch (_) {
      // Preserve the primary validation result.
    }
    bytes?.fill?.(0);
  }
}

async function revalidateLoadedAuthorization(state) {
  let handle;
  let bytes;
  try {
    const pathStat = await state.fsImpl.lstat(state.authorizationPath);
    if (
      !pathStat.isFile() ||
      pathStat.isSymbolicLink() ||
      pathStat.uid !== state.uid ||
      pathStat.nlink !== 1 ||
      (pathStat.mode & 0o777) !== SAFE_FILE_MODE ||
      pathStat.dev !== state.authorizationIdentity.dev ||
      pathStat.ino !== state.authorizationIdentity.ino ||
      pathStat.size !== state.authorizationIdentity.size ||
      (await state.fsImpl.realpath(state.authorizationPath)) !==
        state.authorizationPath
    ) {
      fail("PRODUCTION_ACTION_AUTHORIZATION_CHANGED");
    }
    handle = await state.fsImpl.open(
      state.authorizationPath,
      fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW,
    );
    const opened = await handle.stat();
    bytes = await handle.readFile();
    const after = await handle.stat();
    if (
      !opened.isFile() ||
      !after.isFile() ||
      opened.uid !== state.uid ||
      after.uid !== state.uid ||
      opened.nlink !== 1 ||
      after.nlink !== 1 ||
      (opened.mode & 0o777) !== SAFE_FILE_MODE ||
      (after.mode & 0o777) !== SAFE_FILE_MODE ||
      !sameIdentity(pathStat, opened) ||
      !sameIdentity(pathStat, after) ||
      sha256(bytes) !== state.authorizationReceiptSha256
    ) {
      fail("PRODUCTION_ACTION_AUTHORIZATION_CHANGED");
    }
  } catch (error) {
    if (error instanceof ProductionActionAuthorizationError) throw error;
    fail("PRODUCTION_ACTION_AUTHORIZATION_CHANGED");
  } finally {
    try {
      await handle?.close();
    } catch (_) {
      // Preserve the primary result.
    }
    bytes?.fill?.(0);
  }
}

export async function claimProductionActionAuthorization(
  loadedAuthorization,
  { clock = () => new Date() } = {},
) {
  void loadedAuthorization;
  void clock;
  // A same-owner O_EXCL file can be deleted and replayed. It is not a durable
  // one-shot authority boundary. A reviewed same-process capability or an
  // independent signer is required before this can ever become actionable.
  fail("PRODUCTION_ACTION_TRUSTED_ORIGIN_NOT_AUTHORIZED");

  const state = loadedAuthorizations.get(loadedAuthorization);
  if (!state) fail("PRODUCTION_ACTION_AUTHORIZATION_NOT_LOADED");
  const claimedAt = clock().toISOString();
  if (
    !Number.isFinite(Date.parse(claimedAt)) ||
    Date.parse(claimedAt) >= Date.parse(loadedAuthorization.expiresAt)
  ) {
    fail("PRODUCTION_ACTION_AUTHORIZATION_EXPIRED");
  }
  const claimPath = path.join(
    state.parentPath,
    `.${loadedAuthorization.authorizationId}.production-action-claim.json`,
  );
  const claim = {
    schemaVersion: 1,
    kind: "spazaone_production_action_authorization_claim",
    claimedAt,
    authorizationId: loadedAuthorization.authorizationId,
    authorizationReceiptSha256: loadedAuthorization.authorizationReceiptSha256,
    authorizationPathSha256: sha256(state.authorizationPath),
    receiptPathSha256: loadedAuthorization.receiptPathSha256,
    intentBindingSha256: loadedAuthorization.intentBindingSha256,
    operationBindingSha256: canonicalSha256(loadedAuthorization.operation),
    singleUse: true,
  };
  const bytes = Buffer.from(`${canonicalJson(claim)}\n`, "utf8");
  let handle;
  let parentHandle;
  try {
    await revalidateLoadedAuthorization(state);
    const parentBefore = await state.fsImpl.lstat(state.parentPath);
    if (
      !safeParentStat(parentBefore, state.uid) ||
      (await state.fsImpl.realpath(state.parentPath)) !== state.parentPath
    ) {
      fail("PRODUCTION_ACTION_AUTHORIZATION_CLAIM_PARENT_UNSAFE");
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
      fail("PRODUCTION_ACTION_AUTHORIZATION_CLAIM_PARENT_UNSAFE");
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
        fail("PRODUCTION_ACTION_AUTHORIZATION_ALREADY_CLAIMED");
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
        !opened.isFile() ||
        opened.isSymbolicLink() ||
        opened.uid !== state.uid ||
        opened.nlink !== 1 ||
        (opened.mode & 0o777) !== SAFE_FILE_MODE ||
        opened.size !== bytes.length ||
        !pathStat.isFile() ||
        pathStat.isSymbolicLink() ||
        pathStat.uid !== state.uid ||
        pathStat.nlink !== 1 ||
        (pathStat.mode & 0o777) !== SAFE_FILE_MODE ||
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
        fail("PRODUCTION_ACTION_AUTHORIZATION_CLAIM_UNCERTAIN");
      }
    } finally {
      stored.fill(0);
      extra.fill(0);
    }
    loadedAuthorizations.delete(loadedAuthorization);
    return Object.freeze({
      claimPath,
      claimSha256: sha256(bytes),
      authorizationReceiptSha256:
        loadedAuthorization.authorizationReceiptSha256,
      intentBindingSha256: loadedAuthorization.intentBindingSha256,
      operationBindingSha256: claim.operationBindingSha256,
      receiptPathSha256: claim.receiptPathSha256,
    });
  } catch (error) {
    if (error instanceof ProductionActionAuthorizationError) throw error;
    fail("PRODUCTION_ACTION_AUTHORIZATION_CLAIM_UNCERTAIN");
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
