import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  chmod,
  lstat,
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
  ImmutableDeploymentSnapshotError,
  createImmutableDeploymentSnapshotBuilder,
  immutableDeploymentSnapshotPath,
  removeImmutableDeploymentSnapshot,
  verifyImmutableDeploymentSnapshot,
} from "../scripts/immutable-deployment-snapshot.mjs";

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

test("snapshot seals exact function, rules, indexes, config, and dotenv bytes read-only", async () => {
  const temporaryRoot = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "immutable-snapshot-happy-")),
  );
  const sourcePath = path.join(temporaryRoot, "source.js");
  const sourceBytes = Buffer.from("export const value = 1;\n", "utf8");
  let snapshot;
  try {
    await writeFile(sourcePath, sourceBytes, { flag: "wx", mode: 0o600 });
    const builder = await createImmutableDeploymentSnapshotBuilder({
      temporaryRoot,
    });
    await builder.addSourceFile({
      relativePath: "functions/lib/index.js",
      sourcePath,
      expectedSha256: sha256(sourceBytes),
    });
    for (const [relativePath, text] of [
      ["firestore.rules", "rules_version = '2';\n"],
      ["firestore.indexes.json", '{"indexes":[],"fieldOverrides":[]}\n'],
      ["firebase.json", '{"functions":[]}\n'],
      ["config/.env.pasella-ledger", "SPAZAONE_ENVIRONMENT=production\n"],
    ]) {
      const bytes = Buffer.from(text, "utf8");
      await builder.addBytes({
        relativePath,
        bytes,
        expectedSha256: sha256(bytes),
      });
      bytes.fill(0);
    }
    snapshot = await builder.seal();
    assert.equal(snapshot.sealed, true);
    assert.equal(snapshot.fileCount, 5);
    assert.match(snapshot.inventorySha256, /^[a-f0-9]{64}$/);
    const verification = await verifyImmutableDeploymentSnapshot(snapshot);
    assert.deepEqual(verification, {
      verified: true,
      inventorySha256: snapshot.inventorySha256,
      fileCount: 5,
      totalBytes: snapshot.totalBytes,
    });

    const copiedSource = immutableDeploymentSnapshotPath(
      snapshot,
      "functions/lib/index.js",
    );
    assert.deepEqual(await readFile(copiedSource), sourceBytes);
    assert.equal((await lstat(copiedSource)).mode & 0o777, 0o400);
    assert.equal((await lstat(snapshot.rootPath)).mode & 0o777, 0o500);
  } finally {
    sourceBytes.fill(0);
    if (snapshot) await removeImmutableDeploymentSnapshot(snapshot);
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});

test("live source mutation after sealing cannot change dispatched snapshot bytes", async () => {
  const temporaryRoot = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "immutable-snapshot-live-drift-")),
  );
  const sourcePath = path.join(temporaryRoot, "source.js");
  const original = Buffer.from("reviewed bytes\n", "utf8");
  let snapshot;
  try {
    await writeFile(sourcePath, original, { flag: "wx", mode: 0o600 });
    const builder = await createImmutableDeploymentSnapshotBuilder({
      temporaryRoot,
    });
    await builder.addSourceFile({
      relativePath: "functions/source.js",
      sourcePath,
      expectedSha256: sha256(original),
    });
    snapshot = await builder.seal();
    const dispatchedPath = immutableDeploymentSnapshotPath(
      snapshot,
      "functions/source.js",
    );

    await writeFile(sourcePath, "mutated checkout bytes\n");
    assert.deepEqual(await readFile(dispatchedPath), original);
    await assert.rejects(writeFile(dispatchedPath, "mid-flight mutation\n"), {
      code: "EACCES",
    });
    assert.deepEqual(await readFile(dispatchedPath), original);
    assert.equal(
      (await verifyImmutableDeploymentSnapshot(snapshot)).verified,
      true,
    );
  } finally {
    original.fill(0);
    if (snapshot) await removeImmutableDeploymentSnapshot(snapshot);
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});

test("digest drift, symlink sources, duplicate paths, traversal, and extra-file tampering fail closed", async () => {
  const temporaryRoot = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "immutable-snapshot-adversarial-")),
  );
  const sourcePath = path.join(temporaryRoot, "source.txt");
  const symlinkPath = path.join(temporaryRoot, "source-link.txt");
  let snapshot;
  try {
    await writeFile(sourcePath, "source\n", { flag: "wx", mode: 0o600 });
    await symlink(sourcePath, symlinkPath);
    const wrongDigest = await createImmutableDeploymentSnapshotBuilder({
      temporaryRoot,
    });
    await assert.rejects(
      wrongDigest.addSourceFile({
        relativePath: "functions/source.txt",
        sourcePath,
        expectedSha256: "f".repeat(64),
      }),
      (error) =>
        error instanceof ImmutableDeploymentSnapshotError &&
        error.code === "IMMUTABLE_DEPLOYMENT_SNAPSHOT_SOURCE_CHANGED",
    );
    await assert.rejects(
      wrongDigest.addSourceFile({
        relativePath: "functions/source.txt",
        sourcePath: symlinkPath,
        expectedSha256: sha256("source\n"),
      }),
      (error) =>
        error instanceof ImmutableDeploymentSnapshotError &&
        error.code === "IMMUTABLE_DEPLOYMENT_SNAPSHOT_SOURCE_UNSAFE",
    );

    const builder = await createImmutableDeploymentSnapshotBuilder({
      temporaryRoot,
    });
    const bytes = Buffer.from("authenticated\n", "utf8");
    await builder.addBytes({
      relativePath: "functions/index.js",
      bytes,
      expectedSha256: sha256(bytes),
    });
    await assert.rejects(
      builder.addBytes({
        relativePath: "functions/index.js",
        bytes,
        expectedSha256: sha256(bytes),
      }),
      (error) =>
        error instanceof ImmutableDeploymentSnapshotError &&
        error.code === "IMMUTABLE_DEPLOYMENT_SNAPSHOT_FILE_BINDING_INVALID",
    );
    await assert.rejects(
      builder.addBytes({
        relativePath: "../escape",
        bytes,
        expectedSha256: sha256(bytes),
      }),
      (error) =>
        error instanceof ImmutableDeploymentSnapshotError &&
        error.code === "IMMUTABLE_DEPLOYMENT_SNAPSHOT_PATH_INVALID",
    );
    snapshot = await builder.seal();
    bytes.fill(0);

    await chmod(snapshot.rootPath, 0o700);
    const extraPath = path.join(snapshot.rootPath, "extra.txt");
    await writeFile(extraPath, "extra", { flag: "wx", mode: 0o400 });
    await chmod(snapshot.rootPath, 0o500);
    await assert.rejects(
      verifyImmutableDeploymentSnapshot(snapshot),
      (error) =>
        error instanceof ImmutableDeploymentSnapshotError &&
        error.code === "IMMUTABLE_DEPLOYMENT_SNAPSHOT_CHANGED",
    );
    await chmod(snapshot.rootPath, 0o700);
    await rm(extraPath);
    await chmod(snapshot.rootPath, 0o500);
  } finally {
    if (snapshot) await removeImmutableDeploymentSnapshot(snapshot);
    await rm(temporaryRoot, { recursive: true, force: true });
  }
});
