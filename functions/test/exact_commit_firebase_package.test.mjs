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
  cleanupFirebaseProviderWorkspace,
  createFirebaseProductionSessionWorkspace,
  exactCommitFirebasePackagePath,
  firebaseProviderWorkspacePath,
  inspectFirebaseProviderWorkspace,
  mountExactCommitFirebasePackageReadOnly,
  prepareExactCommitFirebasePackage,
  verifyExactCommitFirebasePackage,
  verifyFirebaseProductionSessionWorkspace,
  verifyMountedExactCommitFirebasePackage,
} from "../scripts/exact-commit-firebase-package.mjs";

const execFile = promisify(nodeExecFile);
const repositoryRoot = path.resolve("..");

const skipPinnedMachineAttestation =
  process.env.SPAZAONE_SKIP_PINNED_MACHINE_ATTESTATION === "1";

test(
  "exact Git commit is rebuilt offline with a pinned production dependency closure",
  {
    skip: skipPinnedMachineAttestation
      ? "requires the registered production-governance Mac toolchain"
      : false,
  },
  async () => {
    const { stdout } = await execFile("/usr/bin/git", [
      "-C",
      repositoryRoot,
      "rev-parse",
      "HEAD",
    ]);
    const expectedAppCommit = stdout.trim();
    let prepared;
    let mounted;
    let workspace;
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
      assert.match(prepared.gitTreeSha1, /^[a-f0-9]{40}$/);
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

      const generatedPath = exactCommitFirebasePackagePath(
        prepared,
        "functions/lib/index.js",
      );
      const generatedBytes = await readFile(generatedPath);
      await writeFile(generatedPath, "mutated after preparation\n");
      await assert.rejects(
        verifyExactCommitFirebasePackage(prepared),
        (error) =>
          error instanceof ExactCommitFirebasePackageError &&
          error.code === "EXACT_COMMIT_PACKAGE_CHANGED",
      );
      await writeFile(generatedPath, generatedBytes);
      generatedBytes.fill(0);
      assert.equal(
        (await verifyExactCommitFirebasePackage(prepared)).verified,
        true,
      );

      mounted = await mountExactCommitFirebasePackageReadOnly(prepared);
      assert.equal(
        (await verifyMountedExactCommitFirebasePackage(mounted)).kernelReadOnly,
        true,
      );
      workspace = await createFirebaseProductionSessionWorkspace({
        mountedPackage: mounted,
        projectId: "pasella-ledger",
        lane: "firestore-rules",
        temporaryRoot: await realpath(os.tmpdir()),
      });
      const verifiedWorkspace =
        await verifyFirebaseProductionSessionWorkspace(workspace);
      assert.equal(verifiedWorkspace.sourceKernelReadOnly, true);
      assert.equal(verifiedWorkspace.providerInputKernelReadOnly, true);
      assert.equal(workspace.writableOverlay, false);
      assert.match(workspace.providerInputInventorySha256, /^[a-f0-9]{64}$/);
      const configPath = firebaseProviderWorkspacePath(workspace, "config");
      await assert.rejects(writeFile(configPath, "must not replace config\n"), {
        code: "EROFS",
      });
      const scratchPath = firebaseProviderWorkspacePath(workspace, "scratch");
      await writeFile(
        path.join(scratchPath, "provider.tmp"),
        "bounded scratch",
      );
      await assert.rejects(
        verifyFirebaseProductionSessionWorkspace(workspace),
        (error) => error.code === "FIREBASE_PRODUCTION_SESSION_SCRATCH_CHANGED",
      );
      const afterUse = await verifyFirebaseProductionSessionWorkspace(
        workspace,
        {
          allowScratchChanges: true,
        },
      );
      assert.equal(afterUse.providerScratchEntryCount, 1);
      assert.equal(
        (await inspectFirebaseProviderWorkspace(workspace))
          .providerScratchEntryCount,
        1,
      );
      await cleanupFirebaseProviderWorkspace(workspace);
      workspace = null;

      workspace = await createFirebaseProductionSessionWorkspace({
        mountedPackage: mounted,
        projectId: "pasella-ledger",
        lane: "dark-new",
        dotenvText: "SPAZAONE_ENVIRONMENT=production\n",
        temporaryRoot: await realpath(os.tmpdir()),
      });
      assert.equal(
        (await verifyFirebaseProductionSessionWorkspace(workspace))
          .providerInputKernelReadOnly,
        true,
      );
      const functionConfigPath = firebaseProviderWorkspacePath(
        workspace,
        "config",
      );
      const functionConfig = JSON.parse(
        await readFile(functionConfigPath, "utf8"),
      );
      assert.equal(functionConfig.functions.length, 1);
      assert.equal(
        functionConfig.functions[0].source,
        firebaseProviderWorkspacePath(workspace, "functions-source"),
      );
      assert.match(
        functionConfig.functions[0].configDir,
        /provider-input-readonly\/config$/,
      );
      await assert.rejects(
        writeFile(
          path.join(
            functionConfig.functions[0].configDir,
            ".env.pasella-ledger",
          ),
          "must not replace dotenv\n",
        ),
        { code: "EROFS" },
      );
      await cleanupFirebaseProviderWorkspace(workspace);
      workspace = null;

      workspace = await createFirebaseProductionSessionWorkspace({
        mountedPackage: mounted,
        projectId: "pasella-ledger",
        lane: "full-reconciliation",
        dotenvText: "",
        temporaryRoot: await realpath(os.tmpdir()),
      });
      const reconciliationConfig = JSON.parse(
        await readFile(
          firebaseProviderWorkspacePath(workspace, "config"),
          "utf8",
        ),
      );
      assert.equal(reconciliationConfig.functions.length, 1);
      assert.equal(
        reconciliationConfig.functions[0].source,
        firebaseProviderWorkspacePath(workspace, "functions-source"),
      );
      assert.equal(
        Object.hasOwn(reconciliationConfig.functions[0], "configDir"),
        false,
      );
      assert.equal(workspace.dotenvSha256, null);
      await assert.rejects(
        createFirebaseProductionSessionWorkspace({
          mountedPackage: mounted,
          projectId: "pasella-ledger",
          lane: "full-reconciliation",
          dotenvText: "SPAZAONE_ENVIRONMENT=production\n",
          temporaryRoot: await realpath(os.tmpdir()),
        }),
        (error) =>
          error instanceof ExactCommitFirebasePackageError &&
          error.code === "FIREBASE_PRODUCTION_SESSION_DOTENV_INVALID",
      );
    } finally {
      if (workspace) await cleanupFirebaseProviderWorkspace(workspace);
      if (prepared) {
        await cleanupExactCommitFirebasePackage({
          mountedPackage: mounted,
          packageDescriptor: prepared,
        });
      }
    }
  },
);

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
  assert.match(source, /createFirebaseProductionSessionWorkspace/);
  assert.match(source, /PRODUCTION_SESSION_LANES/);
  assert.match(source, /"full-reconciliation"/);
  assert.match(source, /const readOnlySourceLane/);
  assert.match(source, /source:\s*image\.functionsPath/);
  assert.match(source, /path\.join\(image\.mountRoot, "firestore\.rules"\)/);
  assert.match(
    source,
    /path\.join\(image\.mountRoot, "firestore\.indexes\.json"\)/,
  );
  assert.match(source, /verifyFirebaseProductionSessionWorkspace/);
  assert.match(source, /providerScratchInventorySha256/);
  assert.match(source, /FIREBASE_PRODUCTION_SESSION_SCRATCH_CHANGED/);
  assert.match(source, /productionWriteAttempted: false/);
  assert.match(source, /authorizesProduction: false/);
});
