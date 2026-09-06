import assert from "node:assert/strict";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { assertDevelopmentReleasePredeployContext } from "../scripts/assert-development-release-predeploy.mjs";
import {
  DevelopmentReleaseDeployError,
  assertRequiredDevelopmentSecrets,
  buildDevelopmentReleaseEnvironment,
  developmentCodexGuardArguments,
  developmentReleaseFirebaseConfig,
  developmentReleaseSelector,
  parseFirebasePrettyIndexStates,
  requiredReleaseIndexesActive,
  requiredReleaseIndexesConfigured,
  resolveDevelopmentAuthorityCommit,
  runDevelopmentReleaseDeployment,
  synthesizeDevelopmentIndexConfiguration,
} from "../scripts/deploy-development-read-efficiency.mjs";
import {
  DEVELOPMENT_RELEASE_FUNCTIONS,
  REQUIRED_RELEASE_COMPOSITE_INDEXES,
} from "../scripts/release-deployment-contract.mjs";

const repositoryRoot = path.resolve("..");
const functionsRoot = path.join(repositoryRoot, "functions");
const commit = "c".repeat(40);
const authorityMainCommit = "b".repeat(40);

function authorityResolution(overrides = {}) {
  return {
    project_id: "spaza-one",
    project: "Spaza One",
    component: "app",
    role: "authority",
    entity: "vox-dei",
    account: "github.tsepo-vox-dei",
    repository: "Vox-Dei-Build/spazaone-app",
    matched_by: "git_origin",
    ...overrides,
  };
}

function authorityExecFile(resolution = authorityResolution()) {
  return async (command, args) => {
    if (command === "git" && args[0] === "status") return { stdout: "" };
    if (command === "git" && args.join(" ") === "rev-parse HEAD") {
      return { stdout: `${commit}\n` };
    }
    if (command === "git" && args.join(" ") === "rev-parse origin/main") {
      return { stdout: `${authorityMainCommit}\n` };
    }
    if (command === "git" && args[0] === "merge-base") {
      return { stdout: `${authorityMainCommit}\n` };
    }
    if (command.endsWith("/codex-guard")) {
      return { stdout: JSON.stringify(resolution) };
    }
    throw new Error(`unexpected authority read: ${command}`);
  };
}

function endpoint(
  id,
  { secrets = [], environment = {}, includeCommon = true } = {},
) {
  return {
    id,
    project: "spazaone-dev",
    entryPoint: id,
    region: "us-central1",
    runtime: "nodejs20",
    codebase: "default",
    platform: "gcfv2",
    hash: "a".repeat(40),
    environmentVariables: {
      FIREBASE_CONFIG: JSON.stringify({ projectId: "spazaone-dev" }),
      GCLOUD_PROJECT: "spazaone-dev",
      ...(includeCommon
        ? {
            SPAZAONE_ENVIRONMENT: "development",
            SPAZAONE_FIREBASE_PROJECT_ID: "spazaone-dev",
            BUILD_COMMIT: "a".repeat(40),
          }
        : {}),
      ...environment,
    },
    secretEnvironmentVariables: secrets.map((key) => ({
      key,
      projectId: "317368517217",
      secret: key,
      version: "3",
    })),
  };
}

function functionBaselines({ includeV2 = false } = {}) {
  const rows = [
    endpoint("getWhatsAppCatalogSyncStatusV1", {
      environment: { CATALOG_ONLY: "catalog baseline" },
    }),
    endpoint("scheduledNPAUpdate", {
      environment: { SCHEDULE_ONLY: "npa baseline" },
    }),
    endpoint("expireAccountSettlementIntents", {
      environment: { SETTLEMENT_ONLY: "settlement baseline" },
    }),
    endpoint("getEnvironmentInfo", {
      environment: { INFO_ONLY: "info baseline" },
    }),
  ];
  if (includeV2) {
    rows.push(
      endpoint("getWhatsAppCatalogSyncStatusV2", {
        secrets: ["WHATSAPP_CATALOG_STATUS_CURSOR_SECRET"],
        environment: { V2_ONLY: "existing v2 baseline" },
      }),
    );
  }
  return rows;
}

function indexDocument(indexes, fieldOverrides = []) {
  return {
    indexes: indexes.map((entry) => ({
      collectionGroup: entry.collectionGroup,
      queryScope: entry.queryScope,
      fields: entry.fields.map((field) => ({ ...field })),
    })),
    fieldOverrides,
  };
}

const unrelatedIndex = {
  collectionGroup: "sales",
  queryScope: "COLLECTION",
  fields: [
    { fieldPath: "type", order: "ASCENDING" },
    { fieldPath: "dateAdded", order: "DESCENDING" },
  ],
};

const unrelatedLocalOnlyIndex = {
  collectionGroup: "products",
  queryScope: "COLLECTION",
  fields: [
    { fieldPath: "group", order: "ASCENDING" },
    { fieldPath: "name", order: "ASCENDING" },
  ],
};

function readyPrettyOutput() {
  return [
    "Compound Indexes",
    "[READY] (customers) -- (isNPA,ASCENDING) (balance,ASCENDING)  -- Density:SPARSE_ALL ",
    "[READY] (paymentIntents) -- (purpose,ASCENDING) (status,ASCENDING) (expiresAt,ASCENDING)  -- Density:SPARSE_ALL ",
    "",
  ].join("\n");
}

test("development predeploy accepts only the exact project and ephemeral resource context", () => {
  const projectRoot = path.join(
    os.tmpdir(),
    "spazaone-development-release-test-context",
  );
  const result = assertDevelopmentReleasePredeployContext({
    resource: "functions",
    environment: {
      GCLOUD_PROJECT: "spazaone-dev",
      PROJECT_DIR: projectRoot,
      RESOURCE_DIR: functionsRoot,
    },
    resolvePath: (value) => path.resolve(value),
  });
  assert.equal(result.outcome, "verified");
  assert.equal(result.firebaseProjectId, "spazaone-dev");

  assert.equal(
    assertDevelopmentReleasePredeployContext({
      resource: "firestore",
      environment: {
        GCLOUD_PROJECT: "spazaone-dev",
        PROJECT_DIR: projectRoot,
        RESOURCE_DIR: projectRoot,
      },
      resolvePath: (value) => path.resolve(value),
    }).outcome,
    "verified",
  );

  for (const projectId of ["pasella-ledger", "demo-spazaone", ""]) {
    assert.throws(
      () =>
        assertDevelopmentReleasePredeployContext({
          resource: "functions",
          environment: {
            GCLOUD_PROJECT: projectId,
            PROJECT_DIR: projectRoot,
            RESOURCE_DIR: functionsRoot,
          },
          resolvePath: (value) => path.resolve(value),
        }),
      (error) =>
        error.code ===
        (projectId === "pasella-ledger"
          ? "DEVELOPMENT_RELEASE_PRODUCTION_FORBIDDEN"
          : "DEVELOPMENT_RELEASE_PROJECT_MISMATCH"),
    );
  }
  assert.throws(
    () =>
      assertDevelopmentReleasePredeployContext({
        resource: "functions",
        environment: {
          GCLOUD_PROJECT: "spazaone-dev",
          PROJECT_DIR: repositoryRoot,
          RESOURCE_DIR: functionsRoot,
        },
        resolvePath: (value) => path.resolve(value),
      }),
    (error) => error.code === "DEVELOPMENT_RELEASE_CONTEXT_PATH_MISMATCH",
  );
});

test("development authority requires the registered owner account and match route", async () => {
  const result = await resolveDevelopmentAuthorityCommit({
    expectedAppCommit: commit,
    execFileImpl: authorityExecFile(),
  });
  assert.equal(result.appCommit, commit);
  assert.equal(result.authorityMainCommit, authorityMainCommit);

  for (const mismatch of [
    { account: "github.tsepo-delta" },
    { matched_by: "path" },
    { project: "Different project" },
  ]) {
    await assert.rejects(
      resolveDevelopmentAuthorityCommit({
        expectedAppCommit: commit,
        execFileImpl: authorityExecFile(authorityResolution(mismatch)),
      }),
      (error) => error.code === "DEVELOPMENT_RELEASE_AUTHORITY_MISMATCH",
    );
  }
});

test("development configs retain lint/build gates and expose only fixed selectors", () => {
  const configDir = "/private/tmp/spazaone-development-release-test";
  const functionsConfig = developmentReleaseFirebaseConfig("functions", {
    configDir,
  });
  assert.equal(functionsConfig.functions[0].source, functionsRoot);
  assert.equal(functionsConfig.functions[0].configDir, configDir);
  assert.match(
    functionsConfig.functions[0].predeploy[0],
    /assert-development-release-predeploy\.mjs.*--resource functions/,
  );
  assert.deepEqual(functionsConfig.functions[0].predeploy.slice(1), [
    'npm --prefix "$RESOURCE_DIR" run lint',
    'npm --prefix "$RESOURCE_DIR" run build',
  ]);
  const indexesConfig = developmentReleaseFirebaseConfig("indexes", {
    configDir,
  });
  assert.equal(
    indexesConfig.firestore.indexes,
    path.join(configDir, "firestore.indexes.json"),
  );
  assert.match(
    indexesConfig.firestore.predeploy[0],
    /assert-development-release-predeploy\.mjs.*--resource firestore/,
  );

  const aggregateSelector = developmentReleaseSelector("functions");
  assert.equal(
    aggregateSelector,
    DEVELOPMENT_RELEASE_FUNCTIONS.map((name) => `functions:${name}`).join(","),
  );
  for (const functionName of DEVELOPMENT_RELEASE_FUNCTIONS) {
    const args = developmentCodexGuardArguments({
      lane: "functions",
      functionName,
      configPath: "/private/tmp/firebase.json",
      dryRun: false,
    });
    assert.deepEqual(args.slice(0, 6), [
      "firebase-deploy",
      "--project",
      "spaza-one",
      "--environment",
      "firebase_development",
      "--",
    ]);
    assert.equal(args.at(-1), `functions:${functionName}`);
    assert.equal(args.includes("pasella-ledger"), false);
  }
  assert.throws(
    () =>
      developmentReleaseSelector("functions", {
        functionName: "unreviewedFunction",
      }),
    (error) =>
      error instanceof DevelopmentReleaseDeployError &&
      error.code === "DEVELOPMENT_RELEASE_FUNCTION_SELECTOR_INVALID",
  );
});

test("each development function keeps its own environment and changes only BUILD_COMMIT", () => {
  const rows = functionBaselines();
  const plans = Object.fromEntries(
    DEVELOPMENT_RELEASE_FUNCTIONS.map((functionName) => [
      functionName,
      buildDevelopmentReleaseEnvironment({
        rows,
        functionName,
        appCommit: commit,
      }),
    ]),
  );
  const v2 = Object.fromEntries(plans.getWhatsAppCatalogSyncStatusV2.entries);
  const npa = Object.fromEntries(plans.scheduledNPAUpdate.entries);
  const settlement = Object.fromEntries(
    plans.expireAccountSettlementIntents.entries,
  );
  const info = Object.fromEntries(plans.getEnvironmentInfo.entries);
  assert.equal(plans.getWhatsAppCatalogSyncStatusV2.targetExisted, false);
  assert.equal(
    plans.getWhatsAppCatalogSyncStatusV2.anchorFunctionName,
    "getWhatsAppCatalogSyncStatusV1",
  );
  assert.equal(v2.CATALOG_ONLY, "catalog baseline");
  assert.equal(npa.SCHEDULE_ONLY, "npa baseline");
  assert.equal(settlement.SETTLEMENT_ONLY, "settlement baseline");
  assert.equal(info.INFO_ONLY, "info baseline");
  for (const entries of [v2, npa, settlement, info]) {
    assert.equal(entries.BUILD_COMMIT, commit);
    assert.equal(entries.SPAZAONE_ENVIRONMENT, "development");
  }
  assert.equal(npa.CATALOG_ONLY, undefined);
  assert.equal(info.SCHEDULE_ONLY, undefined);
  assert.doesNotMatch(
    plans.getEnvironmentInfo.normalized,
    /FIREBASE_CONFIG|GCLOUD_PROJECT/,
  );

  const existingV2 = functionBaselines({ includeV2: true });
  const existingPlan = buildDevelopmentReleaseEnvironment({
    rows: existingV2,
    functionName: "getWhatsAppCatalogSyncStatusV2",
    appCommit: commit,
  });
  assert.equal(
    existingPlan.anchorFunctionName,
    "getWhatsAppCatalogSyncStatusV2",
  );
  assert.equal(
    Object.fromEntries(existingPlan.entries).V2_ONLY,
    "existing v2 baseline",
  );

  const badSecrets = functionBaselines();
  badSecrets
    .find((row) => row.id === "getEnvironmentInfo")
    .secretEnvironmentVariables.push({
      key: "UNREVIEWED_SECRET",
      secret: "UNREVIEWED_SECRET",
      version: "1",
    });
  assert.throws(
    () =>
      buildDevelopmentReleaseEnvironment({
        rows: badSecrets,
        functionName: "getEnvironmentInfo",
        appCommit: commit,
      }),
    (error) => error.code === "DEVELOPMENT_RELEASE_SECRET_BINDING_MISMATCH",
  );

  const badV1 = functionBaselines();
  badV1
    .find((row) => row.id === "getWhatsAppCatalogSyncStatusV1")
    .secretEnvironmentVariables.push({
      key: "UNREVIEWED_SECRET",
      projectId: "317368517217",
      secret: "UNREVIEWED_SECRET",
      version: "1",
    });
  assert.throws(
    () =>
      buildDevelopmentReleaseEnvironment({
        rows: badV1,
        functionName: "getWhatsAppCatalogSyncStatusV2",
        appCommit: commit,
      }),
    (error) =>
      error.code === "DEVELOPMENT_RELEASE_ENVIRONMENT_ANCHOR_SECRET_MISMATCH",
  );
});

test("development index synthesis preserves the remote baseline and adds only two approved composites", () => {
  const remoteTtl = {
    collectionGroup: "existingExpirations",
    fieldPath: "expiresAt",
    ttl: true,
    indexes: [],
  };
  const unapprovedLocalTtl = {
    collectionGroup: "whatsappCatalogCartReplacements",
    fieldPath: "expiresAt",
    ttl: true,
    indexes: [],
  };
  const remote = indexDocument([unrelatedIndex], [remoteTtl]);
  const local = indexDocument(
    [
      unrelatedIndex,
      ...REQUIRED_RELEASE_COMPOSITE_INDEXES,
      unrelatedLocalOnlyIndex,
    ],
    [remoteTtl, unapprovedLocalTtl],
  );
  const plan = synthesizeDevelopmentIndexConfiguration({ remote, local });
  assert.equal(plan.addedIndexCount, 2);
  assert.equal(plan.configuration.indexes.length, 3);
  assert.deepEqual(plan.configuration.fieldOverrides, [
    { ...remoteTtl, indexes: [] },
  ]);
  assert.equal(
    plan.configuration.indexes.some(
      (entry) => entry.collectionGroup === "products",
    ),
    false,
  );
  assert.equal(requiredReleaseIndexesConfigured(plan.configuration), true);

  const rerun = synthesizeDevelopmentIndexConfiguration({
    remote: plan.configuration,
    local,
  });
  assert.equal(rerun.addedIndexCount, 0);
  assert.equal(
    rerun.baselineConfigurationSha256,
    rerun.expectedConfigurationSha256,
  );
  assert.throws(
    () =>
      synthesizeDevelopmentIndexConfiguration({
        remote,
        local: indexDocument([unrelatedIndex]),
      }),
    (error) =>
      error.code === "DEVELOPMENT_RELEASE_REQUIRED_INDEX_SOURCE_MISSING",
  );
});

test("dependent function gate requires both exact composite indexes READY", () => {
  const ready = REQUIRED_RELEASE_COMPOSITE_INDEXES.map((index, position) => ({
    name: `projects/spazaone-dev/databases/(default)/collectionGroups/${index.collectionGroup}/indexes/${position + 1}`,
    collectionGroup: index.collectionGroup,
    queryScope: index.queryScope,
    state: "READY",
    fields: index.fields.map((field) => ({ ...field })),
  }));
  assert.equal(requiredReleaseIndexesActive(ready), true);
  assert.equal(
    requiredReleaseIndexesActive([
      { ...ready[0], state: "CREATING" },
      ready[1],
    ]),
    false,
  );
  const parsed = parseFirebasePrettyIndexStates(
    readyPrettyOutput().replace(
      "[READY] (paymentIntents)",
      "[CREATING] (paymentIntents)",
    ),
  );
  assert.equal(requiredReleaseIndexesActive(parsed), false);
  parsed[1].state = "READY";
  assert.equal(requiredReleaseIndexesActive(parsed), true);
});

test("required cursor secret preflight is metadata-only and fails with a stable code", async () => {
  const calls = [];
  const result = await assertRequiredDevelopmentSecrets({
    execFileImpl: async (command, args) => {
      calls.push({ command, args });
      return {
        stdout: JSON.stringify({
          status: "success",
          result: {
            secrets: [
              {
                secret: {
                  projectId: "317368517217",
                  name: "WHATSAPP_CATALOG_STATUS_CURSOR_SECRET",
                },
                versionId: "1",
                state: "ENABLED",
              },
            ],
          },
        }),
      };
    },
  });
  assert.equal(result.requiredSecretCount, 1);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].args.slice(-2), [
    "functions:secrets:get",
    "WHATSAPP_CATALOG_STATUS_CURSOR_SECRET",
  ]);
  assert.equal(
    calls.some((call) =>
      call.args.some((value) => String(value).includes("access")),
    ),
    false,
  );

  await assert.rejects(
    assertRequiredDevelopmentSecrets({
      execFileImpl: async () => {
        throw new Error("not found");
      },
    }),
    (error) => error.code === "MISSING_REQUIRED_DEVELOPMENT_SECRET",
  );
});

test("missing cursor secret blocks the function lane before any write dispatch", async () => {
  let spawned = false;
  const remoteIndexes = indexDocument(REQUIRED_RELEASE_COMPOSITE_INDEXES);
  await assert.rejects(
    runDevelopmentReleaseDeployment({
      lane: "functions",
      expectedAppCommit: commit,
      execute: true,
      resolveCommit: async () => ({
        appCommit: commit,
        authorityMainCommit: "b".repeat(40),
      }),
      spawnImpl: () => {
        spawned = true;
        throw new Error("must not spawn");
      },
      execFileImpl: async (command, args) => {
        if (args.includes("firestore:indexes")) {
          return {
            stdout: args.includes("--pretty")
              ? readyPrettyOutput()
              : JSON.stringify(remoteIndexes),
          };
        }
        if (args.includes("functions:secrets:get")) throw new Error("404");
        throw new Error(`unexpected read: ${command}`);
      },
    }),
    (error) => error.code === "MISSING_REQUIRED_DEVELOPMENT_SECRET",
  );
  assert.equal(spawned, false);
});

test("an ignored source dotenv blocks the function lane before any write dispatch", async () => {
  let spawned = false;
  let sourceChecks = 0;
  await assert.rejects(
    runDevelopmentReleaseDeployment({
      lane: "functions",
      expectedAppCommit: commit,
      execute: true,
      resolveCommit: async () => ({
        appCommit: commit,
        authorityMainCommit,
      }),
      assertSourceDeploymentClean: async () => {
        sourceChecks++;
        throw new DevelopmentReleaseDeployError(
          "DEVELOPMENT_RELEASE_SOURCE_DOTENV_PRESENT",
        );
      },
      spawnImpl: () => {
        spawned = true;
        throw new Error("must not spawn");
      },
      execFileImpl: async () => {
        throw new Error("must not read remote state");
      },
    }),
    (error) => error.code === "DEVELOPMENT_RELEASE_SOURCE_DOTENV_PRESENT",
  );
  assert.equal(sourceChecks, 1);
  assert.equal(spawned, false);
});
