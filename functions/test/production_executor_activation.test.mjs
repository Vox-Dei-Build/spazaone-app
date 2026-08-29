import assert from "node:assert/strict";
import {
  lstat,
  mkdtemp,
  readFile,
  realpath,
  rm,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";
import { pathToFileURL } from "node:url";

import { FROZEN_APP_MAIN_COMMIT } from "../scripts/production-candidate-manifest.mjs";
import {
  PINNED_NODE_RUNTIME,
  canonicalSha256,
} from "../scripts/production-write-receipt.mjs";

const executorPath = path.resolve(
  "scripts/execute-whatsapp-catalog-production.mjs",
);
const launcherPath = path.resolve(
  "scripts/launch-whatsapp-catalog-production.sh",
);
const deploymentPath = path.resolve(
  "scripts/guard-whatsapp-catalog-functions-deploy.mjs",
);
const reconciliationPath = path.resolve(
  "scripts/run-whatsapp-catalog-full-reconciliation.mjs",
);
const packagePath = path.resolve("package.json");
const appCommit = "c".repeat(40);
const manifestSha256 = "d".repeat(64);

function directExecutorEnvironment() {
  return {
    HOME: "/Users/admin",
    USER: "admin",
    LOGNAME: "admin",
    TMPDIR: "/private/tmp",
    LANG: "C",
    LC_ALL: "C",
    PATH: "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
  };
}

async function withInstrumentedExecutor(callback) {
  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "production-executor-harness-")),
  );
  const harnessPath = path.join(root, "executor-harness.mjs");
  const exactPackageStubPath = path.join(root, "exact-package-stub.mjs");
  try {
    await writeFile(
      exactPackageStubPath,
      `
export const events = [];
let nextId = 0;
const digest = (character) => character.repeat(64);
export async function prepareExactCommitFirebasePackage({ expectedAppCommit }) {
  const descriptor = Object.freeze({
    id: ++nextId,
    expectedAppCommit,
    gitTreeSha1: "e".repeat(40),
    gitArchiveSha256: digest("1"),
    reviewedArchiveInventorySha256: digest("2"),
    packageInventorySha256: digest("3"),
    packageJsonSha256: digest("4"),
    packageLockSha256: digest("5"),
    dependencyClosureSha256: digest("6"),
    generatedLibInventorySha256: digest("7"),
  });
  events.push(["prepare", descriptor.id, expectedAppCommit]);
  return descriptor;
}
export async function mountExactCommitFirebasePackageReadOnly(descriptor) {
  const mounted = Object.freeze({ id: descriptor.id, descriptor });
  events.push(["mount", descriptor.id]);
  return mounted;
}
export async function verifyMountedExactCommitFirebasePackage(mounted) {
  events.push(["verify-mount", mounted.id]);
  return Object.freeze({ kernelReadOnly: true });
}
export async function createFirebaseProductionSessionWorkspace(input) {
  const workspace = Object.freeze({
    id: input.mountedPackage.id,
    lane: input.lane,
    configSha256: digest("8"),
    dotenvSha256: null,
  });
  events.push(["workspace", workspace.id, input.lane, input.dotenvText]);
  return workspace;
}
export async function verifyFirebaseProductionSessionWorkspace(workspace) {
  events.push(["verify-workspace", workspace.id]);
  return Object.freeze({
    sourcePackageInventorySha256: digest("3"),
    providerScratchInventorySha256: digest("9"),
    providerScratchEntryCount: 0,
    sourceKernelReadOnly: true,
    providerInputKernelReadOnly: true,
    providerInputInventorySha256: digest("a"),
  });
}
export async function inspectFirebaseProviderWorkspace(workspace) {
  events.push(["inspect-workspace", workspace.id]);
  return Object.freeze({
    providerScratchInventorySha256: digest("b"),
    providerScratchEntryCount: 2,
    providerScratchTotalBytes: 1_024,
  });
}
export async function cleanupFirebaseProviderWorkspace(workspace) {
  events.push(["cleanup-workspace", workspace.id]);
}
export async function cleanupExactCommitFirebasePackage({ packageDescriptor }) {
  events.push(["cleanup-package", packageDescriptor.id]);
}
export function firebaseProviderWorkspacePath(workspace, kind) {
  return "/private/tmp/executor-harness-" + workspace.id + "-" + kind;
}
export function mountedExactCommitFirebasePackagePath(mounted, relativePath) {
  return "/private/tmp/executor-harness-" + mounted.id + "/" + relativePath;
}
`,
      { flag: "wx", mode: 0o600 },
    );
    const scriptsRoot = path.dirname(executorPath);
    const source = (await readFile(executorPath, "utf8")).replace(
      /from "(\.\/[^"\n]+)"/g,
      (_, specifier) => {
        const target =
          specifier === "./exact-commit-firebase-package.mjs"
            ? exactPackageStubPath
            : path.resolve(scriptsRoot, specifier);
        return `from ${JSON.stringify(pathToFileURL(target).href)}`;
      },
    );
    await writeFile(
      harnessPath,
      `${source}
export {
  assertLiveSessionDispatchDeadline,
  authorizePreparedProductionLiveSession,
  consumeProductionLiveSessionCapability,
  disposeAuthorizedProductionLiveSession,
  disposeConsumedProductionLiveSession,
  disposePreparedProductionLiveSession,
  disposeRecoveryInspectionLiveSession,
  exactRecoveryReadback,
  extractActionAuthorizationArguments,
  mintFreshReconciliationContinuationCapability,
  prepareProductionLiveSession,
  recordRecoveryInspection,
};
`,
      { flag: "wx", mode: 0o600 },
    );
    const [executor, infrastructure] = await Promise.all([
      import(pathToFileURL(harnessPath).href),
      import(pathToFileURL(exactPackageStubPath).href),
    ]);
    return await callback(executor, infrastructure);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

function lifecycleFixture() {
  const operation = Object.freeze({
    kind: "full_reconciliation",
    lane: "full-reconciliation",
    selector: "functions:runWhatsAppCatalogFullReconciliationBotHttp",
    inputSha256: "f".repeat(64),
  });
  const context = {
    expectedAppCommit: "a".repeat(40),
    expectedCurrentMainCommit: "b".repeat(40),
    expectedCandidateManifestSha256: "c".repeat(64),
    kind: "spazaone_catalog_full_reconciliation",
    lane: operation.lane,
    selector: operation.selector,
    operationInputSha256: operation.inputSha256,
    sourceSha256: "d".repeat(64),
    receiptPath: "/private/tmp/harness-production-receipt.json",
  };
  const candidate = {
    authenticatedManifest: Object.freeze({ operation }),
    appCommit: context.expectedAppCommit,
    governedMainCommit: context.expectedCurrentMainCommit,
    manifestSha256: context.expectedCandidateManifestSha256,
    receiptSetSha256: "9".repeat(64),
    gitTreeSha1: "e".repeat(40),
    operation,
  };
  return { context, candidate };
}

function millisecondsAfter(timestamp, milliseconds) {
  return new Date(timestamp.getTime() + milliseconds);
}

function cleanupEventCount(infrastructure, eventName) {
  return infrastructure.events.filter(([name]) => name === eventName).length;
}

test("production executor is a zero-export module with private attestation state", async () => {
  const namespace = await import(
    `../scripts/execute-whatsapp-catalog-production.mjs?test=${Date.now()}`
  );
  assert.deepEqual(Object.keys(namespace), []);
  const source = await readFile(executorPath, "utf8");
  assert.doesNotMatch(source, /^\s*export\s+/m);
  assert.match(source, /const authorityAttestations = new WeakMap\(\)/);
  assert.match(source, /const preparedLiveSessions = new WeakMap\(\)/);
  assert.match(source, /const liveSessionCapabilities = new WeakMap\(\)/);
  assert.match(source, /const consumedLiveSessions = new WeakSet\(\)/);
  assert.match(
    source,
    /const recoveryInspectionCapabilities = new WeakMap\(\)/,
  );
  assert.match(source, /authorityAttestations\.delete\(token\)/);
  assert.match(source, /transaction\.markDispatchStarted\(\)/);
  assert.match(source, /createDurableArtifactTransaction/);
  assert.match(source, /authorizePreparedProductionLiveSession/);
  assert.match(source, /consumeProductionLiveSessionCapability/);
  assert.match(source, /disposeAuthorizedProductionLiveSession/);
  assert.match(source, /disposeRecoveryInspectionLiveSession/);
  assert.match(source, /actionAuthorizationClaimSha256/);
  assert.match(source, /SERIALIZED_PRODUCTION_CAPABILITY_FORBIDDEN/);
  assert.doesNotMatch(source, /claimProductionActionAuthorization/);
  assert.doesNotMatch(source, /loadProductionActionAuthorization/);
  assert.doesNotMatch(source, /createAuthenticatedDeploymentSnapshot/);
  assert.ok(
    source.lastIndexOf("consumeProductionLiveSessionCapability(") <
      source.lastIndexOf("beginIntent(context)"),
  );
  assert.ok(
    source.indexOf("authorityAttestations.delete(token)") <
      source.indexOf("return await transaction.persistFinal(bytes)"),
  );
  assert.doesNotMatch(source, /await executeDeployment\(options, dotenvText\)/);
});

test("disabled deployment body uses only a sealed authenticated package through dispatch", async () => {
  const source = await readFile(executorPath, "utf8");
  assert.match(source, /prepareExactCommitFirebasePackage/);
  assert.match(source, /mountExactCommitFirebasePackageReadOnly/);
  assert.match(source, /verifyMountedExactCommitFirebasePackage/);
  assert.match(source, /createFirebaseProductionSessionWorkspace/);
  assert.match(source, /firebaseProviderWorkspacePath/);
  assert.match(source, /gitArchiveSha256/);
  assert.match(source, /gitTreeSha1/);
  assert.match(source, /sourceKernelReadOnly/);
  assert.match(source, /serializableCapability:\s*false/);
  assert.match(source, /providerScratchInventorySha256/);
  assert.doesNotMatch(source, /buildEphemeralFirebase(?:Policy)?Config\(/);
  assert.ok(
    source.lastIndexOf("verifyMountedExactCommitFirebasePackage(") >
      source.lastIndexOf("waitForSpawn("),
  );
});

test("reviewed recovery is readback-first and requires fresh continuation authority", async () => {
  const [executorSource, reconciliationSource] = await Promise.all([
    readFile(executorPath, "utf8"),
    readFile(reconciliationPath, "utf8"),
  ]);
  assert.match(executorSource, /recordRecoveryInspection/);
  assert.match(executorSource, /mintFreshReconciliationContinuationCapability/);
  assert.match(
    executorSource,
    /recoveryReadbackSha256:\s*state\.recoveryReadbackSha256/,
  );
  assert.match(executorSource, /exactRecoveryReadback\(await provider\(\)\)/);
  assert.match(
    reconciliationSource,
    /FRESH_RECONCILIATION_CONTINUATION_AUTHORIZATION_REQUIRED/,
  );
  assert.ok(
    reconciliationSource.indexOf(
      '"FRESH_RECONCILIATION_CONTINUATION_AUTHORIZATION_REQUIRED"',
    ) < reconciliationSource.indexOf("for (let step = 0; step < maxSteps"),
  );
});

test("private lifecycle validators reject malformed recovery and expired dispatch", async () => {
  await withInstrumentedExecutor(
    ({
      exactRecoveryReadback,
      assertLiveSessionDispatchDeadline,
      extractActionAuthorizationArguments,
    }) => {
      assert.throws(
        () =>
          exactRecoveryReadback({
            outcome: "incomplete",
            cycleId: "a".repeat(32),
            continuationStateDigestSha256: "invalid",
          }),
        /PRODUCTION_RECOVERY_READBACK_REJECTED/,
      );
      assert.throws(
        () =>
          exactRecoveryReadback({
            outcome: "complete",
            cycleId: "a".repeat(32),
            unexpected: true,
          }),
        /PRODUCTION_RECOVERY_READBACK_REJECTED/,
      );
      const validFacts = {
        outcome: "incomplete",
        cycleId: "a".repeat(32),
        continuationStateDigestSha256: "c".repeat(64),
      };
      const valid = exactRecoveryReadback(validFacts);
      assert.equal(Object.isFrozen(valid), true);
      assert.equal(Object.isFrozen(valid.facts), true);
      assert.deepEqual(valid.facts, validFacts);
      assert.equal(valid.readbackSha256, canonicalSha256(validFacts));

      const deadline = "2026-08-29T10:00:00.000Z";
      assert.doesNotThrow(() =>
        assertLiveSessionDispatchDeadline(
          { binding: { expiresAt: deadline } },
          () => new Date("2026-08-29T09:59:59.999Z"),
        ),
      );
      assert.throws(
        () =>
          assertLiveSessionDispatchDeadline(
            { binding: { expiresAt: deadline } },
            () => new Date(deadline),
          ),
        /PRODUCTION_LIVE_SESSION_EXPIRED_BEFORE_DISPATCH/,
      );
      assert.throws(
        () =>
          extractActionAuthorizationArguments([
            "--action-authorization-receipt-path",
            "/tmp/forbidden.json",
          ]),
        /SERIALIZED_PRODUCTION_CAPABILITY_FORBIDDEN/,
      );
    },
  );
});

test("private live session executes prepare-authorize-consume once and rejects wrong context and replay", async () => {
  await withInstrumentedExecutor(async (executor, infrastructure) => {
    const { context, candidate } = lifecycleFixture();
    const preparedAt = new Date();
    const prepared = await executor.prepareProductionLiveSession({
      context,
      candidate,
      dotenvText: "",
      recovery: { mode: "direct" },
      clock: () => preparedAt,
    });
    assert.equal(Object.isFrozen(prepared.capability), true);
    assert.equal(Object.getPrototypeOf(prepared.capability), null);
    assert.equal(prepared.summary.productionWriteAttempted, false);

    const authorized = await executor.authorizePreparedProductionLiveSession(
      prepared.capability,
      {
        authorizedAt: millisecondsAfter(preparedAt, 1_000).toISOString(),
        deadline: millisecondsAfter(preparedAt, 120_000).toISOString(),
        clock: () => millisecondsAfter(preparedAt, 2_000),
      },
    );
    assert.equal(authorized.summary.serializableCapability, false);
    await assert.rejects(
      executor.consumeProductionLiveSessionCapability(
        authorized.capability,
        { ...context, selector: "functions:wrong" },
        { clock: () => millisecondsAfter(preparedAt, 3_000) },
      ),
      (error) => error.code === "PRODUCTION_LIVE_SESSION_CAPABILITY_REJECTED",
    );

    const consumed = await executor.consumeProductionLiveSessionCapability(
      authorized.capability,
      context,
      { clock: () => millisecondsAfter(preparedAt, 4_000) },
    );
    assert.match(consumed.consumptionSha256, /^[a-f0-9]{64}$/);
    await assert.rejects(
      executor.consumeProductionLiveSessionCapability(
        authorized.capability,
        context,
        { clock: () => millisecondsAfter(preparedAt, 5_000) },
      ),
      (error) => error.code === "PRODUCTION_LIVE_SESSION_CAPABILITY_REJECTED",
    );
    assert.equal(
      (await executor.disposeConsumedProductionLiveSession(consumed)).outcome,
      "disposed",
    );
    await assert.rejects(
      executor.disposeConsumedProductionLiveSession(consumed),
      (error) => error.code === "PRODUCTION_CONSUMED_SESSION_NOT_ACTIVE",
    );
    assert.equal(cleanupEventCount(infrastructure, "cleanup-workspace"), 1);
    assert.equal(cleanupEventCount(infrastructure, "cleanup-package"), 1);
  });
});

test("prepared, authorized, recovery, and expired live sessions clean their exact package mounts", async () => {
  await withInstrumentedExecutor(async (executor, infrastructure) => {
    const { context, candidate } = lifecycleFixture();
    const preparedAt = new Date();
    const prepare = (options = {}) =>
      executor.prepareProductionLiveSession({
        context,
        candidate,
        dotenvText: "",
        recovery: { mode: "direct" },
        clock: () => preparedAt,
        ...options,
      });

    const disposablePrepared = await prepare();
    await executor.disposePreparedProductionLiveSession(
      disposablePrepared.capability,
    );

    const toAuthorize = await prepare();
    const disposableAuthorized =
      await executor.authorizePreparedProductionLiveSession(
        toAuthorize.capability,
        {
          authorizedAt: millisecondsAfter(preparedAt, 1_000).toISOString(),
          deadline: millisecondsAfter(preparedAt, 120_000).toISOString(),
          clock: () => millisecondsAfter(preparedAt, 2_000),
        },
      );
    await executor.disposeAuthorizedProductionLiveSession(
      disposableAuthorized.capability,
    );

    const expiredPrepared = await prepare();
    await assert.rejects(
      executor.authorizePreparedProductionLiveSession(
        expiredPrepared.capability,
        {
          authorizedAt: millisecondsAfter(preparedAt, 599_000).toISOString(),
          deadline: millisecondsAfter(preparedAt, 600_000).toISOString(),
          clock: () => millisecondsAfter(preparedAt, 600_000),
        },
      ),
      (error) =>
        error.code === "FRESH_PRODUCTION_ACTION_AUTHORIZATION_REQUIRED",
    );

    const expiresAfterAuthorization = await prepare();
    const shortAuthorization =
      await executor.authorizePreparedProductionLiveSession(
        expiresAfterAuthorization.capability,
        {
          authorizedAt: millisecondsAfter(preparedAt, 1_000).toISOString(),
          deadline: millisecondsAfter(preparedAt, 10_000).toISOString(),
          clock: () => millisecondsAfter(preparedAt, 2_000),
        },
      );
    await assert.rejects(
      executor.consumeProductionLiveSessionCapability(
        shortAuthorization.capability,
        context,
        { clock: () => millisecondsAfter(preparedAt, 10_000) },
      ),
      (error) => error.code === "PRODUCTION_LIVE_SESSION_CAPABILITY_REJECTED",
    );

    let recoveryProviderCalls = 0;
    const disposableRecovery = await prepare({
      recovery: {
        mode: "readback_first",
        priorReceiptSha256: "8".repeat(64),
      },
      recoveryReadbackProvider: () => {
        recoveryProviderCalls += 1;
        return {
          outcome: "complete",
          cycleId: "7".repeat(32),
        };
      },
    });
    await executor.disposeRecoveryInspectionLiveSession(
      disposableRecovery.capability,
    );
    assert.equal(recoveryProviderCalls, 0);

    const continuationInspection = await prepare({
      recovery: {
        mode: "readback_first",
        priorReceiptSha256: "8".repeat(64),
      },
      recoveryReadbackProvider: () => ({
        outcome: "incomplete",
        cycleId: "7".repeat(32),
        continuationStateDigestSha256: "6".repeat(64),
      }),
    });
    await executor.recordRecoveryInspection(continuationInspection.capability, {
      clock: () => millisecondsAfter(preparedAt, 1_000),
    });
    const disposableContinuation =
      await executor.mintFreshReconciliationContinuationCapability(
        continuationInspection.capability,
        {
          authorizedAt: millisecondsAfter(preparedAt, 2_000).toISOString(),
          deadline: millisecondsAfter(preparedAt, 120_000).toISOString(),
          clock: () => millisecondsAfter(preparedAt, 3_000),
        },
      );
    await executor.disposeAuthorizedProductionLiveSession(
      disposableContinuation.capability,
    );

    let expiredRecoveryProviderCalls = 0;
    const expiredRecovery = await prepare({
      recovery: {
        mode: "readback_first",
        priorReceiptSha256: "8".repeat(64),
      },
      recoveryReadbackProvider: () => {
        expiredRecoveryProviderCalls += 1;
        return {
          outcome: "complete",
          cycleId: "7".repeat(32),
        };
      },
    });
    await assert.rejects(
      executor.recordRecoveryInspection(expiredRecovery.capability, {
        clock: () => millisecondsAfter(preparedAt, 600_000),
      }),
      (error) => error.code === "PRODUCTION_RECOVERY_READBACK_REJECTED",
    );
    assert.equal(expiredRecoveryProviderCalls, 0);
    assert.equal(cleanupEventCount(infrastructure, "cleanup-workspace"), 7);
    assert.equal(cleanupEventCount(infrastructure, "cleanup-package"), 7);
  });
});

test("recovery invokes its bound provider once, derives the readback digest, and requires fresh continuation authority", async () => {
  await withInstrumentedExecutor(async (executor, infrastructure) => {
    const { context, candidate } = lifecycleFixture();
    const preparedAt = new Date();
    const priorReceiptSha256 = "8".repeat(64);
    const incompleteReadback = {
      outcome: "incomplete",
      cycleId: "7".repeat(32),
      continuationStateDigestSha256: "6".repeat(64),
    };
    let providerCalls = 0;
    const inspection = await executor.prepareProductionLiveSession({
      context,
      candidate,
      dotenvText: "",
      recovery: { mode: "readback_first", priorReceiptSha256 },
      recoveryReadbackProvider: async () => {
        providerCalls += 1;
        return incompleteReadback;
      },
      clock: () => preparedAt,
    });
    const inspected = await executor.recordRecoveryInspection(
      inspection.capability,
      { clock: () => millisecondsAfter(preparedAt, 1_000) },
    );
    assert.equal(inspected.outcome, "continuation_authorization_required");
    assert.equal(
      inspected.recoveryReadbackSha256,
      canonicalSha256(incompleteReadback),
    );
    assert.equal(providerCalls, 1);
    await assert.rejects(
      executor.recordRecoveryInspection(inspection.capability, {
        clock: () => millisecondsAfter(preparedAt, 2_000),
      }),
      (error) => error.code === "PRODUCTION_RECOVERY_READBACK_REJECTED",
    );
    assert.equal(providerCalls, 1);

    const continuation =
      await executor.mintFreshReconciliationContinuationCapability(
        inspection.capability,
        {
          authorizedAt: millisecondsAfter(preparedAt, 3_000).toISOString(),
          deadline: millisecondsAfter(preparedAt, 120_000).toISOString(),
          clock: () => millisecondsAfter(preparedAt, 4_000),
        },
      );
    assert.equal(
      continuation.summary.recoveryReadbackSha256,
      canonicalSha256(incompleteReadback),
    );
    await assert.rejects(
      executor.mintFreshReconciliationContinuationCapability(
        inspection.capability,
        {
          authorizedAt: millisecondsAfter(preparedAt, 5_000).toISOString(),
          deadline: millisecondsAfter(preparedAt, 120_000).toISOString(),
          clock: () => millisecondsAfter(preparedAt, 6_000),
        },
      ),
      (error) =>
        error.code ===
        "FRESH_RECONCILIATION_CONTINUATION_AUTHORIZATION_REQUIRED",
    );
    const consumed = await executor.consumeProductionLiveSessionCapability(
      continuation.capability,
      context,
      { clock: () => millisecondsAfter(preparedAt, 7_000) },
    );
    assert.deepEqual(consumed.binding.recovery, {
      mode: "continuation",
      priorReceiptSha256,
      cycleId: incompleteReadback.cycleId,
      continuationStateDigestSha256:
        incompleteReadback.continuationStateDigestSha256,
      recoveryReadbackSha256: canonicalSha256(incompleteReadback),
    });
    await executor.disposeConsumedProductionLiveSession(consumed);

    const completeReadback = {
      outcome: "complete",
      cycleId: "5".repeat(32),
    };
    const completedInspection = await executor.prepareProductionLiveSession({
      context,
      candidate,
      dotenvText: "",
      recovery: { mode: "readback_first", priorReceiptSha256 },
      recoveryReadbackProvider: () => completeReadback,
      clock: () => preparedAt,
    });
    const complete = await executor.recordRecoveryInspection(
      completedInspection.capability,
      { clock: () => millisecondsAfter(preparedAt, 1_000) },
    );
    assert.equal(complete.outcome, "recovered_readback");
    assert.equal(
      complete.recoveryReadbackSha256,
      canonicalSha256(completeReadback),
    );

    const rejectedInspection = await executor.prepareProductionLiveSession({
      context,
      candidate,
      dotenvText: "",
      recovery: { mode: "readback_first", priorReceiptSha256 },
      recoveryReadbackProvider: () => ({
        ...completeReadback,
        readbackSha256: "4".repeat(64),
      }),
      clock: () => preparedAt,
    });
    await assert.rejects(
      executor.recordRecoveryInspection(rejectedInspection.capability, {
        clock: () => millisecondsAfter(preparedAt, 1_000),
      }),
      (error) => error.code === "PRODUCTION_RECOVERY_READBACK_REJECTED",
    );
    assert.equal(cleanupEventCount(infrastructure, "cleanup-workspace"), 3);
    assert.equal(cleanupEventCount(infrastructure, "cleanup-package"), 3);
  });
});

test("direct executor invocation is rejected before any writer gate", () => {
  const result = spawnSync(
    PINNED_NODE_RUNTIME.executablePath,
    [executorPath, "deployment", "--execute"],
    {
      cwd: path.resolve("."),
      encoding: "utf8",
      env: {
        ...directExecutorEnvironment(),
        FIREBASE_TOKEN: "must-not-be-observed",
      },
    },
  );
  assert.equal(result.status, 1);
  assert.equal(
    JSON.parse(result.stderr).code,
    "PRODUCTION_EXECUTOR_LAUNCHER_REQUIRED",
  );
});

test("external launcher blocks in shell before Node, executor paths, or NODE_OPTIONS preload", async () => {
  const source = await readFile(launcherPath, "utf8");
  const stat = await lstat(launcherPath);
  assert.equal(stat.isFile(), true);
  assert.equal(stat.mode & 0o111, 0o111);
  assert.match(source, /PRODUCTION_LIVE_SESSION_CAPABILITY_NOT_AUTHORIZED/);
  assert.doesNotMatch(source, /\/opt\/homebrew\/bin\/node|EXECUTOR_PATH/);
  assert.doesNotMatch(
    source,
    /NODE_OPTIONS|FIREBASE_TOKEN|GOOGLE_APPLICATION_CREDENTIALS/,
  );

  const root = await realpath(
    await mkdtemp(path.join(os.tmpdir(), "executor-node-options-")),
  );
  const preloadPath = path.join(root, "preload.cjs");
  const sentinelPath = path.join(root, "preload-ran");
  try {
    await writeFile(
      preloadPath,
      `require("node:fs").writeFileSync(${JSON.stringify(sentinelPath)}, "ran");\n`,
      { flag: "wx", mode: 0o600 },
    );
    const result = spawnSync(launcherPath, ["invalid-mode"], {
      cwd: path.resolve("."),
      encoding: "utf8",
      env: {
        ...process.env,
        NODE_OPTIONS: `--require=${preloadPath}`,
        FIREBASE_TOKEN: "must-be-stripped",
      },
    });
    assert.equal(result.status, 1);
    assert.equal(
      JSON.parse(result.stderr).code,
      "PRODUCTION_LIVE_SESSION_CAPABILITY_NOT_AUTHORIZED",
    );
    await assert.rejects(lstat(sentinelPath), { code: "ENOENT" });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("launcher and dormant executor retain independent write hard stops", async () => {
  const common = [
    "--expected-app-commit",
    appCommit,
    "--expected-current-main-commit",
    FROZEN_APP_MAIN_COMMIT,
    "--execute",
    "--receipt-path",
    "/tmp/not-created-production-receipt.json",
    "--candidate-manifest-path",
    "/tmp/not-read-production-candidate.json",
    "--expected-candidate-manifest-sha256",
    manifestSha256,
  ];
  const deployment = spawnSync(
    launcherPath,
    ["deployment", "--lane", "firestore-rules", ...common],
    {
      cwd: path.resolve("."),
      encoding: "utf8",
      env: process.env,
    },
  );
  assert.equal(deployment.status, 1);
  assert.equal(
    JSON.parse(deployment.stderr).code,
    "PRODUCTION_LIVE_SESSION_CAPABILITY_NOT_AUTHORIZED",
  );

  const reconciliation = spawnSync(
    launcherPath,
    ["reconciliation", ...common],
    {
      cwd: path.resolve("."),
      encoding: "utf8",
      env: process.env,
    },
  );
  assert.equal(reconciliation.status, 1);
  assert.equal(
    JSON.parse(reconciliation.stderr).code,
    "PRODUCTION_LIVE_SESSION_CAPABILITY_NOT_AUTHORIZED",
  );
  const executorSource = await readFile(executorPath, "utf8");
  assert.match(executorSource, /PRODUCTION_EXECUTOR_ACTIVATION_NOT_AUTHORIZED/);
  assert.match(
    executorSource,
    /PRODUCTION_RECONCILIATION_EXECUTOR_NOT_ENABLED/,
  );
});

test("legacy execute gates and package commands remain unrelaxed", async () => {
  const [deploymentSource, reconciliationSource, packageJson] =
    await Promise.all([
      readFile(deploymentPath, "utf8"),
      readFile(reconciliationPath, "utf8"),
      readFile(packagePath, "utf8").then(JSON.parse),
    ]);
  assert.match(
    deploymentSource,
    /PRODUCTION_CATALOG_DEPLOY_EXECUTOR_NOT_ENABLED/,
  );
  assert.match(
    reconciliationSource,
    /PRODUCTION_RECONCILIATION_EXECUTOR_NOT_ENABLED/,
  );
  assert.equal(
    packageJson.scripts["catalog:deploy:guard"],
    "node scripts/guard-whatsapp-catalog-functions-deploy.mjs",
  );
  assert.equal(
    packageJson.scripts["catalog:reconcile:production"],
    "node scripts/run-whatsapp-catalog-full-reconciliation.mjs",
  );
});

test("unlinked policy readback is evidence-only and cannot close a receipt", async () => {
  const source = await readFile(deploymentPath, "utf8");
  assert.match(
    source,
    /closedPolicyReceipt:\s*false,\s*receiptStatus:\s*"readback_evidence_only",\s*requiresPriorReceiptLineage:\s*true/s,
  );
});
