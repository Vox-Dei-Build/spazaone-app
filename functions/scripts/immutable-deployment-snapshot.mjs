import { createHash } from "node:crypto";
import { constants as fsConstants } from "node:fs";
import {
  chmod,
  lstat,
  mkdir,
  mkdtemp,
  open,
  readdir,
  realpath,
  rm,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { canonicalJson } from "./production-write-receipt.mjs";

const SHA256 = /^[a-f0-9]{64}$/;
const MAX_FILE_BYTES = 32 * 1024 * 1024;
const MAX_TOTAL_BYTES = 256 * 1024 * 1024;
const MUTABLE_FILE_MODE = 0o600;
const SEALED_FILE_MODE = 0o400;
const MUTABLE_DIRECTORY_MODE = 0o700;
const SEALED_DIRECTORY_MODE = 0o500;
const snapshots = new WeakMap();

export class ImmutableDeploymentSnapshotError extends Error {
  constructor(code, { cause } = {}) {
    super(code, cause === undefined ? undefined : { cause });
    this.name = "ImmutableDeploymentSnapshotError";
    this.code = code;
    this.retryAllowed = false;
  }
}

function fail(code, details) {
  throw new ImmutableDeploymentSnapshotError(code, details);
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function safeRelativePath(value) {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > 512 ||
    path.posix.isAbsolute(value) ||
    value.includes("\\") ||
    value
      .split("/")
      .some((segment) => !segment || segment === "." || segment === "..")
  ) {
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_PATH_INVALID");
  }
  return value;
}

function canonicalRoot(value) {
  if (
    typeof value !== "string" ||
    !path.isAbsolute(value) ||
    path.resolve(value) !== value
  ) {
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_ROOT_INVALID");
  }
  return value;
}

function expectedUid() {
  const uid = process.geteuid?.();
  if (!Number.isSafeInteger(uid) || uid < 0) {
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_OWNER_UNAVAILABLE");
  }
  return uid;
}

function sameIdentity(left, right) {
  return left.dev === right.dev && left.ino === right.ino;
}

async function inventory(rootPath) {
  const files = [];
  const directories = [];
  const visit = async (directory, relativeDirectory = "") => {
    const entries = await readdir(directory, { withFileTypes: true });
    entries.sort((left, right) => left.name.localeCompare(right.name));
    for (const entry of entries) {
      const relativePath = relativeDirectory
        ? `${relativeDirectory}/${entry.name}`
        : entry.name;
      if (entry.isSymbolicLink()) {
        fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_CHANGED");
      }
      if (entry.isDirectory()) {
        directories.push(relativePath);
        await visit(path.join(directory, entry.name), relativePath);
      } else if (entry.isFile()) {
        files.push(relativePath);
      } else {
        fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_CHANGED");
      }
    }
  };
  await visit(rootPath);
  return { files: files.sort(), directories: directories.sort() };
}

async function readExactSourceFile(sourcePath, expectedSha256) {
  let handle;
  let bytes;
  try {
    const before = await lstat(sourcePath);
    if (
      !before.isFile() ||
      before.isSymbolicLink() ||
      before.size < 0 ||
      before.size > MAX_FILE_BYTES
    ) {
      fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_SOURCE_UNSAFE");
    }
    handle = await open(
      sourcePath,
      fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW,
    );
    const opened = await handle.stat();
    bytes = await handle.readFile();
    const after = await handle.stat();
    const pathAfter = await lstat(sourcePath);
    if (
      !opened.isFile() ||
      !after.isFile() ||
      !pathAfter.isFile() ||
      !sameIdentity(before, opened) ||
      !sameIdentity(before, after) ||
      !sameIdentity(before, pathAfter) ||
      before.size !== opened.size ||
      before.size !== after.size ||
      before.size !== pathAfter.size ||
      !Buffer.isBuffer(bytes) ||
      sha256(bytes) !== expectedSha256
    ) {
      fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_SOURCE_CHANGED");
    }
    return Buffer.from(bytes);
  } catch (error) {
    if (error instanceof ImmutableDeploymentSnapshotError) throw error;
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_SOURCE_UNREADABLE", { cause: error });
  } finally {
    try {
      await handle?.close();
    } catch (_) {
      // Preserve the primary result.
    }
    bytes?.fill?.(0);
  }
}

async function verifyExactSnapshotFile(file, uid) {
  let handle;
  let bytes;
  try {
    const before = await lstat(file.path);
    handle = await open(
      file.path,
      fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW,
    );
    const opened = await handle.stat();
    bytes = await handle.readFile();
    const after = await handle.stat();
    const pathAfter = await lstat(file.path);
    if (
      !before.isFile() ||
      before.isSymbolicLink() ||
      before.uid !== uid ||
      before.nlink !== 1 ||
      (before.mode & 0o777) !== SEALED_FILE_MODE ||
      before.size !== file.size ||
      before.dev !== file.dev ||
      before.ino !== file.ino ||
      !opened.isFile() ||
      !after.isFile() ||
      !pathAfter.isFile() ||
      !sameIdentity(before, opened) ||
      !sameIdentity(before, after) ||
      !sameIdentity(before, pathAfter) ||
      opened.uid !== uid ||
      after.uid !== uid ||
      pathAfter.uid !== uid ||
      opened.nlink !== 1 ||
      after.nlink !== 1 ||
      pathAfter.nlink !== 1 ||
      (opened.mode & 0o777) !== SEALED_FILE_MODE ||
      (after.mode & 0o777) !== SEALED_FILE_MODE ||
      (pathAfter.mode & 0o777) !== SEALED_FILE_MODE ||
      opened.size !== file.size ||
      after.size !== file.size ||
      pathAfter.size !== file.size ||
      sha256(bytes) !== file.sha256
    ) {
      fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_CHANGED");
    }
  } catch (error) {
    if (error instanceof ImmutableDeploymentSnapshotError) throw error;
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_CHANGED", { cause: error });
  } finally {
    try {
      await handle?.close();
    } catch (_) {
      // Preserve the primary result.
    }
    bytes?.fill?.(0);
  }
}

async function makeParents(rootPath, relativePath, directories) {
  const segments = relativePath.split("/").slice(0, -1);
  let current = rootPath;
  for (const segment of segments) {
    current = path.join(current, segment);
    if (!directories.has(current)) {
      try {
        await mkdir(current, { mode: MUTABLE_DIRECTORY_MODE });
      } catch (error) {
        if (error?.code !== "EEXIST") throw error;
      }
      const stat = await lstat(current);
      if (
        !stat.isDirectory() ||
        stat.isSymbolicLink() ||
        stat.uid !== expectedUid() ||
        (stat.mode & 0o777) !== MUTABLE_DIRECTORY_MODE
      ) {
        fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_DIRECTORY_UNSAFE");
      }
      directories.add(current);
    }
  }
}

async function writeExactFile(targetPath, bytes) {
  let handle;
  try {
    handle = await open(
      targetPath,
      fsConstants.O_CREAT |
        fsConstants.O_EXCL |
        fsConstants.O_RDWR |
        fsConstants.O_NOFOLLOW,
      MUTABLE_FILE_MODE,
    );
    await handle.writeFile(bytes);
    await handle.sync();
    const stat = await handle.stat();
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
        !stat.isFile() ||
        stat.isSymbolicLink() ||
        stat.uid !== expectedUid() ||
        stat.nlink !== 1 ||
        (stat.mode & 0o777) !== MUTABLE_FILE_MODE ||
        stat.size !== bytes.length ||
        bytesRead !== bytes.length ||
        extraBytesRead !== 0 ||
        !stored.equals(bytes)
      ) {
        fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_WRITE_UNCERTAIN");
      }
    } finally {
      stored.fill(0);
      extra.fill(0);
    }
  } catch (error) {
    if (error instanceof ImmutableDeploymentSnapshotError) throw error;
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_WRITE_FAILED", { cause: error });
  } finally {
    try {
      await handle?.close();
    } catch (_) {
      // Preserve the primary result.
    }
  }
}

class ImmutableDeploymentSnapshotBuilder {
  #rootPath;
  #directories;
  #files = new Map();
  #totalBytes = 0;
  #sealed = false;

  constructor(rootPath) {
    this.#rootPath = rootPath;
    this.#directories = new Set([rootPath]);
  }

  get rootPath() {
    return this.#rootPath;
  }

  async addBytes({ relativePath, bytes: inputBytes, expectedSha256 }) {
    if (this.#sealed) fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_ALREADY_SEALED");
    const normalized = safeRelativePath(relativePath);
    if (
      this.#files.has(normalized) ||
      !SHA256.test(String(expectedSha256 ?? ""))
    ) {
      fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_FILE_BINDING_INVALID");
    }
    const bytes = Buffer.isBuffer(inputBytes)
      ? Buffer.from(inputBytes)
      : inputBytes instanceof Uint8Array
        ? Buffer.from(inputBytes)
        : null;
    if (
      !bytes ||
      bytes.length > MAX_FILE_BYTES ||
      this.#totalBytes + bytes.length > MAX_TOTAL_BYTES ||
      sha256(bytes) !== expectedSha256
    ) {
      bytes?.fill?.(0);
      fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_FILE_BINDING_INVALID");
    }
    try {
      await makeParents(this.#rootPath, normalized, this.#directories);
      const targetPath = path.join(this.#rootPath, ...normalized.split("/"));
      await writeExactFile(targetPath, bytes);
      const stat = await lstat(targetPath);
      this.#files.set(normalized, {
        relativePath: normalized,
        sha256: expectedSha256,
        size: bytes.length,
        path: targetPath,
        dev: stat.dev,
        ino: stat.ino,
      });
      this.#totalBytes += bytes.length;
      return this;
    } finally {
      bytes.fill(0);
    }
  }

  async addSourceFile({ relativePath, sourcePath, expectedSha256 }) {
    if (this.#sealed) fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_ALREADY_SEALED");
    if (
      typeof sourcePath !== "string" ||
      !path.isAbsolute(sourcePath) ||
      path.resolve(sourcePath) !== sourcePath ||
      !SHA256.test(String(expectedSha256 ?? ""))
    ) {
      fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_SOURCE_BINDING_INVALID");
    }
    const bytes = await readExactSourceFile(sourcePath, expectedSha256);
    try {
      return await this.addBytes({ relativePath, bytes, expectedSha256 });
    } finally {
      bytes.fill(0);
    }
  }

  async seal() {
    if (this.#sealed || this.#files.size < 1) {
      fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_SEAL_INVALID");
    }
    this.#sealed = true;
    for (const file of this.#files.values()) {
      await chmod(file.path, SEALED_FILE_MODE);
    }
    const orderedDirectories = [...this.#directories].sort(
      (left, right) => right.length - left.length,
    );
    for (const directory of orderedDirectories) {
      await chmod(directory, SEALED_DIRECTORY_MODE);
    }
    const evidence = [...this.#files.values()]
      .map(({ relativePath, sha256: digest, size }) => [
        relativePath,
        digest,
        size,
      ])
      .sort((left, right) => left[0].localeCompare(right[0]));
    const descriptor = Object.freeze({
      rootPath: this.#rootPath,
      fileCount: evidence.length,
      totalBytes: this.#totalBytes,
      inventorySha256: sha256(canonicalJson(evidence)),
      sealed: true,
    });
    const directoryEvidence = [];
    for (const directory of this.#directories) {
      const stat = await lstat(directory);
      directoryEvidence.push({
        path: directory,
        relativePath:
          directory === this.#rootPath
            ? ""
            : path
                .relative(this.#rootPath, directory)
                .split(path.sep)
                .join("/"),
        dev: stat.dev,
        ino: stat.ino,
      });
    }
    snapshots.set(descriptor, {
      rootPath: this.#rootPath,
      uid: expectedUid(),
      directories: directoryEvidence,
      files: [...this.#files.values()].map((value) => ({ ...value })),
      descriptor,
      cleaned: false,
    });
    await verifyImmutableDeploymentSnapshot(descriptor);
    return descriptor;
  }

  async discard() {
    if (this.#sealed) {
      fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_ALREADY_SEALED");
    }
    this.#sealed = true;
    try {
      await rm(this.#rootPath, { recursive: true, force: false });
      return Object.freeze({ removed: true, rootPath: this.#rootPath });
    } catch (error) {
      fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_CLEANUP_FAILED", { cause: error });
    }
  }
}

export async function createImmutableDeploymentSnapshotBuilder({
  temporaryRoot = os.tmpdir(),
} = {}) {
  canonicalRoot(temporaryRoot);
  let rootPath;
  try {
    rootPath = await realpath(
      await mkdtemp(path.join(temporaryRoot, "spazaone-deploy-snapshot-")),
    );
    await chmod(rootPath, MUTABLE_DIRECTORY_MODE);
    const stat = await lstat(rootPath);
    if (
      !stat.isDirectory() ||
      stat.isSymbolicLink() ||
      stat.uid !== expectedUid() ||
      (stat.mode & 0o777) !== MUTABLE_DIRECTORY_MODE
    ) {
      fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_ROOT_UNSAFE");
    }
    return new ImmutableDeploymentSnapshotBuilder(rootPath);
  } catch (error) {
    if (error instanceof ImmutableDeploymentSnapshotError) throw error;
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_CREATE_FAILED", { cause: error });
  }
}

export function immutableDeploymentSnapshotPath(snapshot, relativePath) {
  const state = snapshots.get(snapshot);
  if (!state || state.cleaned) {
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_NOT_ACTIVE");
  }
  const normalized = safeRelativePath(relativePath);
  if (!state.files.some((file) => file.relativePath === normalized)) {
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_PATH_NOT_AUTHENTICATED");
  }
  return path.join(state.rootPath, ...normalized.split("/"));
}

export async function verifyImmutableDeploymentSnapshot(snapshot) {
  const state = snapshots.get(snapshot);
  if (!state || state.cleaned) {
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_NOT_ACTIVE");
  }
  const rootStat = await lstat(state.rootPath);
  if (
    !rootStat.isDirectory() ||
    rootStat.isSymbolicLink() ||
    rootStat.uid !== state.uid ||
    (rootStat.mode & 0o777) !== SEALED_DIRECTORY_MODE ||
    (await realpath(state.rootPath)) !== state.rootPath
  ) {
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_CHANGED");
  }
  const evidence = [];
  for (const file of state.files) {
    await verifyExactSnapshotFile(file, state.uid);
    evidence.push([file.relativePath, file.sha256, file.size]);
  }
  evidence.sort((left, right) => left[0].localeCompare(right[0]));
  if (
    evidence.length !== snapshot.fileCount ||
    sha256(canonicalJson(evidence)) !== snapshot.inventorySha256
  ) {
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_CHANGED");
  }
  const actualInventory = await inventory(state.rootPath);
  const expectedFiles = state.files.map((file) => file.relativePath).sort();
  const expectedDirectories = state.directories
    .map((directory) => directory.relativePath)
    .filter(Boolean)
    .sort();
  if (
    canonicalJson(actualInventory.files) !== canonicalJson(expectedFiles) ||
    canonicalJson(actualInventory.directories) !==
      canonicalJson(expectedDirectories)
  ) {
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_CHANGED");
  }
  for (const directory of state.directories) {
    const stat = await lstat(directory.path);
    if (
      !stat.isDirectory() ||
      stat.isSymbolicLink() ||
      stat.uid !== state.uid ||
      (stat.mode & 0o777) !== SEALED_DIRECTORY_MODE ||
      stat.dev !== directory.dev ||
      stat.ino !== directory.ino
    ) {
      fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_CHANGED");
    }
  }
  return Object.freeze({
    verified: true,
    inventorySha256: snapshot.inventorySha256,
    fileCount: snapshot.fileCount,
    totalBytes: snapshot.totalBytes,
  });
}

export async function removeImmutableDeploymentSnapshot(snapshot) {
  const state = snapshots.get(snapshot);
  if (!state || state.cleaned) {
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_NOT_ACTIVE");
  }
  try {
    const directories = [...state.directories].sort(
      (left, right) => left.path.length - right.path.length,
    );
    for (const directory of directories) {
      await chmod(directory.path, MUTABLE_DIRECTORY_MODE);
    }
    for (const file of state.files) {
      await chmod(file.path, MUTABLE_FILE_MODE);
    }
    await rm(state.rootPath, { recursive: true, force: false });
    state.cleaned = true;
    snapshots.delete(snapshot);
    return Object.freeze({ removed: true, rootPath: state.rootPath });
  } catch (error) {
    fail("IMMUTABLE_DEPLOYMENT_SNAPSHOT_CLEANUP_FAILED", { cause: error });
  }
}
