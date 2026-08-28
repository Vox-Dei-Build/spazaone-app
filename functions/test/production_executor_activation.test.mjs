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

import { FROZEN_APP_MAIN_COMMIT } from "../scripts/production-candidate-manifest.mjs";
import { PINNED_NODE_RUNTIME } from "../scripts/production-write-receipt.mjs";

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

test("production executor is a zero-export module with private attestation state", async () => {
  const namespace = await import(
    `../scripts/execute-whatsapp-catalog-production.mjs?test=${Date.now()}`
  );
  assert.deepEqual(Object.keys(namespace), []);
  const source = await readFile(executorPath, "utf8");
  assert.doesNotMatch(source, /^\s*export\s+/m);
  assert.match(source, /const authorityAttestations = new WeakMap\(\)/);
  assert.match(source, /authorityAttestations\.delete\(token\)/);
  assert.match(source, /transaction\.markDispatchStarted\(\)/);
  assert.match(source, /createDurableArtifactTransaction/);
  assert.match(source, /claimProductionActionAuthorization/);
  assert.match(source, /actionAuthorizationClaimSha256/);
  assert.match(source, /PRODUCTION_LIVE_SESSION_CAPABILITY_NOT_AUTHORIZED/);
  assert.ok(
    source.lastIndexOf("claimProductionActionAuthorization(") <
      source.lastIndexOf("beginIntent(context)"),
  );
  assert.ok(
    source.indexOf("authorityAttestations.delete(token)") <
      source.indexOf("return await transaction.persistFinal(bytes)"),
  );
  assert.ok(
    source.lastIndexOf("assertExecutorActivationAuthorized()") <
      source.indexOf("await executeDeployment(options, dotenvText)"),
  );
});

test("disabled deployment body uses only a sealed authenticated package through dispatch", async () => {
  const source = await readFile(executorPath, "utf8");
  assert.match(source, /createAuthenticatedDeploymentSnapshot/);
  assert.match(source, /packageFileEvidence/);
  assert.match(source, /"firestore\.rules"/);
  assert.match(source, /"firestore\.indexes\.json"/);
  assert.match(source, /verifyImmutableDeploymentSnapshot/);
  assert.match(source, /immutableDeploymentSnapshotPath/);
  assert.doesNotMatch(source, /buildEphemeralFirebase(?:Policy)?Config\(/);
  assert.ok(
    source.lastIndexOf("verifyImmutableDeploymentSnapshot(") >
      source.lastIndexOf("waitForSpawn("),
  );
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
