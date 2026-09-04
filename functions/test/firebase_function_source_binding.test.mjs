import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { createRequire } from "node:module";
import test from "node:test";

import {
  FirebaseFunctionSourceBindingError,
  FIREBASE_FUNCTION_SOURCE_IGNORES,
  assertPinnedFirebaseFunctionHashImplementation,
  collectFirebaseGen1RuntimeConfigHashSha1,
  computeCandidateFirebaseSourceContract,
  firebaseEndpointHashSha1,
  firebaseGen1RuntimeConfigHashSha1,
  listCandidateFirebasePackageFiles,
  verifyCandidateFirebaseFunctionHashes,
} from "../scripts/firebase-function-source-binding.mjs";
import {
  NATIVE_CATALOG_EXISTING_FUNCTION_SECRET_REFS,
  NATIVE_CATALOG_FUNCTION_SECRET_REFS,
} from "../scripts/guard-whatsapp-catalog-functions-deploy.mjs";

const require = createRequire(import.meta.url);
const skipPinnedMachineAttestation =
  process.env.SPAZAONE_SKIP_PINNED_MACHINE_ATTESTATION === "1";
const hostBoundTest = skipPinnedMachineAttestation ? test.skip : test;
const pinnedFirebaseFs = skipPinnedMachineAttestation
  ? undefined
  : require("/opt/homebrew/lib/node_modules/firebase-tools/lib/fsAsync.js");
const pinnedFirebaseHash = skipPinnedMachineAttestation
  ? undefined
  : require("/opt/homebrew/lib/node_modules/firebase-tools/lib/deploy/functions/cache/hash.js");

const commit = "c".repeat(40);
const projectId = "pasella-ledger";
const region = "us-central1";

function digest(algorithm, value) {
  return createHash(algorithm).update(value).digest("hex");
}

function pinnedEndpointHash({
  sourceHashSha1,
  environmentVariables,
  secretVersions,
}) {
  const envHash = pinnedFirebaseHash.getEnvironmentVariablesHash({
    environmentVariables,
  });
  const secretsHash = pinnedFirebaseHash.getSecretsHash({
    secretEnvironmentVariables: Object.entries(secretVersions).map(
      ([secret, version]) => ({ secret, version }),
    ),
  });
  return pinnedFirebaseHash.getEndpointHash(
    sourceHashSha1,
    envHash,
    secretsHash,
  );
}

function blobSha1(value) {
  const bytes = Buffer.from(value, "utf8");
  return createHash("sha1")
    .update(Buffer.from(`blob ${bytes.length}\0`, "utf8"))
    .update(bytes)
    .digest("hex");
}

function fakeGitTree(files) {
  return async () => ({
    functionsRelativePath: "functions",
    entries: new Map(
      Object.entries(files).map(([name, value]) => [
        name,
        { mode: "100644", blobSha1: blobSha1(value) },
      ]),
    ),
  });
}

async function withCandidateSource(callback) {
  const root = await mkdtemp(
    path.join(os.tmpdir(), "firebase-source-binding-test-"),
  );
  const functionsDirectory = path.join(root, "functions");
  const tracked = {
    ".gitignore": "lib/**/*.js\nlib/**/*.js.map\n",
    "package.json": '{"name":"binding-fixture"}\n',
    "src/index.ts": "export const example = true;\n",
  };
  try {
    await mkdir(path.join(functionsDirectory, "src"), { recursive: true });
    await mkdir(path.join(functionsDirectory, "lib"), { recursive: true });
    for (const [relativePath, value] of Object.entries(tracked)) {
      await writeFile(path.join(functionsDirectory, relativePath), value);
    }
    await writeFile(
      path.join(functionsDirectory, "lib/index.js"),
      '"use strict";\nexports.example = true;\n',
    );
    await writeFile(
      path.join(functionsDirectory, "lib/index.js.map"),
      '{"version":3,"file":"index.js","sources":["../src/index.ts"]}\n',
    );
    await mkdir(path.join(functionsDirectory, "node_modules", "ignored"), {
      recursive: true,
    });
    await writeFile(
      path.join(functionsDirectory, "node_modules/ignored/index.js"),
      "must not be packaged\n",
    );
    await writeFile(
      path.join(functionsDirectory, "firebase-debug.trace.log"),
      "must not be packaged\n",
    );
    await callback({ root, functionsDirectory, tracked });
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

hostBoundTest("pinned firebase-tools hash implementation is present", async () => {
  assert.match(
    await assertPinnedFirebaseFunctionHashImplementation(),
    /^[a-f0-9]{64}$/,
  );
  await assert.rejects(
    assertPinnedFirebaseFunctionHashImplementation({
      readFileImpl: async () => Buffer.from("changed implementation", "utf8"),
    }),
    (error) => error.code === "FIREBASE_FUNCTION_HASH_IMPLEMENTATION_MISMATCH",
  );
});

hostBoundTest("runtime and endpoint hashes reproduce firebase-tools 15.21.0", () => {
  const firebaseConfig = {
    projectId,
    storageBucket: "pasella-ledger.appspot.com",
    databaseURL: "https://pasella-ledger.firebaseio.test",
  };
  const legacy = {
    twilio: { token: "fixture-token-never-output", sid: "fixture-sid" },
    nested: { z: "last", a: "first" },
  };
  const runtimeHash = firebaseGen1RuntimeConfigHashSha1(firebaseConfig, legacy);
  const sorted = (value) => {
    if (typeof value !== "object" || value === null) return value;
    return Object.keys(value)
      .sort()
      .map((key) => ({ key, value: sorted(value[key]) }));
  };
  assert.equal(
    runtimeHash,
    digest(
      "sha1",
      JSON.stringify(sorted({ firebase: firebaseConfig, ...legacy })),
    ),
  );

  const sourceHashSha1 = `${"a".repeat(40)}.${runtimeHash}`;
  const environmentVariables = {
    SETTING: "value",
    GCLOUD_PROJECT: projectId,
  };
  const secretVersions = { FIRST_SECRET: "2", SECOND_SECRET: "11" };
  const envHash = digest("sha1", JSON.stringify(environmentVariables));
  const secretsHash = digest("sha1", JSON.stringify(secretVersions));
  assert.equal(
    firebaseEndpointHashSha1({
      sourceHashSha1,
      environmentVariables,
      secretVersions,
    }),
    pinnedEndpointHash({
      sourceHashSha1,
      environmentVariables,
      secretVersions,
    }),
  );
  assert.equal(
    pinnedEndpointHash({
      sourceHashSha1,
      environmentVariables,
      secretVersions,
    }),
    digest("sha1", `${sourceHashSha1}${envHash}${secretsHash}`),
  );
});

hostBoundTest("checked secret-reference order matches every selected source declaration", async () => {
  const sourceFiles = {
    onMerchantProductCatalogChange: "src/whatsapp/catalogQueue.ts",
    syncWhatsAppMerchantCatalog: "src/whatsapp/catalogWorker.ts",
    reconcileWhatsAppMerchantCatalog: "src/whatsapp/catalogReconciliation.ts",
    runWhatsAppCatalogFullReconciliationBotHttp:
      "src/whatsapp/catalogReconciliation.ts",
    getMerchantWhatsAppCatalogCompletenessBotHttp:
      "src/whatsapp/catalogStatus.ts",
    getMerchantWhatsAppProductListBotHttp: "src/whatsapp/catalogStatus.ts",
    getWhatsAppCatalogSyncStatusV1: "src/whatsapp/catalogStatus.ts",
    getWhatsAppCatalogSyncStatusV2: "src/whatsapp/catalogStatus.ts",
    resolveMerchantWhatsAppCatalogProductBotHttp:
      "src/whatsapp/nativeProductListDelivery.ts",
    sendMerchantWhatsAppCatalogBotHttp:
      "src/whatsapp/nativeProductListDelivery.ts",
    getWhatsAppProductListDeliveryStatusBotHttp:
      "src/whatsapp/nativeProductListStatus.ts",
    monitorWhatsAppProductListDeliveries:
      "src/whatsapp/nativeProductListStatus.ts",
    replaceWhatsAppCatalogCartBotHttp:
      "src/ecommerce/replaceWhatsAppCatalogCart.ts",
    getMerchantCatalogBotHttp: "src/ecommerce/getMerchantCatalogBotHttp.ts",
    checkoutCart: "src/ecommerce/checkoutCart.ts",
    cancelOrder: "src/ecommerce/cancelOrder.ts",
    finalizeOnlinePaid: "src/ecommerce/finalizeOnlinePaid.ts",
    updateOrderPayment: "src/ecommerce/updateOrderPayment.ts",
  };
  const contracts = {
    ...NATIVE_CATALOG_FUNCTION_SECRET_REFS,
    ...NATIVE_CATALOG_EXISTING_FUNCTION_SECRET_REFS,
  };
  const functionsRoot = path.resolve(import.meta.dirname, "..");
  for (const [functionName, expected] of Object.entries(contracts)) {
    const text = await readFile(
      path.join(functionsRoot, sourceFiles[functionName]),
      "utf8",
    );
    const start = text.indexOf(`export const ${functionName}`);
    assert.notEqual(start, -1, functionName);
    const next = text.indexOf("\nexport const ", start + 1);
    const declaration = text.slice(start, next === -1 ? undefined : next);
    const secrets = declaration.match(/secrets:\s*\[([\s\S]*?)\]/)?.[1] ?? "";
    const actual = [...secrets.matchAll(/["']([A-Z][A-Z0-9_]*)["']/g)].map(
      (match) => match[1],
    );
    assert.deepEqual(actual, [...expected], functionName);
  }
});

hostBoundTest("candidate contract binds Git blobs, exact generated inventory, and package bytes", async () => {
  await withCandidateSource(async ({ root, functionsDirectory, tracked }) => {
    const pinnedFiles = (
      await pinnedFirebaseFs.readdirRecursive({
        path: functionsDirectory,
        ignoreStrings: [...FIREBASE_FUNCTION_SOURCE_IGNORES],
      })
    )
      .map(({ name }) =>
        path.relative(functionsDirectory, name).split(path.sep).join("/"),
      )
      .sort();
    assert.deepEqual(
      await listCandidateFirebasePackageFiles(functionsDirectory),
      pinnedFiles,
    );
    const contract = await computeCandidateFirebaseSourceContract({
      repositoryRoot: root,
      functionsDirectory,
      expectedAppCommit: commit,
      runtimeConfigHashSha1: "b".repeat(40),
      loadGitTree: fakeGitTree(tracked),
      assertImplementation: async () => "d".repeat(64),
    });
    assert.match(contract.contractSha256, /^[a-f0-9]{64}$/);
    assert.match(contract.sourceV1HashSha1, /^[a-f0-9]{40}\.[a-f0-9]{40}$/);
    assert.match(contract.sourceV2HashSha1, /^[a-f0-9]{40}$/);
    assert.equal(contract.packagedFileCount, 5);
    assert.equal(contract.generatedFileCount, 2);
    assert.equal(contract.firebaseParamsModuleReferenceCount, 0);
    assert.equal(contract.packageFileEvidence.length, 5);
    assert.equal(Object.isFrozen(contract.packageFileEvidence), true);
    assert.ok(
      contract.packageFileEvidence.every(
        (entry) =>
          Object.isFrozen(entry) &&
          /^[a-f0-9]{64}$/.test(entry.sha256) &&
          typeof entry.relativePath === "string",
      ),
    );
    assert.deepEqual(
      contract.packageFileEvidence.map((entry) => entry.relativePath),
      pinnedFiles,
    );

    const reviewedGitFunctionsDirectory = path.join(
      root,
      "reviewed-git-origin/functions",
    );
    let capturedGitFunctionsDirectory = null;
    const separated = await computeCandidateFirebaseSourceContract({
      repositoryRoot: root,
      functionsDirectory,
      gitFunctionsDirectory: reviewedGitFunctionsDirectory,
      expectedAppCommit: commit,
      runtimeConfigHashSha1: "b".repeat(40),
      loadGitTree: async (input) => {
        capturedGitFunctionsDirectory = input.functionsDirectory;
        return fakeGitTree(tracked)();
      },
      assertImplementation: async () => "d".repeat(64),
    });
    assert.equal(capturedGitFunctionsDirectory, reviewedGitFunctionsDirectory);
    assert.equal(separated.contractSha256, contract.contractSha256);

    await writeFile(
      path.join(functionsDirectory, "firestore-debug.log"),
      "firebase-tools packages this untracked file\n",
    );
    assert.equal(
      (await listCandidateFirebasePackageFiles(functionsDirectory)).includes(
        "firestore-debug.log",
      ),
      true,
    );
    await assert.rejects(
      computeCandidateFirebaseSourceContract({
        repositoryRoot: root,
        functionsDirectory,
        expectedAppCommit: commit,
        runtimeConfigHashSha1: "b".repeat(40),
        loadGitTree: fakeGitTree(tracked),
        assertImplementation: async () => "d".repeat(64),
      }),
      (error) => error.code === "FIREBASE_CANDIDATE_SOURCE_INVENTORY_MISMATCH",
    );
    await rm(path.join(functionsDirectory, "firestore-debug.log"));

    await writeFile(
      path.join(functionsDirectory, "lib/stale.js"),
      "exports.stale = true;\n",
    );
    await assert.rejects(
      computeCandidateFirebaseSourceContract({
        repositoryRoot: root,
        functionsDirectory,
        expectedAppCommit: commit,
        runtimeConfigHashSha1: "b".repeat(40),
        loadGitTree: fakeGitTree(tracked),
        assertImplementation: async () => "d".repeat(64),
      }),
      (error) => error.code === "FIREBASE_CANDIDATE_SOURCE_INVENTORY_MISMATCH",
    );
  });
});

hostBoundTest("candidate contract rejects unresolved Firebase parameter declarations", async () => {
  await withCandidateSource(async ({ root, functionsDirectory, tracked }) => {
    const paramsModule = ["firebase-functions", "params"].join("/");
    tracked["src/index.ts"] =
      `import { defineString } from "${paramsModule}";\n` +
      'export const example = defineString("EXAMPLE");\n';
    await writeFile(
      path.join(functionsDirectory, "src/index.ts"),
      tracked["src/index.ts"],
    );
    await assert.rejects(
      computeCandidateFirebaseSourceContract({
        repositoryRoot: root,
        functionsDirectory,
        expectedAppCommit: commit,
        runtimeConfigHashSha1: "b".repeat(40),
        loadGitTree: fakeGitTree(tracked),
        assertImplementation: async () => "d".repeat(64),
      }),
      (error) => error.code === "FIREBASE_CANDIDATE_PARAMS_UNSUPPORTED",
    );
  });
});

hostBoundTest("candidate contract rejects a tracked byte that is not from the reviewed commit", async () => {
  await withCandidateSource(async ({ root, functionsDirectory, tracked }) => {
    await writeFile(
      path.join(functionsDirectory, "src/index.ts"),
      "export const changed = true;\n",
    );
    await assert.rejects(
      computeCandidateFirebaseSourceContract({
        repositoryRoot: root,
        functionsDirectory,
        expectedAppCommit: commit,
        runtimeConfigHashSha1: "b".repeat(40),
        loadGitTree: fakeGitTree(tracked),
        assertImplementation: async () => "d".repeat(64),
      }),
      (error) => error.code === "FIREBASE_CANDIDATE_SOURCE_GIT_BLOB_MISMATCH",
    );
  });
});

hostBoundTest("runtime-config collector returns only a digest and clears command buffers", async () => {
  const firebaseConfig = JSON.stringify({ projectId, storageBucket: "bucket" });
  const legacy = { twilio: { token: "fixture-token-never-output" } };
  const outputs = [];
  const invocations = [];
  const execFileImpl = async (command, args, options) => {
    invocations.push({ command, args, options });
    const value = args.includes("functions:list")
      ? {
          status: "success",
          result: [
            {
              id: "getMerchantCatalogBotHttp",
              environmentVariables: { FIREBASE_CONFIG: firebaseConfig },
            },
          ],
        }
      : { status: "success", result: legacy };
    const stdout = Buffer.from(JSON.stringify(value), "utf8");
    outputs.push(stdout);
    return { stdout };
  };
  const result = await collectFirebaseGen1RuntimeConfigHashSha1({
    firebaseCliPath: "/opt/homebrew/bin/firebase",
    projectId,
    account: "tsepo.ntsaba@thedelta.io",
    anchorFunctionId: "getMerchantCatalogBotHttp",
    execFileImpl,
    environment: { PATH: "/opt/homebrew/bin:/usr/bin:/bin" },
  });
  assert.equal(
    result,
    firebaseGen1RuntimeConfigHashSha1(JSON.parse(firebaseConfig), legacy),
  );
  assert.match(result, /^[a-f0-9]{40}$/);
  assert.equal(JSON.stringify(result).includes("fixture-token"), false);
  assert.equal(
    outputs.every((buffer) => buffer.every((byte) => byte === 0)),
    true,
  );
  assert.equal(
    invocations.every(
      ({ options }) =>
        options.environment === undefined &&
        options.env.FIREBASE_CLI_EXPERIMENTS === "legacyRuntimeConfigCommands",
    ),
    true,
  );
});

function sourceContract() {
  return {
    contractSha256: "d".repeat(64),
    packagedFileCount: 42,
    generatedFileCount: 20,
    firebaseParamsModuleReferenceCount: 0,
    sourceV1HashSha1: `${"a".repeat(40)}.${"b".repeat(40)}`,
    sourceV2HashSha1: "a".repeat(40),
  };
}

function normalizedEndpoint({
  id,
  platform,
  environmentVariables,
  secrets,
  hash,
}) {
  return {
    id,
    platform,
    region,
    codebase: "default",
    runtime: "nodejs20",
    entryPoint: id,
    environmentVariables,
    secretEnvironmentVariables: secrets.map(([key, version]) => ({
      key,
      secret: key,
      version,
    })),
    hash,
  };
}

hostBoundTest("configured and existing lanes require candidate-derived provider hashes", () => {
  const configuredEnvironmentEntries = [["BUILD_COMMIT", commit]];
  const firebaseConfig = JSON.stringify({ projectId, storageBucket: "bucket" });
  const configuredBackendEnvironment = {
    BUILD_COMMIT: commit,
    FIREBASE_CONFIG: firebaseConfig,
    GCLOUD_PROJECT: projectId,
  };
  const configuredEndpointEnvironment = {
    ...configuredBackendEnvironment,
    EVENTARC_CLOUD_EVENT_SOURCE: `projects/${projectId}/locations/${region}/functions/sendCatalog`,
  };
  const configuredSecrets = { TOKEN_A: "2", TOKEN_B: "7" };
  const configuredProviderHash = pinnedEndpointHash({
    sourceHashSha1: sourceContract().sourceV1HashSha1,
    environmentVariables: configuredBackendEnvironment,
    secretVersions: configuredSecrets,
  });
  const configured = normalizedEndpoint({
    id: "sendCatalog",
    platform: "gcfv1",
    environmentVariables: configuredEndpointEnvironment,
    secrets: Object.entries(configuredSecrets),
    hash: configuredProviderHash,
  });
  assert.notEqual(
    configuredProviderHash,
    pinnedEndpointHash({
      sourceHashSha1: sourceContract().sourceV1HashSha1,
      environmentVariables: configuredEndpointEnvironment,
      secretVersions: configuredSecrets,
    }),
    "EVENTARC is endpoint-only and must not affect the provider label",
  );
  const configuredProof = verifyCandidateFirebaseFunctionHashes({
    endpoints: [configured],
    expectedFunctionNames: ["sendCatalog"],
    expectedSecretReferences: { sendCatalog: ["TOKEN_A", "TOKEN_B"] },
    sourceContract: sourceContract(),
    projectId,
    region,
    configuredEnvironmentEntries,
  });
  assert.equal(configuredProof.candidateSourceBindingMatches, true);
  assert.doesNotMatch(
    JSON.stringify(configuredProof),
    /TOKEN_A|firebase-functions/,
  );

  const baseline = {
    environmentVariables: {
      EXISTING_SETTING: "preserved",
      FIREBASE_CONFIG: firebaseConfig,
      GCLOUD_PROJECT: projectId,
      EVENTARC_CLOUD_EVENT_SOURCE: `projects/${projectId}/locations/${region}/functions/checkoutCart`,
    },
  };
  const existingEnvironment = { ...baseline.environmentVariables };
  const existingBackendEnvironment = {
    FIREBASE_CONFIG: firebaseConfig,
    GCLOUD_PROJECT: projectId,
  };
  const existingSecrets = { PASELLA_BOT_TOKEN: "5" };
  const existingProviderHash = pinnedEndpointHash({
    sourceHashSha1: sourceContract().sourceV1HashSha1,
    environmentVariables: existingBackendEnvironment,
    secretVersions: existingSecrets,
  });
  const existing = normalizedEndpoint({
    id: "checkoutCart",
    platform: "gcfv1",
    environmentVariables: existingEnvironment,
    secrets: Object.entries(existingSecrets),
    hash: existingProviderHash,
  });
  assert.notEqual(
    existingProviderHash,
    pinnedEndpointHash({
      sourceHashSha1: sourceContract().sourceV1HashSha1,
      environmentVariables: existingEnvironment,
      secretVersions: existingSecrets,
    }),
    "preserved remote endpoint values are not wantBackend hash inputs",
  );
  const existingProof = verifyCandidateFirebaseFunctionHashes({
    endpoints: [existing],
    expectedFunctionNames: ["checkoutCart"],
    expectedSecretReferences: { checkoutCart: ["PASELLA_BOT_TOKEN"] },
    sourceContract: sourceContract(),
    projectId,
    region,
    existingEnvironmentBaselines: { checkoutCart: baseline },
  });
  assert.equal(existingProof.candidateSourceBindingMatches, true);

  existing.hash = "f".repeat(40);
  const stale = verifyCandidateFirebaseFunctionHashes({
    endpoints: [existing],
    expectedFunctionNames: ["checkoutCart"],
    expectedSecretReferences: { checkoutCart: ["PASELLA_BOT_TOKEN"] },
    sourceContract: sourceContract(),
    projectId,
    region,
    existingEnvironmentBaselines: { checkoutCart: baseline },
  });
  assert.equal(stale.candidateSourceBindingMatches, false);
});

hostBoundTest("secret order/version, selector, region, codebase, and source are fail closed", () => {
  const source = sourceContract();
  const firebaseConfig = JSON.stringify({ projectId });
  const environmentVariables = {
    BUILD_COMMIT: commit,
    FIREBASE_CONFIG: firebaseConfig,
    GCLOUD_PROJECT: projectId,
    EVENTARC_CLOUD_EVENT_SOURCE: `projects/${projectId}/locations/${region}/services/sendCatalog`,
  };
  const endpoint = normalizedEndpoint({
    id: "sendCatalog",
    platform: "gcfv2",
    environmentVariables,
    secrets: [
      ["TOKEN_B", "2"],
      ["TOKEN_A", "1"],
    ],
    hash: "f".repeat(40),
  });
  const proof = verifyCandidateFirebaseFunctionHashes({
    endpoints: [endpoint],
    expectedFunctionNames: ["sendCatalog"],
    expectedSecretReferences: { sendCatalog: ["TOKEN_A", "TOKEN_B"] },
    sourceContract: source,
    projectId,
    region,
    configuredEnvironmentEntries: [["BUILD_COMMIT", commit]],
  });
  assert.equal(proof.candidateSourceBindingMatches, false);

  for (const mutation of [
    { region: "europe-west1" },
    { codebase: "other" },
    { runtime: "nodejs18" },
    { entryPoint: "other" },
  ]) {
    const changed = { ...endpoint, ...mutation };
    const changedProof = verifyCandidateFirebaseFunctionHashes({
      endpoints: [changed],
      expectedFunctionNames: ["sendCatalog"],
      expectedSecretReferences: { sendCatalog: ["TOKEN_A", "TOKEN_B"] },
      sourceContract: source,
      projectId,
      region,
      configuredEnvironmentEntries: [["BUILD_COMMIT", commit]],
    });
    assert.equal(changedProof.candidateSourceBindingMatches, false);
  }
  assert.throws(
    () =>
      verifyCandidateFirebaseFunctionHashes({
        endpoints: [endpoint],
        expectedFunctionNames: ["missingFunction"],
        expectedSecretReferences: { missingFunction: [] },
        sourceContract: source,
        projectId,
        region,
        configuredEnvironmentEntries: [["BUILD_COMMIT", commit]],
      }),
    (error) =>
      error instanceof FirebaseFunctionSourceBindingError &&
      error.code === "FIREBASE_CANDIDATE_HASH_SELECTOR_MISMATCH",
  );
});
