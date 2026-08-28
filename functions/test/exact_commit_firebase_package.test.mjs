import assert from "node:assert/strict";
import { execFile as nodeExecFile } from "node:child_process";
import { mkdtemp, readFile, realpath, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

import {
  ExactCommitFirebasePackageError,
  PINNED_LOCAL_PACKAGE_TOOLCHAIN,
  assertKernelReadOnlyMount,
  cleanupExactCommitFirebasePackage,
  exactCommitFirebasePackagePath,
  prepareExactCommitFirebasePackage,
  verifyExactCommitFirebasePackage,
} from "../scripts/exact-commit-firebase-package.mjs";

const execFile = promisify(nodeExecFile);
const repositoryRoot = path.resolve("..");

test("exact Git commit is rebuilt offline with a pinned production dependency closure", async () => {
  const { stdout } = await execFile("/usr/bin/git", [
    "-C",
    repositoryRoot,
    "rev-parse",
    "HEAD",
  ]);
  const expectedAppCommit = stdout.trim();
  let prepared;
  try {
    prepared = await prepareExactCommitFirebasePackage({
      repositoryRoot,
      expectedAppCommit,
      temporaryRoot: await realpath(os.tmpdir()),
    });
    assert.equal(prepared.expectedAppCommit, expectedAppCommit);
    assert.equal(prepared.builtFromExactCommit, true);
    assert.equal(prepared.offlineInstall, true);
    assert.equal(prepared.scriptsDisabledDuringInstall, true);
    assert.equal(prepared.productionDependenciesIncluded, true);
    assert.equal(prepared.authorizesProduction, false);
    assert.match(prepared.gitArchiveSha256, /^[a-f0-9]{64}$/);
    assert.match(prepared.generatedLibInventorySha256, /^[a-f0-9]{64}$/);
    assert.match(prepared.dependencyClosureSha256, /^[a-f0-9]{64}$/);
    assert.ok(prepared.dependencyFileCount > 100);
    assert.equal(
      (await verifyExactCommitFirebasePackage(prepared)).verified,
      true,
    );
    assert.match(
      await readFile(
        exactCommitFirebasePackagePath(prepared, "functions/lib/index.js"),
        "utf8",
      ),
      /sourceMappingURL|exports|export/,
    );
    assert.match(
      await readFile(
        exactCommitFirebasePackagePath(
          prepared,
          "functions/node_modules/firebase-functions/package.json",
        ),
        "utf8",
      ),
      /"name":\s*"firebase-functions"/,
    );

    await writeFile(
      exactCommitFirebasePackagePath(prepared, "functions/lib/index.js"),
      "mutated after preparation\n",
    );
    await assert.rejects(
      verifyExactCommitFirebasePackage(prepared),
      (error) =>
        error instanceof ExactCommitFirebasePackageError &&
        error.code === "EXACT_COMMIT_PACKAGE_CHANGED",
    );
  } finally {
    if (prepared) {
      await cleanupExactCommitFirebasePackage({
        packageDescriptor: prepared,
      });
    }
  }
});

test("kernel read-only proof requires EROFS rather than owner chmod", async () => {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "kernel-readonly-contract-")),
  );
  try {
    await assert.rejects(
      assertKernelReadOnlyMount(root),
      (error) =>
        error instanceof ExactCommitFirebasePackageError &&
        error.code === "KERNEL_READ_ONLY_MOUNT_WRITABLE",
    );
    const verified = await assertKernelReadOnlyMount(root, {
      writeFileImpl: async () => {
        const error = new Error("read-only file system");
        error.code = "EROFS";
        throw error;
      },
    });
    assert.deepEqual(verified, {
      kernelReadOnly: true,
      writeErrorCode: "EROFS",
    });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("provider image and local probe contract pins exact tools and audit-only evidence", async () => {
  assert.equal(PINNED_LOCAL_PACKAGE_TOOLCHAIN.firebase.version, "15.21.0");
  for (const tool of Object.values(PINNED_LOCAL_PACKAGE_TOOLCHAIN)) {
    assert.match(tool.sha256, /^[a-f0-9]{64}$/);
    assert.equal(path.isAbsolute(tool.path), true);
    assert.equal(path.isAbsolute(tool.realpath), true);
  }
  const source = await readFile(
    path.resolve("scripts/exact-commit-firebase-package.mjs"),
    "utf8",
  );
  assert.match(source, /"create",\s*"-quiet",\s*"-format",\s*"UDRO"/s);
  assert.match(source, /"attach",\s*"-quiet",\s*"-readonly"/s);
  assert.match(source, /error\?\.code === "EROFS"/);
  assert.match(source, /"ci",\s*"--offline",\s*"--ignore-scripts"/s);
  assert.match(source, /FIREBASE_FUNCTIONS_DISCOVERY_OUTPUT_PATH: "true"/);
  assert.match(source, /workspace\.projectId\.startsWith\("demo-"\)/);
  assert.match(source, /productionWriteAttempted: false/);
  assert.match(source, /authorizesProduction: false/);
});
