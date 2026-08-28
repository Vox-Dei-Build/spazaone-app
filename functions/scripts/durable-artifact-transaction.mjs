import { randomUUID } from "node:crypto";
import { constants as fsConstants } from "node:fs";
import {
  link as fsLink,
  lstat as fsLstat,
  open as fsOpen,
  realpath as fsRealpath,
  unlink as fsUnlink,
} from "node:fs/promises";
import path from "node:path";

const INTENT_MAX_BYTES = 64 * 1024;
const ARTIFACT_MAX_BYTES = 16 * 1024 * 1024;
const SAFE_FILE_MODE = 0o600;
const EXCLUSIVE_READ_WRITE_FLAGS =
  fsConstants.O_CREAT |
  fsConstants.O_EXCL |
  fsConstants.O_RDWR |
  fsConstants.O_NOFOLLOW;

const defaultFs = Object.freeze({
  link: fsLink,
  lstat: fsLstat,
  open: fsOpen,
  realpath: fsRealpath,
  unlink: fsUnlink,
});

/**
 * This error describes storage certainty only. It does not attest to the
 * meaning, validity, or authority of the bytes being stored.
 */
export class DurableArtifactTransactionError extends Error {
  constructor(
    code,
    {
      targetMayExist = false,
      retryAllowed = true,
      needsReview = false,
      cause,
    } = {},
  ) {
    super(code, cause === undefined ? undefined : { cause });
    this.name = "DurableArtifactTransactionError";
    this.code = code;
    this.targetMayExist = targetMayExist;
    this.retryAllowed = retryAllowed;
    this.needsReview = needsReview;
  }
}

function fail(code, details) {
  throw new DurableArtifactTransactionError(code, details);
}

function snapshotBytes(value, label, maximumBytes) {
  let bytes;
  if (typeof value === "string") {
    bytes = Buffer.from(value, "utf8");
  } else if (Buffer.isBuffer(value) || value instanceof Uint8Array) {
    bytes = Buffer.from(value);
  } else {
    fail(`DURABLE_ARTIFACT_${label}_BYTES_INVALID`, {
      retryAllowed: false,
    });
  }
  if (bytes.length < 1 || bytes.length > maximumBytes) {
    bytes.fill(0);
    fail(`DURABLE_ARTIFACT_${label}_BYTES_INVALID`, {
      retryAllowed: false,
    });
  }
  return bytes;
}

function expectedOwnerUid(input) {
  const uid = input ?? process.getuid?.();
  if (!Number.isSafeInteger(uid) || uid < 0) {
    fail("DURABLE_ARTIFACT_OWNER_UNAVAILABLE", { retryAllowed: false });
  }
  return uid;
}

function assertCanonicalTarget(targetPath) {
  const basename =
    typeof targetPath === "string" ? path.basename(targetPath) : "";
  if (
    typeof targetPath !== "string" ||
    !path.isAbsolute(targetPath) ||
    path.resolve(targetPath) !== targetPath ||
    basename.length < 1 ||
    basename === "." ||
    basename === ".."
  ) {
    fail("DURABLE_ARTIFACT_TARGET_PATH_INVALID", { retryAllowed: false });
  }
}

function assertSafeNonce(nonce) {
  if (
    typeof nonce !== "string" ||
    !/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/.test(nonce)
  ) {
    fail("DURABLE_ARTIFACT_NONCE_INVALID", { retryAllowed: false });
  }
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

function safeFileStat(stat, uid, size, nlink) {
  return (
    stat.isFile() &&
    !stat.isSymbolicLink() &&
    stat.uid === uid &&
    (stat.mode & 0o777) === SAFE_FILE_MODE &&
    stat.size === size &&
    stat.nlink === nlink
  );
}

function sameIdentity(left, right) {
  return left.dev === right.dev && left.ino === right.ino;
}

async function pathMissing(fsImpl, pathname) {
  try {
    await fsImpl.lstat(pathname);
    return false;
  } catch (error) {
    if (error?.code === "ENOENT") return true;
    throw error;
  }
}

async function readExact(handle, expected) {
  const actual = Buffer.alloc(expected.length);
  const extra = Buffer.alloc(1);
  try {
    let offset = 0;
    while (offset < actual.length) {
      const { bytesRead } = await handle.read(
        actual,
        offset,
        actual.length - offset,
        offset,
      );
      if (bytesRead < 1) break;
      offset += bytesRead;
    }
    const { bytesRead: extraBytesRead } = await handle.read(
      extra,
      0,
      1,
      expected.length,
    );
    return (
      offset === expected.length &&
      extraBytesRead === 0 &&
      actual.equals(expected)
    );
  } finally {
    actual.fill(0);
    extra.fill(0);
  }
}

async function closeQuietly(handle) {
  try {
    await handle?.close();
  } catch (_) {
    // Preserve the primary result or error.
  }
}

function storageError(error, { linkAttempted = false } = {}) {
  const targetMayExist = linkAttempted || error?.targetMayExist === true;
  if (error instanceof DurableArtifactTransactionError) {
    return new DurableArtifactTransactionError(error.code, {
      targetMayExist,
      retryAllowed: false,
      needsReview: true,
      cause: error,
    });
  }
  return new DurableArtifactTransactionError(
    linkAttempted
      ? "DURABLE_ARTIFACT_PERSISTENCE_UNCERTAIN"
      : "DURABLE_ARTIFACT_PERSISTENCE_FAILED",
    {
      targetMayExist,
      retryAllowed: false,
      needsReview: true,
      cause: error,
    },
  );
}

class DurableArtifactTransaction {
  #fs;
  #targetPath;
  #parentPath;
  #intentPath;
  #stagingPath;
  #uid;
  #parentHandle;
  #parentIdentity;
  #intentHandle;
  #intentIdentity;
  #intentBytes;
  #state = "prepared";

  constructor(input) {
    this.#fs = input.fsImpl;
    this.#targetPath = input.targetPath;
    this.#parentPath = input.parentPath;
    this.#intentPath = input.intentPath;
    this.#stagingPath = input.stagingPath;
    this.#uid = input.uid;
    this.#parentHandle = input.parentHandle;
    this.#parentIdentity = input.parentIdentity;
    this.#intentHandle = input.intentHandle;
    this.#intentIdentity = input.intentIdentity;
    this.#intentBytes = input.intentBytes;
  }

  get targetPath() {
    return this.#targetPath;
  }

  get intentPath() {
    return this.#intentPath;
  }

  get state() {
    return this.#state;
  }

  async #assertParentIdentity() {
    const handleStat = await this.#parentHandle.stat();
    const pathStat = await this.#fs.lstat(this.#parentPath);
    const resolved = await this.#fs.realpath(this.#parentPath);
    if (
      resolved !== this.#parentPath ||
      !safeParentStat(handleStat, this.#uid) ||
      !safeParentStat(pathStat, this.#uid) ||
      !sameIdentity(handleStat, this.#parentIdentity) ||
      !sameIdentity(pathStat, this.#parentIdentity) ||
      (handleStat.mode & 0o777) !== (this.#parentIdentity.mode & 0o777) ||
      (pathStat.mode & 0o777) !== (this.#parentIdentity.mode & 0o777)
    ) {
      fail("DURABLE_ARTIFACT_PARENT_IDENTITY_CHANGED");
    }
  }

  async #assertHeldFile(pathname, handle, identity, bytes, nlink) {
    const handleStat = await handle.stat();
    const pathStat = await this.#fs.lstat(pathname);
    if (
      !safeFileStat(handleStat, this.#uid, bytes.length, nlink) ||
      !safeFileStat(pathStat, this.#uid, bytes.length, nlink) ||
      !sameIdentity(handleStat, identity) ||
      !sameIdentity(pathStat, identity) ||
      !(await readExact(handle, bytes))
    ) {
      fail("DURABLE_ARTIFACT_FILE_IDENTITY_CHANGED");
    }
  }

  async #safeUnlinkHeld(pathname, handle, identity, bytes, nlink) {
    await this.#assertHeldFile(pathname, handle, identity, bytes, nlink);
    await this.#fs.unlink(pathname);
  }

  async verifyReadyForDispatch() {
    if (this.#state !== "prepared") {
      fail("DURABLE_ARTIFACT_STATE_INVALID", { retryAllowed: false });
    }
    await this.#assertParentIdentity();
    await this.#assertHeldFile(
      this.#intentPath,
      this.#intentHandle,
      this.#intentIdentity,
      this.#intentBytes,
      1,
    );
    if (!(await pathMissing(this.#fs, this.#targetPath))) {
      fail("DURABLE_ARTIFACT_TARGET_EXISTS", { retryAllowed: false });
    }
    return Object.freeze({ ready: true, targetPath: this.#targetPath });
  }

  markDispatchStarted() {
    if (this.#state !== "prepared") {
      fail("DURABLE_ARTIFACT_STATE_INVALID", { retryAllowed: false });
    }
    this.#state = "dispatch_started";
  }

  async cancelBeforeDispatch() {
    if (this.#state !== "prepared") {
      fail("DURABLE_ARTIFACT_CANCELLATION_AFTER_DISPATCH_FORBIDDEN", {
        retryAllowed: false,
        needsReview: this.#state !== "cancelled",
      });
    }
    this.#state = "cancelling";
    try {
      await this.#assertParentIdentity();
      await this.#assertHeldFile(
        this.#intentPath,
        this.#intentHandle,
        this.#intentIdentity,
        this.#intentBytes,
        1,
      );
      await this.#safeUnlinkHeld(
        this.#intentPath,
        this.#intentHandle,
        this.#intentIdentity,
        this.#intentBytes,
        1,
      );
      await this.#parentHandle.sync();
      await this.#assertParentIdentity();
      if (!(await pathMissing(this.#fs, this.#intentPath))) {
        fail("DURABLE_ARTIFACT_CANCELLATION_UNCERTAIN", {
          retryAllowed: false,
        });
      }
      await this.#intentHandle.close();
      await this.#parentHandle.close();
      this.#intentBytes.fill(0);
      this.#state = "cancelled";
      return Object.freeze({ cancelled: true });
    } catch (error) {
      await closeQuietly(this.#intentHandle);
      await closeQuietly(this.#parentHandle);
      this.#intentBytes.fill(0);
      this.#state = "failed";
      if (error instanceof DurableArtifactTransactionError) throw error;
      throw new DurableArtifactTransactionError(
        "DURABLE_ARTIFACT_CANCELLATION_UNCERTAIN",
        { retryAllowed: false, cause: error },
      );
    }
  }

  async persistFinal(canonicalBytes) {
    if (this.#state !== "dispatch_started") {
      fail("DURABLE_ARTIFACT_DISPATCH_NOT_STARTED", {
        retryAllowed: false,
      });
    }
    let finalBytes;
    try {
      finalBytes = snapshotBytes(canonicalBytes, "FINAL", ARTIFACT_MAX_BYTES);
    } catch (error) {
      await closeQuietly(this.#intentHandle);
      await closeQuietly(this.#parentHandle);
      this.#intentBytes.fill(0);
      this.#state = "failed";
      throw storageError(error);
    }
    this.#state = "finalizing";

    let stagingHandle;
    let stagingIdentity;
    let targetHandle;
    let linkAttempted = false;
    try {
      await this.#assertParentIdentity();
      await this.#assertHeldFile(
        this.#intentPath,
        this.#intentHandle,
        this.#intentIdentity,
        this.#intentBytes,
        1,
      );
      if (!(await pathMissing(this.#fs, this.#targetPath))) {
        fail("DURABLE_ARTIFACT_TARGET_EXISTS", { targetMayExist: true });
      }

      stagingHandle = await this.#fs.open(
        this.#stagingPath,
        EXCLUSIVE_READ_WRITE_FLAGS,
        SAFE_FILE_MODE,
      );
      await stagingHandle.writeFile(finalBytes);
      await stagingHandle.chmod(SAFE_FILE_MODE);
      await stagingHandle.sync();
      stagingIdentity = await stagingHandle.stat();
      await this.#assertHeldFile(
        this.#stagingPath,
        stagingHandle,
        stagingIdentity,
        finalBytes,
        1,
      );
      await this.#assertParentIdentity();
      await this.#assertHeldFile(
        this.#intentPath,
        this.#intentHandle,
        this.#intentIdentity,
        this.#intentBytes,
        1,
      );
      if (!(await pathMissing(this.#fs, this.#targetPath))) {
        fail("DURABLE_ARTIFACT_TARGET_EXISTS", { targetMayExist: true });
      }

      linkAttempted = true;
      await this.#fs.link(this.#stagingPath, this.#targetPath);

      const linkedTargetStat = await this.#fs.lstat(this.#targetPath);
      if (
        !safeFileStat(linkedTargetStat, this.#uid, finalBytes.length, 2) ||
        !sameIdentity(linkedTargetStat, stagingIdentity)
      ) {
        fail("DURABLE_ARTIFACT_LINK_VERIFICATION_UNCERTAIN", {
          targetMayExist: true,
        });
      }
      await this.#assertHeldFile(
        this.#stagingPath,
        stagingHandle,
        stagingIdentity,
        finalBytes,
        2,
      );
      await this.#assertParentIdentity();
      await this.#parentHandle.sync();

      await this.#safeUnlinkHeld(
        this.#stagingPath,
        stagingHandle,
        stagingIdentity,
        finalBytes,
        2,
      );
      await this.#safeUnlinkHeld(
        this.#intentPath,
        this.#intentHandle,
        this.#intentIdentity,
        this.#intentBytes,
        1,
      );
      await this.#parentHandle.sync();

      targetHandle = await this.#fs.open(
        this.#targetPath,
        fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW,
      );
      const targetIdentity = await targetHandle.stat();
      const targetPathStat = await this.#fs.lstat(this.#targetPath);
      if (
        !safeFileStat(targetIdentity, this.#uid, finalBytes.length, 1) ||
        !safeFileStat(targetPathStat, this.#uid, finalBytes.length, 1) ||
        !sameIdentity(targetIdentity, stagingIdentity) ||
        !sameIdentity(targetPathStat, stagingIdentity) ||
        !(await readExact(targetHandle, finalBytes)) ||
        !(await pathMissing(this.#fs, this.#stagingPath)) ||
        !(await pathMissing(this.#fs, this.#intentPath))
      ) {
        fail("DURABLE_ARTIFACT_FINAL_VERIFICATION_UNCERTAIN", {
          targetMayExist: true,
        });
      }
      await this.#assertParentIdentity();

      const finalHandleStat = await targetHandle.stat();
      const finalPathStat = await this.#fs.lstat(this.#targetPath);
      if (
        !safeFileStat(finalHandleStat, this.#uid, finalBytes.length, 1) ||
        !safeFileStat(finalPathStat, this.#uid, finalBytes.length, 1) ||
        !sameIdentity(finalHandleStat, stagingIdentity) ||
        !sameIdentity(finalPathStat, stagingIdentity) ||
        !(await readExact(targetHandle, finalBytes))
      ) {
        fail("DURABLE_ARTIFACT_FINAL_VERIFICATION_UNCERTAIN", {
          targetMayExist: true,
        });
      }

      await targetHandle.close();
      targetHandle = undefined;
      await stagingHandle.close();
      stagingHandle = undefined;
      await this.#intentHandle.close();
      await this.#parentHandle.close();
      this.#intentBytes.fill(0);
      this.#state = "persisted";
      return Object.freeze({
        persisted: true,
        path: this.#targetPath,
        mode: "0600",
        bytes: finalBytes.length,
      });
    } catch (error) {
      await closeQuietly(targetHandle);
      await closeQuietly(stagingHandle);
      await closeQuietly(this.#intentHandle);
      await closeQuietly(this.#parentHandle);
      this.#intentBytes.fill(0);
      this.#state = "failed";
      throw storageError(error, { linkAttempted });
    } finally {
      finalBytes.fill(0);
    }
  }
}

/**
 * Creates a durable, redacted intent marker for an opaque artifact write.
 * The caller remains solely responsible for the semantics and authority of
 * both the intent and final bytes. This helper only provides storage safety.
 */
export async function createDurableArtifactTransaction({
  targetPath,
  redactedIntentBytes,
  ownerUid,
  fsImpl: fsOverrides,
  uuid = randomUUID,
}) {
  assertCanonicalTarget(targetPath);
  const uid = expectedOwnerUid(ownerUid);
  const fsImpl = Object.freeze({ ...defaultFs, ...fsOverrides });
  const parentPath = path.dirname(targetPath);
  const name = path.basename(targetPath);
  const nonce = uuid();
  assertSafeNonce(nonce);
  const intentPath = path.join(parentPath, `.${name}.intent-${nonce}`);
  const stagingPath = path.join(parentPath, `.${name}.stage-${nonce}`);
  const intentBytes = snapshotBytes(
    redactedIntentBytes,
    "INTENT",
    INTENT_MAX_BYTES,
  );

  let parentHandle;
  let parentIdentity;
  let intentHandle;
  let intentIdentity;
  let intentCreated = false;
  try {
    const parentPathStat = await fsImpl.lstat(parentPath);
    if (
      !safeParentStat(parentPathStat, uid) ||
      (await fsImpl.realpath(parentPath)) !== parentPath
    ) {
      fail("DURABLE_ARTIFACT_PARENT_UNSAFE", { retryAllowed: false });
    }
    if (!(await pathMissing(fsImpl, targetPath))) {
      fail("DURABLE_ARTIFACT_TARGET_EXISTS", { retryAllowed: false });
    }

    parentHandle = await fsImpl.open(
      parentPath,
      fsConstants.O_RDONLY |
        fsConstants.O_NOFOLLOW |
        (fsConstants.O_DIRECTORY ?? 0),
    );
    parentIdentity = await parentHandle.stat();
    if (
      !safeParentStat(parentIdentity, uid) ||
      !sameIdentity(parentIdentity, parentPathStat) ||
      parentIdentity.nlink !== parentPathStat.nlink ||
      (parentIdentity.mode & 0o777) !== (parentPathStat.mode & 0o777)
    ) {
      fail("DURABLE_ARTIFACT_PARENT_UNSAFE", { retryAllowed: false });
    }

    intentHandle = await fsImpl.open(
      intentPath,
      EXCLUSIVE_READ_WRITE_FLAGS,
      SAFE_FILE_MODE,
    );
    intentCreated = true;
    await intentHandle.writeFile(intentBytes);
    await intentHandle.chmod(SAFE_FILE_MODE);
    await intentHandle.sync();
    intentIdentity = await intentHandle.stat();
    const intentPathStat = await fsImpl.lstat(intentPath);
    if (
      !safeFileStat(intentIdentity, uid, intentBytes.length, 1) ||
      !safeFileStat(intentPathStat, uid, intentBytes.length, 1) ||
      !sameIdentity(intentIdentity, intentPathStat) ||
      !(await readExact(intentHandle, intentBytes))
    ) {
      fail("DURABLE_ARTIFACT_INTENT_VERIFICATION_FAILED", {
        retryAllowed: false,
      });
    }
    await parentHandle.sync();

    const transaction = new DurableArtifactTransaction({
      fsImpl,
      targetPath,
      parentPath,
      intentPath,
      stagingPath,
      uid,
      parentHandle,
      parentIdentity,
      intentHandle,
      intentIdentity,
      intentBytes,
    });
    await transaction.verifyReadyForDispatch();
    return transaction;
  } catch (error) {
    if (intentCreated) {
      try {
        const held = intentIdentity ?? (await intentHandle?.stat());
        const currentParent = await fsImpl.lstat(parentPath);
        const current = await fsImpl.lstat(intentPath);
        if (
          held !== undefined &&
          parentIdentity !== undefined &&
          sameIdentity(currentParent, parentIdentity) &&
          sameIdentity(current, held)
        ) {
          await fsImpl.unlink(intentPath);
          await parentHandle?.sync();
        }
      } catch (_) {
        // Do not replace the original creation error with cleanup uncertainty.
      }
    }
    await closeQuietly(intentHandle);
    await closeQuietly(parentHandle);
    intentBytes.fill(0);
    if (error instanceof DurableArtifactTransactionError) throw error;
    throw new DurableArtifactTransactionError(
      "DURABLE_ARTIFACT_INTENT_CREATION_FAILED",
      { retryAllowed: false, cause: error },
    );
  }
}
