import { createHash, randomUUID } from "node:crypto";
import { execFile as nodeExecFile } from "node:child_process";
import { constants as fsConstants } from "node:fs";
import {
  link,
  lstat,
  open,
  readFile,
  realpath,
  unlink,
} from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

import {
  PRODUCTION_FIREBASE_ACCOUNT,
  PRODUCTION_FIREBASE_PROJECT_ID,
  PRODUCTION_NATIVE_CATALOG_TARGET,
  PRODUCTION_TARGET_DOCUMENT,
  nativeCatalogTargetConfigurationDigestSha256,
} from "./whatsapp-catalog-production-target.mjs";
import {
  FROZEN_APP_MAIN_COMMIT,
  PRODUCTION_CANDIDATE_RECEIPT_NAMES,
  canonicalProductionCandidateManifestBytes,
} from "./production-candidate-manifest.mjs";

const execFile = promisify(nodeExecFile);

export const PINNED_NODE_RUNTIME = Object.freeze({
  executablePath: "/opt/homebrew/bin/node",
  executableRealpath: "/opt/homebrew/Cellar/node/24.4.1/bin/node",
  executableSha256:
    "0747ad5579627f4c31f899bc980979aeb082a38b02415a749c9ee6e061370b01",
  version: "v24.4.1",
});

export const PINNED_FIREBASE_CLI = Object.freeze({
  executablePath: "/opt/homebrew/bin/firebase",
  executableRealpath:
    "/opt/homebrew/lib/node_modules/firebase-tools/lib/bin/firebase.js",
  executableSha256:
    "1e05ff8373e5a5c7222475a0d90d4db58c85c2f281d44d4884bc96062288b864",
  version: "15.21.0",
});

export const PINNED_GCLOUD_CLI = Object.freeze({
  executablePath: "/opt/homebrew/bin/gcloud",
  executableRealpath: "/opt/homebrew/share/google-cloud-sdk/bin/gcloud",
  executableSha256:
    "8628b9f971d07c5e52fd2c6d469ee4a0940c75eb51820d628c3dd068981bd260",
  version: "576.0.0",
});

export const PRODUCTION_WRITE_AUTHORITY = Object.freeze({
  projectId: "spaza-one",
  project: "Spaza One",
  entity: "vox-dei",
  component: "app",
  role: "authority",
  account: "github.tsepo-vox-dei",
  repository: "Vox-Dei-Build/spazaone-app",
  matchedBy: "git_origin",
});

export const PRODUCTION_WRITE_TARGET = Object.freeze({
  firebaseProjectId: PRODUCTION_FIREBASE_PROJECT_ID,
  firebaseAccount: PRODUCTION_FIREBASE_ACCOUNT,
  firestoreDatabaseId: "(default)",
  codexGuardPath: "/Users/admin/.codex/identity-governance/bin/codex-guard",
});

const SHA256 = /^[a-f0-9]{64}$/;
const COMMIT = /^[a-f0-9]{40}$/;
const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/;
const SAFE_CODE = /^[A-Z][A-Z0-9_]{0,95}$/;
const RECEIPT_KEYS = [
  "schemaVersion",
  "kind",
  "outcome",
  "actionStartedAt",
  "dispatchStartedAt",
  "actionCompletedAt",
  "verifiedAt",
  "authority",
  "target",
  "toolchain",
  "appCommit",
  "operation",
  "lineage",
  "result",
  "remoteWriteAttempted",
  "needsReview",
  "retryAllowed",
  "redactedReceiptSha256",
];
const TOOLCHAIN_KEYS = [
  "nodeExecutablePath",
  "nodeExecutableRealpath",
  "nodeExecutableSha256",
  "nodeVersion",
  "firebaseCliExecutablePath",
  "firebaseCliExecutableRealpath",
  "firebaseCliExecutableSha256",
  "firebaseCliVersion",
  "gcloudCliExecutablePath",
  "gcloudCliExecutableRealpath",
  "gcloudCliExecutableSha256",
  "gcloudCliVersion",
];
const OPERATION_KEYS = [
  "lane",
  "selector",
  "sourceSha256",
  "configurationSha256",
  "candidateManifestSha256",
  "operationInputSha256",
  "actionAuthorizationSha256",
  "actionAuthorizationClaimSha256",
  "operatorAuditOnly",
];
const LINEAGE_KEYS = ["mode", "priorReceiptSha256"];
const RESULT_KEYS = [
  "commandExitZero",
  "readbackStatus",
  "cleanupStatus",
  "providerScratchEvidence",
  "remoteEvidence",
  "errorCode",
];
const PROVIDER_SCRATCH_EVIDENCE_KEYS = [
  "inventorySha256",
  "entryCount",
  "totalBytes",
];
const REMOTE_EVIDENCE_KEYS = ["kind", "evidenceSha256", "summary"];
const CANDIDATE_MANIFEST_KEYS = [
  "schemaVersion",
  "kind",
  "appCommit",
  "governedMainCommit",
  "gitTreeSha1",
  "immutableTargetConfigurationSha256",
  "operation",
  "receipts",
];
const CANDIDATE_OPERATION_KEYS = ["kind", "lane", "selector", "inputSha256"];
const BUILD_RECEIPT_INPUT_KEYS = [
  "kind",
  "outcome",
  "actionStartedAt",
  "dispatchStartedAt",
  "actionCompletedAt",
  "verifiedAt",
  "appCommit",
  "lane",
  "selector",
  "sourceSha256",
  "configurationSha256",
  "candidateManifest",
  "candidateManifestSha256",
  "operationInputSha256",
  "actionAuthorizationSha256",
  "actionAuthorizationClaimSha256",
  "commandExitZero",
  "readbackStatus",
  "cleanupStatus",
  "remoteEvidence",
  "errorCode",
];
const FUNCTION_EVIDENCE_KEYS = [
  "kind",
  "lane",
  "selector",
  "firebaseProjectId",
  "region",
  "functionCount",
  "buildIdentitiesComplete",
  "buildIdentitySetSha256",
  "environmentShapesValid",
  "environmentMatches",
  "secretReferencesMatch",
  "environmentDigestSha256",
  "expectedEnvironmentDigestSha256",
  "environmentTransitionMode",
  "preDeployEnvironmentDigestSha256",
  "environmentTransitionDigestSha256",
  "candidateSourceBindingMatches",
  "candidateSourceContractSha256",
  "candidateSourceFileCount",
  "candidateGeneratedFileCount",
  "candidateProviderBindingSetSha256",
];
const FIRESTORE_RULES_EVIDENCE_KEYS = [
  "kind",
  "lane",
  "selector",
  "firebaseProjectId",
  "databaseId",
  "sourceSha256",
  "activeSourceSha256",
  "activeRulesetName",
];
const FIRESTORE_INDEXES_EVIDENCE_KEYS = [
  "kind",
  "lane",
  "selector",
  "firebaseProjectId",
  "databaseId",
  "sourceSha256",
  "expectedFullIndexConfigurationDigestSha256",
  "remoteFullIndexConfigurationDigestSha256",
  "expectedIndexCount",
  "remoteIndexCount",
  "expectedFieldOverrideCount",
  "remoteFieldOverrideCount",
  "expectedTtlContractDigestSha256",
  "remoteTtlContractDigestSha256",
  "expectedTtlFieldCount",
  "remoteTtlFieldCount",
  "ttlActive",
  "ttlActiveCount",
];
const RECONCILIATION_EVIDENCE_KEYS = ["kind", "artifact"];
export const FINALIZED_RECONCILIATION_ARTIFACT_KEYS = Object.freeze([
  "schemaVersion",
  "kind",
  "verifiedAt",
  "startedAt",
  "completedAt",
  "firebaseProjectId",
  "catalogId",
  "senderPhoneNumberId",
  "appCommit",
  "targetConfigurationDigestSha256",
  "cycleId",
  "deliveryEnabled",
  "syncEnabled",
  "scanScope",
  "cycleComplete",
  "productScanComplete",
  "mappingScanComplete",
  "stabilityVerified",
  "sourceCountsVerified",
  "outboxDrained",
  "outboxPendingCount",
  "outboxRetryCount",
  "outboxProcessingCount",
  "outboxSubmittedCount",
  "outboxActiveCount",
  "outboxDeletedCount",
  "outboxRejectedCount",
  "outboxUnknownCount",
  "outboxTotalCount",
  "outboxCountsVerified",
  "catalogComplete",
  "setEqualityVerified",
  "mutationGenerationDigestSha256",
  "completionDigest",
  "incompleteMerchantCount",
  "malformedMappingCount",
  "redactedReceiptSha256",
]);

const FUNCTION_LANE_SELECTORS = Object.freeze({
  "dark-new": [
    "onMerchantProductCatalogChange",
    "syncWhatsAppMerchantCatalog",
    "reconcileWhatsAppMerchantCatalog",
    "runWhatsAppCatalogFullReconciliationBotHttp",
    "getMerchantWhatsAppCatalogCompletenessBotHttp",
    "getMerchantWhatsAppProductListBotHttp",
    "getWhatsAppCatalogSyncStatusV1",
    "resolveMerchantWhatsAppCatalogProductBotHttp",
    "sendMerchantWhatsAppCatalogBotHttp",
    "getWhatsAppProductListDeliveryStatusBotHttp",
    "monitorWhatsAppProductListDeliveries",
    "replaceWhatsAppCatalogCartBotHttp",
  ],
  "existing-code": [
    "getMerchantCatalogBotHttp",
    "checkoutCart",
    "cancelOrder",
    "finalizeOnlinePaid",
    "updateOrderPayment",
  ],
  "sync-enable": [
    "onMerchantProductCatalogChange",
    "syncWhatsAppMerchantCatalog",
    "reconcileWhatsAppMerchantCatalog",
    "runWhatsAppCatalogFullReconciliationBotHttp",
    "getMerchantWhatsAppCatalogCompletenessBotHttp",
    "getMerchantWhatsAppProductListBotHttp",
  ],
  "sync-disable": [
    "onMerchantProductCatalogChange",
    "syncWhatsAppMerchantCatalog",
    "reconcileWhatsAppMerchantCatalog",
    "runWhatsAppCatalogFullReconciliationBotHttp",
    "getMerchantWhatsAppCatalogCompletenessBotHttp",
    "getMerchantWhatsAppProductListBotHttp",
  ],
  "controlled-delivery-enable": [
    "resolveMerchantWhatsAppCatalogProductBotHttp",
    "sendMerchantWhatsAppCatalogBotHttp",
    "getWhatsAppProductListDeliveryStatusBotHttp",
    "monitorWhatsAppProductListDeliveries",
    "replaceWhatsAppCatalogCartBotHttp",
  ],
  "all-eligible-delivery-enable": [
    "resolveMerchantWhatsAppCatalogProductBotHttp",
    "sendMerchantWhatsAppCatalogBotHttp",
    "getWhatsAppProductListDeliveryStatusBotHttp",
    "monitorWhatsAppProductListDeliveries",
    "replaceWhatsAppCatalogCartBotHttp",
  ],
  "delivery-disable": [
    "resolveMerchantWhatsAppCatalogProductBotHttp",
    "sendMerchantWhatsAppCatalogBotHttp",
    "getWhatsAppProductListDeliveryStatusBotHttp",
    "monitorWhatsAppProductListDeliveries",
    "replaceWhatsAppCatalogCartBotHttp",
  ],
});

const RECEIPT_OPERATION_CONTRACTS = Object.freeze({
  spazaone_catalog_function_deployment: Object.freeze(
    Object.fromEntries(
      Object.entries(FUNCTION_LANE_SELECTORS).map(([lane, functions]) => [
        lane,
        functions.map((name) => `functions:${name}`).join(","),
      ]),
    ),
  ),
  spazaone_catalog_policy_deployment: Object.freeze({
    "firestore-rules": "firestore:rules",
    "firestore-indexes": "firestore:indexes",
  }),
  spazaone_catalog_full_reconciliation: Object.freeze({
    "full-reconciliation":
      "functions:runWhatsAppCatalogFullReconciliationBotHttp",
  }),
});

export class ProductionReceiptError extends Error {
  constructor(code, { targetMayExist = false } = {}) {
    super(code);
    this.name = "ProductionReceiptError";
    this.code = code;
    this.needsReview = targetMayExist;
    this.retryAllowed = false;
    this.targetMayExist = targetMayExist;
  }
}

function fail(code, options) {
  throw new ProductionReceiptError(code, options);
}

function plainObject(value, label) {
  if (
    value === null ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) {
    fail(`${label}_INVALID`);
  }
  return value;
}

function exactKeys(value, expected, label) {
  const keys = Object.keys(plainObject(value, label)).sort();
  const approved = [...expected].sort();
  if (
    keys.length !== approved.length ||
    keys.some((key, index) => key !== approved[index])
  ) {
    fail(`${label}_KEYSET_INVALID`);
  }
}

function exactObject(value, expected, label) {
  exactKeys(value, Object.keys(expected), label);
  for (const [key, expectedValue] of Object.entries(expected)) {
    if (value[key] !== expectedValue) fail(`${label}_MISMATCH`);
  }
}

function validateProviderScratchEvidence(value) {
  exactKeys(value, PROVIDER_SCRATCH_EVIDENCE_KEYS, "PROVIDER_SCRATCH_EVIDENCE");
  string(
    value.inventorySha256,
    "PROVIDER_SCRATCH_EVIDENCE_INVENTORY_SHA256",
    SHA256,
  );
  const entryCount = nonNegativeInteger(
    value.entryCount,
    "PROVIDER_SCRATCH_EVIDENCE_ENTRY_COUNT",
  );
  const totalBytes = nonNegativeInteger(
    value.totalBytes,
    "PROVIDER_SCRATCH_EVIDENCE_TOTAL_BYTES",
  );
  if (entryCount > 2_048 || totalBytes > 256 * 1024 * 1024) {
    fail("PROVIDER_SCRATCH_EVIDENCE_UNBOUNDED");
  }
}

function string(value, label, pattern) {
  if (
    typeof value !== "string" ||
    !value ||
    (pattern && !pattern.test(value))
  ) {
    fail(`${label}_INVALID`);
  }
  return value;
}

function nullableSha256(value, label) {
  if (value === null) return null;
  return string(value, label, SHA256);
}

function timestamp(value, label) {
  const result = string(value, label, ISO_TIMESTAMP);
  if (!Number.isFinite(Date.parse(result))) fail(`${label}_INVALID`);
  return result;
}

export function canonicalJson(value) {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean"
  ) {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) fail("CANONICAL_NUMBER_INVALID");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }
  const record = plainObject(value, "CANONICAL_OBJECT");
  return `{${Object.keys(record)
    .sort()
    .map((key) => {
      if (record[key] === undefined) fail("CANONICAL_UNDEFINED_INVALID");
      return `${JSON.stringify(key)}:${canonicalJson(record[key])}`;
    })
    .join(",")}}`;
}

export function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

export function canonicalSha256(value) {
  return sha256(canonicalJson(value));
}

export function appCommitSourceSha256(appCommit) {
  return sha256(
    `spazaone-app-commit-v1\n${string(appCommit, "APP_COMMIT", COMMIT)}\n`,
  );
}

function expectedOperationSelector(kind, lane) {
  const lanes = RECEIPT_OPERATION_CONTRACTS[kind];
  return lanes && Object.hasOwn(lanes, lane) ? lanes[lane] : null;
}

function nonNegativeInteger(value, label) {
  if (!Number.isSafeInteger(value) || value < 0) fail(`${label}_INVALID`);
  return value;
}

function trueValue(value, label) {
  if (value !== true) fail(`${label}_INVALID`);
  return true;
}

function expectedCandidateOperationKind(receiptKind) {
  return {
    spazaone_catalog_function_deployment: "function_deployment",
    spazaone_catalog_policy_deployment: "policy_deployment",
    spazaone_catalog_full_reconciliation: "full_reconciliation",
  }[receiptKind];
}

function validateCandidateManifestBinding({
  candidateManifest,
  candidateManifestSha256,
  kind,
  appCommit,
  lane,
  selector,
  operationInputSha256,
}) {
  exactKeys(
    candidateManifest,
    CANDIDATE_MANIFEST_KEYS,
    "PRODUCTION_RECEIPT_CANDIDATE_MANIFEST",
  );
  exactKeys(
    candidateManifest.operation,
    CANDIDATE_OPERATION_KEYS,
    "PRODUCTION_RECEIPT_CANDIDATE_OPERATION",
  );
  exactKeys(
    candidateManifest.receipts,
    PRODUCTION_CANDIDATE_RECEIPT_NAMES,
    "PRODUCTION_RECEIPT_CANDIDATE_RECEIPTS",
  );
  const receiptDigests = PRODUCTION_CANDIDATE_RECEIPT_NAMES.map((name) =>
    string(
      candidateManifest.receipts[name],
      "PRODUCTION_RECEIPT_CANDIDATE_RECEIPT_SHA256",
      SHA256,
    ),
  );
  const expectedManifestDigest = sha256(
    canonicalProductionCandidateManifestBytes(candidateManifest),
  );
  if (
    candidateManifest.schemaVersion !== 1 ||
    candidateManifest.kind !== "spazaone_native_catalog_production_candidate" ||
    candidateManifest.appCommit !== appCommit ||
    candidateManifest.governedMainCommit !== FROZEN_APP_MAIN_COMMIT ||
    !COMMIT.test(String(candidateManifest.gitTreeSha1 ?? "")) ||
    candidateManifest.immutableTargetConfigurationSha256 !==
      nativeCatalogTargetConfigurationDigestSha256() ||
    candidateManifest.operation.kind !== expectedCandidateOperationKind(kind) ||
    candidateManifest.operation.lane !== lane ||
    candidateManifest.operation.selector !== selector ||
    candidateManifest.operation.inputSha256 !== operationInputSha256 ||
    new Set(receiptDigests).size !== receiptDigests.length ||
    candidateManifestSha256 !== expectedManifestDigest
  ) {
    fail("PRODUCTION_RECEIPT_CANDIDATE_BINDING_INVALID");
  }
  return expectedManifestDigest;
}

function artifactWithoutSeal(artifact) {
  const result = { ...artifact };
  delete result.redactedReceiptSha256;
  return result;
}

export function validateFinalizedReconciliationArtifact(
  artifact,
  {
    expectedAppCommit = null,
    expectedTargetConfigurationDigestSha256 = nativeCatalogTargetConfigurationDigestSha256(),
  } = {},
) {
  exactKeys(
    artifact,
    FINALIZED_RECONCILIATION_ARTIFACT_KEYS,
    "FINALIZED_RECONCILIATION_ARTIFACT",
  );
  const startedAt = Date.parse(
    timestamp(artifact.startedAt, "RECONCILIATION_ARTIFACT_STARTED_AT"),
  );
  const completedAt = Date.parse(
    timestamp(artifact.completedAt, "RECONCILIATION_ARTIFACT_COMPLETED_AT"),
  );
  const verifiedAt = Date.parse(
    timestamp(artifact.verifiedAt, "RECONCILIATION_ARTIFACT_VERIFIED_AT"),
  );
  const countNames = [
    "outboxPendingCount",
    "outboxRetryCount",
    "outboxProcessingCount",
    "outboxSubmittedCount",
    "outboxActiveCount",
    "outboxDeletedCount",
    "outboxRejectedCount",
    "outboxUnknownCount",
    "outboxTotalCount",
    "incompleteMerchantCount",
    "malformedMappingCount",
  ];
  for (const name of countNames) {
    nonNegativeInteger(
      artifact[name],
      `RECONCILIATION_ARTIFACT_${name.toUpperCase()}`,
    );
  }
  const outboxStatusTotal = [
    artifact.outboxPendingCount,
    artifact.outboxRetryCount,
    artifact.outboxProcessingCount,
    artifact.outboxSubmittedCount,
    artifact.outboxActiveCount,
    artifact.outboxDeletedCount,
    artifact.outboxRejectedCount,
    artifact.outboxUnknownCount,
  ].reduce((sum, count) => sum + count, 0);
  string(
    artifact.mutationGenerationDigestSha256,
    "RECONCILIATION_ARTIFACT_MUTATION_GENERATION_SHA256",
    SHA256,
  );
  string(
    artifact.completionDigest,
    "RECONCILIATION_ARTIFACT_COMPLETION_DIGEST",
    SHA256,
  );
  string(
    artifact.redactedReceiptSha256,
    "RECONCILIATION_ARTIFACT_RECEIPT_SHA256",
    SHA256,
  );
  if (
    artifact.schemaVersion !== 1 ||
    artifact.kind !== "spazaone_catalog_full_reconciliation" ||
    startedAt > completedAt ||
    completedAt > verifiedAt ||
    !COMMIT.test(String(artifact.appCommit ?? "")) ||
    (expectedAppCommit !== null && artifact.appCommit !== expectedAppCommit) ||
    artifact.targetConfigurationDigestSha256 !==
      expectedTargetConfigurationDigestSha256 ||
    artifact.firebaseProjectId !== PRODUCTION_FIREBASE_PROJECT_ID ||
    artifact.catalogId !== PRODUCTION_NATIVE_CATALOG_TARGET.catalogId ||
    artifact.senderPhoneNumberId !==
      PRODUCTION_NATIVE_CATALOG_TARGET.senderPhoneNumberId ||
    !/^[a-f0-9]{32}$/.test(String(artifact.cycleId ?? "")) ||
    artifact.deliveryEnabled !== false ||
    artifact.syncEnabled !== true ||
    artifact.scanScope !== "all_eligible_merchants" ||
    artifact.cycleComplete !== true ||
    artifact.productScanComplete !== true ||
    artifact.mappingScanComplete !== true ||
    artifact.stabilityVerified !== true ||
    artifact.sourceCountsVerified !== true ||
    artifact.outboxDrained !== true ||
    artifact.outboxCountsVerified !== true ||
    artifact.catalogComplete !== true ||
    artifact.setEqualityVerified !== true ||
    artifact.incompleteMerchantCount !== 0 ||
    artifact.malformedMappingCount !== 0 ||
    artifact.outboxPendingCount !== 0 ||
    artifact.outboxRetryCount !== 0 ||
    artifact.outboxProcessingCount !== 0 ||
    artifact.outboxSubmittedCount !== 0 ||
    artifact.outboxUnknownCount !== 0 ||
    outboxStatusTotal !== artifact.outboxTotalCount ||
    artifact.redactedReceiptSha256 !==
      canonicalSha256(artifactWithoutSeal(artifact))
  ) {
    fail("FINALIZED_RECONCILIATION_ARTIFACT_BINDING_INVALID");
  }
  return {
    artifactReceiptSha256: artifact.redactedReceiptSha256,
    completionDigestSha256: artifact.completionDigest,
  };
}

function normalizeFunctionEvidence(remoteEvidence, context) {
  exactKeys(remoteEvidence, FUNCTION_EVIDENCE_KEYS, "FUNCTION_REMOTE_EVIDENCE");
  const expectedFunctionCount = context.selector.split(",").length;
  const functionCount = nonNegativeInteger(
    remoteEvidence.functionCount,
    "FUNCTION_REMOTE_EVIDENCE_COUNT",
  );
  const buildIdentitySetSha256 = string(
    remoteEvidence.buildIdentitySetSha256,
    "FUNCTION_REMOTE_EVIDENCE_BUILD_IDENTITY_SHA256",
    SHA256,
  );
  const environmentDigestSha256 = string(
    remoteEvidence.environmentDigestSha256,
    "FUNCTION_REMOTE_EVIDENCE_ENVIRONMENT_SHA256",
    SHA256,
  );
  const expectedEnvironmentDigestSha256 = string(
    remoteEvidence.expectedEnvironmentDigestSha256,
    "FUNCTION_REMOTE_EVIDENCE_EXPECTED_ENVIRONMENT_SHA256",
    SHA256,
  );
  const environmentTransitionMode = string(
    remoteEvidence.environmentTransitionMode,
    "FUNCTION_REMOTE_EVIDENCE_TRANSITION_MODE",
    /^(configured_exact|exact_catalog_recipient_hash_secret_addition|exact_environment_preservation)$/,
  );
  const preDeployEnvironmentDigestSha256 =
    remoteEvidence.preDeployEnvironmentDigestSha256 === null
      ? null
      : string(
          remoteEvidence.preDeployEnvironmentDigestSha256,
          "FUNCTION_REMOTE_EVIDENCE_PREDEPLOY_ENVIRONMENT_SHA256",
          SHA256,
        );
  const environmentTransitionDigestSha256 = string(
    remoteEvidence.environmentTransitionDigestSha256,
    "FUNCTION_REMOTE_EVIDENCE_TRANSITION_SHA256",
    SHA256,
  );
  const candidateSourceContractSha256 = string(
    remoteEvidence.candidateSourceContractSha256,
    "FUNCTION_REMOTE_EVIDENCE_SOURCE_CONTRACT_SHA256",
    SHA256,
  );
  const candidateProviderBindingSetSha256 = string(
    remoteEvidence.candidateProviderBindingSetSha256,
    "FUNCTION_REMOTE_EVIDENCE_PROVIDER_BINDING_SHA256",
    SHA256,
  );
  const candidateSourceFileCount = nonNegativeInteger(
    remoteEvidence.candidateSourceFileCount,
    "FUNCTION_REMOTE_EVIDENCE_SOURCE_FILE_COUNT",
  );
  const candidateGeneratedFileCount = nonNegativeInteger(
    remoteEvidence.candidateGeneratedFileCount,
    "FUNCTION_REMOTE_EVIDENCE_GENERATED_FILE_COUNT",
  );
  if (
    remoteEvidence.kind !== "function_deployment" ||
    remoteEvidence.lane !== context.lane ||
    remoteEvidence.selector !== context.selector ||
    remoteEvidence.firebaseProjectId !== PRODUCTION_FIREBASE_PROJECT_ID ||
    remoteEvidence.region !== PRODUCTION_TARGET_DOCUMENT.functionRegions[0] ||
    functionCount !== expectedFunctionCount ||
    functionCount < 1 ||
    environmentDigestSha256 !== expectedEnvironmentDigestSha256 ||
    (context.lane === "existing-code"
      ? preDeployEnvironmentDigestSha256 === null ||
        environmentTransitionMode === "configured_exact"
      : preDeployEnvironmentDigestSha256 !== null ||
        environmentTransitionMode !== "configured_exact") ||
    environmentTransitionDigestSha256 !==
      sha256(
        JSON.stringify([
          environmentTransitionMode,
          preDeployEnvironmentDigestSha256,
          environmentDigestSha256,
        ]),
      )
  ) {
    fail("FUNCTION_REMOTE_EVIDENCE_BINDING_INVALID");
  }
  trueValue(
    remoteEvidence.buildIdentitiesComplete,
    "FUNCTION_REMOTE_EVIDENCE_BUILD_IDENTITIES_COMPLETE",
  );
  trueValue(
    remoteEvidence.environmentShapesValid,
    "FUNCTION_REMOTE_EVIDENCE_ENVIRONMENT_SHAPES_VALID",
  );
  trueValue(
    remoteEvidence.environmentMatches,
    "FUNCTION_REMOTE_EVIDENCE_ENVIRONMENT_MATCHES",
  );
  trueValue(
    remoteEvidence.secretReferencesMatch,
    "FUNCTION_REMOTE_EVIDENCE_SECRET_REFERENCES_MATCH",
  );
  trueValue(
    remoteEvidence.candidateSourceBindingMatches,
    "FUNCTION_REMOTE_EVIDENCE_SOURCE_BINDING_MATCHES",
  );
  if (
    candidateSourceFileCount < 1 ||
    candidateGeneratedFileCount < 1 ||
    candidateGeneratedFileCount > candidateSourceFileCount
  ) {
    fail("FUNCTION_REMOTE_EVIDENCE_SOURCE_COUNTS_INVALID");
  }
  return {
    lane: remoteEvidence.lane,
    selector: remoteEvidence.selector,
    firebaseProjectId: remoteEvidence.firebaseProjectId,
    region: remoteEvidence.region,
    functionCount,
    buildIdentitiesComplete: true,
    buildIdentitySetSha256,
    environmentShapesValid: true,
    environmentMatches: true,
    secretReferencesMatch: true,
    environmentDigestSha256,
    expectedEnvironmentDigestSha256,
    environmentTransitionMode,
    preDeployEnvironmentDigestSha256,
    environmentTransitionDigestSha256,
    candidateSourceBindingMatches: true,
    candidateSourceContractSha256,
    candidateSourceFileCount,
    candidateGeneratedFileCount,
    candidateProviderBindingSetSha256,
  };
}

function normalizeFirestoreRulesEvidence(remoteEvidence, context) {
  exactKeys(
    remoteEvidence,
    FIRESTORE_RULES_EVIDENCE_KEYS,
    "FIRESTORE_RULES_REMOTE_EVIDENCE",
  );
  const sourceSha256 = string(
    remoteEvidence.sourceSha256,
    "FIRESTORE_RULES_REMOTE_EVIDENCE_SOURCE_SHA256",
    SHA256,
  );
  const activeSourceSha256 = string(
    remoteEvidence.activeSourceSha256,
    "FIRESTORE_RULES_REMOTE_EVIDENCE_ACTIVE_SOURCE_SHA256",
    SHA256,
  );
  const activeRulesetName = string(
    remoteEvidence.activeRulesetName,
    "FIRESTORE_RULES_REMOTE_EVIDENCE_RULESET",
    new RegExp(
      `^projects/${PRODUCTION_FIREBASE_PROJECT_ID}/rulesets/[A-Za-z0-9_-]+$`,
    ),
  );
  if (
    remoteEvidence.kind !== "firestore_rules" ||
    remoteEvidence.lane !== "firestore-rules" ||
    remoteEvidence.lane !== context.lane ||
    remoteEvidence.selector !== "firestore:rules" ||
    remoteEvidence.selector !== context.selector ||
    remoteEvidence.firebaseProjectId !== PRODUCTION_FIREBASE_PROJECT_ID ||
    remoteEvidence.databaseId !== PRODUCTION_WRITE_TARGET.firestoreDatabaseId ||
    sourceSha256 !== activeSourceSha256 ||
    sourceSha256 !== context.sourceSha256 ||
    sourceSha256 !== context.operationInputSha256
  ) {
    fail("FIRESTORE_RULES_REMOTE_EVIDENCE_BINDING_INVALID");
  }
  return {
    lane: remoteEvidence.lane,
    selector: remoteEvidence.selector,
    firebaseProjectId: remoteEvidence.firebaseProjectId,
    databaseId: remoteEvidence.databaseId,
    sourceSha256,
    activeSourceSha256,
    activeRulesetName,
  };
}

function normalizeFirestoreIndexesEvidence(remoteEvidence, context) {
  exactKeys(
    remoteEvidence,
    FIRESTORE_INDEXES_EVIDENCE_KEYS,
    "FIRESTORE_INDEXES_REMOTE_EVIDENCE",
  );
  const digestNames = [
    "sourceSha256",
    "expectedFullIndexConfigurationDigestSha256",
    "remoteFullIndexConfigurationDigestSha256",
    "expectedTtlContractDigestSha256",
    "remoteTtlContractDigestSha256",
  ];
  const digests = Object.fromEntries(
    digestNames.map((name) => [
      name,
      string(
        remoteEvidence[name],
        `FIRESTORE_INDEXES_REMOTE_EVIDENCE_${name.toUpperCase()}`,
        SHA256,
      ),
    ]),
  );
  const countNames = [
    "expectedIndexCount",
    "remoteIndexCount",
    "expectedFieldOverrideCount",
    "remoteFieldOverrideCount",
    "expectedTtlFieldCount",
    "remoteTtlFieldCount",
    "ttlActiveCount",
  ];
  const counts = Object.fromEntries(
    countNames.map((name) => [
      name,
      nonNegativeInteger(
        remoteEvidence[name],
        `FIRESTORE_INDEXES_REMOTE_EVIDENCE_${name.toUpperCase()}`,
      ),
    ]),
  );
  if (
    remoteEvidence.kind !== "firestore_indexes" ||
    remoteEvidence.lane !== "firestore-indexes" ||
    remoteEvidence.lane !== context.lane ||
    remoteEvidence.selector !== "firestore:indexes" ||
    remoteEvidence.selector !== context.selector ||
    remoteEvidence.firebaseProjectId !== PRODUCTION_FIREBASE_PROJECT_ID ||
    remoteEvidence.databaseId !== PRODUCTION_WRITE_TARGET.firestoreDatabaseId ||
    digests.sourceSha256 !== context.sourceSha256 ||
    digests.sourceSha256 !== context.operationInputSha256 ||
    digests.expectedFullIndexConfigurationDigestSha256 !==
      digests.remoteFullIndexConfigurationDigestSha256 ||
    counts.expectedIndexCount !== counts.remoteIndexCount ||
    counts.expectedFieldOverrideCount !== counts.remoteFieldOverrideCount ||
    digests.expectedTtlContractDigestSha256 !==
      digests.remoteTtlContractDigestSha256 ||
    counts.expectedTtlFieldCount < 1 ||
    counts.expectedTtlFieldCount !== counts.remoteTtlFieldCount ||
    counts.expectedTtlFieldCount !== counts.ttlActiveCount ||
    remoteEvidence.ttlActive !== true
  ) {
    fail("FIRESTORE_INDEXES_REMOTE_EVIDENCE_BINDING_INVALID");
  }
  return {
    lane: remoteEvidence.lane,
    selector: remoteEvidence.selector,
    firebaseProjectId: remoteEvidence.firebaseProjectId,
    databaseId: remoteEvidence.databaseId,
    ...digests,
    ...counts,
    ttlActive: true,
  };
}

function normalizeReconciliationEvidence(remoteEvidence, context) {
  exactKeys(
    remoteEvidence,
    RECONCILIATION_EVIDENCE_KEYS,
    "RECONCILIATION_REMOTE_EVIDENCE",
  );
  if (remoteEvidence.kind !== "full_reconciliation") {
    fail("RECONCILIATION_REMOTE_EVIDENCE_KIND_INVALID");
  }
  const digests = validateFinalizedReconciliationArtifact(
    remoteEvidence.artifact,
    {
      expectedAppCommit: context.appCommit,
      expectedTargetConfigurationDigestSha256: context.configurationSha256,
    },
  );
  if (
    context.kind !== "spazaone_catalog_full_reconciliation" ||
    context.lane !== "full-reconciliation" ||
    context.selector !==
      "functions:runWhatsAppCatalogFullReconciliationBotHttp" ||
    context.sourceSha256 !== appCommitSourceSha256(context.appCommit) ||
    Date.parse(remoteEvidence.artifact.verifiedAt) >
      Date.parse(context.verifiedAt)
  ) {
    fail("RECONCILIATION_REMOTE_EVIDENCE_BINDING_INVALID");
  }
  return {
    artifactReceiptSha256: digests.artifactReceiptSha256,
    completionDigestSha256: digests.completionDigestSha256,
    artifact: structuredClone(remoteEvidence.artifact),
  };
}

function expectedRemoteEvidenceKind(kind, lane) {
  if (kind === "spazaone_catalog_function_deployment") {
    return "function_deployment";
  }
  if (kind === "spazaone_catalog_full_reconciliation") {
    return "full_reconciliation";
  }
  if (kind === "spazaone_catalog_policy_deployment") {
    return lane === "firestore-rules" ? "firestore_rules" : "firestore_indexes";
  }
  return null;
}

function normalizeRemoteEvidence(remoteEvidence, context) {
  plainObject(remoteEvidence, "REMOTE_EVIDENCE");
  const expectedKind = expectedRemoteEvidenceKind(context.kind, context.lane);
  if (!expectedKind || remoteEvidence.kind !== expectedKind) {
    fail("REMOTE_EVIDENCE_KIND_MISMATCH");
  }
  let summary;
  if (expectedKind === "function_deployment") {
    summary = normalizeFunctionEvidence(remoteEvidence, context);
  } else if (expectedKind === "firestore_rules") {
    summary = normalizeFirestoreRulesEvidence(remoteEvidence, context);
  } else if (expectedKind === "firestore_indexes") {
    summary = normalizeFirestoreIndexesEvidence(remoteEvidence, context);
  } else {
    summary = normalizeReconciliationEvidence(remoteEvidence, context);
  }
  return {
    kind: expectedKind,
    evidenceSha256: canonicalSha256(remoteEvidence),
    summary,
  };
}

function validateStoredRemoteEvidence(stored, context) {
  exactKeys(stored, REMOTE_EVIDENCE_KEYS, "STORED_REMOTE_EVIDENCE");
  const reconstructed =
    stored.kind === "full_reconciliation"
      ? { kind: stored.kind, artifact: stored.summary?.artifact }
      : { kind: stored.kind, ...stored.summary };
  const normalized = normalizeRemoteEvidence(reconstructed, context);
  if (canonicalJson(stored) !== canonicalJson(normalized)) {
    fail("STORED_REMOTE_EVIDENCE_BINDING_INVALID");
  }
  return normalized;
}

function assertOperationCrossBinding(receipt) {
  const selector = expectedOperationSelector(
    receipt.kind,
    receipt.operation.lane,
  );
  if (!selector || receipt.operation.selector !== selector) {
    fail("PRODUCTION_RECEIPT_OPERATION_MISMATCH");
  }
  if (
    receipt.operation.configurationSha256 !==
    nativeCatalogTargetConfigurationDigestSha256()
  ) {
    fail("PRODUCTION_RECEIPT_CONFIGURATION_MISMATCH");
  }
  if (
    receipt.kind !== "spazaone_catalog_policy_deployment" &&
    receipt.operation.sourceSha256 !== appCommitSourceSha256(receipt.appCommit)
  ) {
    fail("PRODUCTION_RECEIPT_SOURCE_MISMATCH");
  }
  string(
    receipt.operation.candidateManifestSha256,
    "PRODUCTION_RECEIPT_CANDIDATE_MANIFEST_SHA256",
    SHA256,
  );
  string(
    receipt.operation.operationInputSha256,
    "PRODUCTION_RECEIPT_OPERATION_INPUT_SHA256",
    SHA256,
  );
  string(
    receipt.operation.actionAuthorizationSha256,
    "PRODUCTION_RECEIPT_ACTION_AUTHORIZATION_SHA256",
    SHA256,
  );
  string(
    receipt.operation.actionAuthorizationClaimSha256,
    "PRODUCTION_RECEIPT_ACTION_AUTHORIZATION_CLAIM_SHA256",
    SHA256,
  );
  if (receipt.operation.operatorAuditOnly !== true) {
    fail("PRODUCTION_RECEIPT_OPERATOR_AUDIT_ROLE_INVALID");
  }
  if (
    !new Set(["verified", "recovered_verified", "readback_verified"]).has(
      receipt.outcome,
    )
  ) {
    return;
  }
  if (!receipt.result.remoteEvidence) {
    fail("PRODUCTION_RECEIPT_REMOTE_EVIDENCE_REQUIRED");
  }
  if (
    receipt.outcome === "readback_verified" ||
    receipt.outcome === "recovered_verified"
  ) {
    if (receipt.result.cleanupStatus !== "not_applicable") {
      fail("PRODUCTION_RECEIPT_READBACK_CLEANUP_INVALID");
    }
    return;
  }
  if (receipt.kind === "spazaone_catalog_full_reconciliation") {
    if (receipt.result.cleanupStatus !== "not_applicable") {
      fail("PRODUCTION_RECEIPT_RECONCILIATION_CLEANUP_INVALID");
    }
  } else if (receipt.result.cleanupStatus !== "deleted") {
    fail("PRODUCTION_RECEIPT_DEPLOYMENT_CLEANUP_INVALID");
  }
}

function parseFirebaseProjects(payload) {
  const rows = Array.isArray(payload)
    ? payload
    : Array.isArray(payload?.result)
      ? payload.result
      : null;
  if (!rows) return null;
  const ids = rows.map((row) => String(row?.projectId ?? ""));
  if (
    ids.some((id) => !/^[a-z][a-z0-9-]{4,29}$/.test(id)) ||
    new Set(ids).size !== ids.length
  ) {
    return null;
  }
  return ids;
}

async function assertExecutableIdentity(
  descriptor,
  { lstatImpl = lstat, realpathImpl = realpath, readFileImpl = readFile } = {},
) {
  let linkStat;
  let resolved;
  let resolvedStat;
  let bytes;
  try {
    linkStat = await lstatImpl(descriptor.executablePath);
    resolved = await realpathImpl(descriptor.executablePath);
    resolvedStat = await lstatImpl(resolved);
    bytes = await readFileImpl(resolved);
  } catch (_) {
    fail("PRODUCTION_CLI_IDENTITY_UNVERIFIED");
  }
  try {
    if (
      (!linkStat.isFile() && !linkStat.isSymbolicLink()) ||
      resolved !== descriptor.executableRealpath ||
      !resolvedStat.isFile() ||
      resolvedStat.isSymbolicLink() ||
      resolvedStat.nlink < 1 ||
      sha256(bytes) !== descriptor.executableSha256
    ) {
      fail("PRODUCTION_CLI_IDENTITY_MISMATCH");
    }
  } finally {
    bytes?.fill?.(0);
  }
}

/**
 * Verifies local executable identity first, then the explicitly selected
 * Firebase account/project. It never relies on the ambient active project.
 */
export async function assertPinnedProductionToolchain({
  execFileImpl = execFile,
  environment = process.env,
  fsImpl,
} = {}) {
  await assertExecutableIdentity(PINNED_NODE_RUNTIME, fsImpl);
  await assertExecutableIdentity(PINNED_FIREBASE_CLI, fsImpl);
  await assertExecutableIdentity(PINNED_GCLOUD_CLI, fsImpl);
  const safeNames = new Set([
    "HOME",
    "USER",
    "LOGNAME",
    "TMPDIR",
    "SHELL",
    "TERM",
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
  ]);
  const childEnvironment = {
    PATH: "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
  };
  for (const [key, value] of Object.entries(environment)) {
    if (safeNames.has(key) && typeof value === "string") {
      childEnvironment[key] = value;
    }
  }
  let firebaseVersion;
  let gcloudVersion;
  let firebaseProjects;
  let gcloudAccounts;
  try {
    firebaseVersion = String(
      (
        await execFileImpl(PINNED_FIREBASE_CLI.executablePath, ["--version"], {
          encoding: "utf8",
          env: childEnvironment,
        })
      ).stdout ?? "",
    )
      .trim()
      .split(/\s+/)[0];
    gcloudVersion = JSON.parse(
      String(
        (
          await execFileImpl(
            PINNED_GCLOUD_CLI.executablePath,
            ["version", "--format=json"],
            { encoding: "utf8", env: childEnvironment },
          )
        ).stdout ?? "",
      ),
    )?.["Google Cloud SDK"];
    firebaseProjects = parseFirebaseProjects(
      JSON.parse(
        String(
          (
            await execFileImpl(
              PINNED_FIREBASE_CLI.executablePath,
              [
                "--account",
                PRODUCTION_FIREBASE_ACCOUNT,
                "--project",
                PRODUCTION_FIREBASE_PROJECT_ID,
                "--non-interactive",
                "--json",
                "projects:list",
              ],
              { encoding: "utf8", env: childEnvironment },
            )
          ).stdout ?? "",
        ),
      ),
    );
    gcloudAccounts = String(
      (
        await execFileImpl(
          PINNED_GCLOUD_CLI.executablePath,
          [
            "auth",
            "list",
            `--filter=account:${PRODUCTION_FIREBASE_ACCOUNT}`,
            "--format=value(account)",
          ],
          { encoding: "utf8", env: childEnvironment },
        )
      ).stdout ?? "",
    )
      .trim()
      .split(/\s+/)
      .filter(Boolean);
  } catch (_) {
    fail("PRODUCTION_CLI_ACCOUNT_PROJECT_UNVERIFIED");
  }
  if (
    firebaseVersion !== PINNED_FIREBASE_CLI.version ||
    gcloudVersion !== PINNED_GCLOUD_CLI.version ||
    !firebaseProjects?.includes(PRODUCTION_FIREBASE_PROJECT_ID) ||
    JSON.stringify(gcloudAccounts) !==
      JSON.stringify([PRODUCTION_FIREBASE_ACCOUNT])
  ) {
    fail("PRODUCTION_CLI_ACCOUNT_PROJECT_MISMATCH");
  }
  return productionReceiptToolchain();
}

function receiptWithoutSeal(receipt) {
  const rest = { ...receipt };
  delete rest.redactedReceiptSha256;
  return rest;
}

function assertChronology(receipt) {
  const ordered = [
    ["ACTION_STARTED_AT", receipt.actionStartedAt],
    ["DISPATCH_STARTED_AT", receipt.dispatchStartedAt],
    ["ACTION_COMPLETED_AT", receipt.actionCompletedAt],
    ["VERIFIED_AT", receipt.verifiedAt],
  ];
  let previous = -Infinity;
  for (const [label, value] of ordered) {
    const milliseconds = Date.parse(timestamp(value, label));
    if (milliseconds < previous) fail("PRODUCTION_RECEIPT_CHRONOLOGY_INVALID");
    previous = milliseconds;
  }
}

function assertRedacted(value) {
  const forbiddenKey =
    /(?:^|_)(?:token|secret|password|credential|phone|recipient|customer|merchant|callback|webhook)(?:$|_)/i;
  const forbiddenValue =
    /(?:bearer\s+|-----BEGIN [A-Z ]+PRIVATE KEY-----|https?:\/\/[^\s]*[?&](?:access_token|token|secret)=)/i;
  const walk = (current) => {
    if (Array.isArray(current)) {
      current.forEach(walk);
      return;
    }
    if (current && typeof current === "object") {
      for (const [key, child] of Object.entries(current)) {
        if (key !== "senderPhoneNumberId" && forbiddenKey.test(key)) {
          fail("PRODUCTION_RECEIPT_SENSITIVE_KEY");
        }
        walk(child);
      }
      return;
    }
    if (typeof current === "string" && forbiddenValue.test(current)) {
      fail("PRODUCTION_RECEIPT_SENSITIVE_VALUE");
    }
  };
  walk(value);
}

export function validateProductionWriteReceipt(receipt) {
  exactKeys(receipt, RECEIPT_KEYS, "PRODUCTION_RECEIPT");
  if (receipt.schemaVersion !== 4) fail("PRODUCTION_RECEIPT_VERSION_INVALID");
  if (
    !new Set([
      "spazaone_catalog_function_deployment",
      "spazaone_catalog_policy_deployment",
      "spazaone_catalog_full_reconciliation",
    ]).has(receipt.kind)
  ) {
    fail("PRODUCTION_RECEIPT_KIND_INVALID");
  }
  if (
    !new Set([
      "verified",
      "needs_review",
      "recovered_verified",
      "readback_verified",
    ]).has(receipt.outcome)
  ) {
    fail("PRODUCTION_RECEIPT_OUTCOME_INVALID");
  }
  assertChronology(receipt);
  exactObject(receipt.authority, PRODUCTION_WRITE_AUTHORITY, "AUTHORITY");
  exactObject(receipt.target, PRODUCTION_WRITE_TARGET, "TARGET");
  exactKeys(receipt.toolchain, TOOLCHAIN_KEYS, "TOOLCHAIN");
  if (
    receipt.toolchain.nodeExecutablePath !==
      PINNED_NODE_RUNTIME.executablePath ||
    receipt.toolchain.nodeExecutableRealpath !==
      PINNED_NODE_RUNTIME.executableRealpath ||
    receipt.toolchain.nodeExecutableSha256 !==
      PINNED_NODE_RUNTIME.executableSha256 ||
    receipt.toolchain.nodeVersion !== PINNED_NODE_RUNTIME.version ||
    receipt.toolchain.firebaseCliExecutablePath !==
      PINNED_FIREBASE_CLI.executablePath ||
    receipt.toolchain.firebaseCliExecutableRealpath !==
      PINNED_FIREBASE_CLI.executableRealpath ||
    receipt.toolchain.firebaseCliExecutableSha256 !==
      PINNED_FIREBASE_CLI.executableSha256 ||
    receipt.toolchain.firebaseCliVersion !== PINNED_FIREBASE_CLI.version ||
    receipt.toolchain.gcloudCliExecutablePath !==
      PINNED_GCLOUD_CLI.executablePath ||
    receipt.toolchain.gcloudCliExecutableRealpath !==
      PINNED_GCLOUD_CLI.executableRealpath ||
    receipt.toolchain.gcloudCliExecutableSha256 !==
      PINNED_GCLOUD_CLI.executableSha256 ||
    receipt.toolchain.gcloudCliVersion !== PINNED_GCLOUD_CLI.version
  ) {
    fail("PRODUCTION_RECEIPT_TOOLCHAIN_MISMATCH");
  }
  string(receipt.appCommit, "APP_COMMIT", COMMIT);
  exactKeys(receipt.operation, OPERATION_KEYS, "OPERATION");
  string(receipt.operation.lane, "OPERATION_LANE", /^[a-z][a-z0-9-]{1,63}$/);
  string(
    receipt.operation.selector,
    "OPERATION_SELECTOR",
    /^[A-Za-z0-9:,._-]{1,2000}$/,
  );
  string(receipt.operation.sourceSha256, "OPERATION_SOURCE_SHA256", SHA256);
  nullableSha256(
    receipt.operation.configurationSha256,
    "OPERATION_CONFIGURATION_SHA256",
  );
  string(
    receipt.operation.candidateManifestSha256,
    "OPERATION_CANDIDATE_MANIFEST_SHA256",
    SHA256,
  );
  string(
    receipt.operation.operationInputSha256,
    "OPERATION_INPUT_SHA256",
    SHA256,
  );
  exactKeys(receipt.lineage, LINEAGE_KEYS, "LINEAGE");
  if (
    !new Set([
      "direct_write",
      "reviewed_resume_write",
      "recovered_readback",
      "policy_readback",
    ]).has(receipt.lineage.mode)
  ) {
    fail("PRODUCTION_RECEIPT_LINEAGE_MODE_INVALID");
  }
  if (receipt.lineage.mode === "direct_write") {
    if (receipt.lineage.priorReceiptSha256 !== null) {
      fail("PRODUCTION_RECEIPT_LINEAGE_INVALID");
    }
  } else {
    string(
      receipt.lineage.priorReceiptSha256,
      "PRODUCTION_RECEIPT_PRIOR_RECEIPT_SHA256",
      SHA256,
    );
  }
  exactKeys(receipt.result, RESULT_KEYS, "RESULT");
  if (
    receipt.result.commandExitZero !== null &&
    typeof receipt.result.commandExitZero !== "boolean"
  ) {
    fail("RESULT_COMMAND_EXIT_INVALID");
  }
  if (
    !new Set(["verified", "needs_review", "not_performed"]).has(
      receipt.result.readbackStatus,
    )
  ) {
    fail("RESULT_READBACK_STATUS_INVALID");
  }
  if (
    !new Set(["deleted", "not_applicable", "needs_review"]).has(
      receipt.result.cleanupStatus,
    )
  ) {
    fail("RESULT_CLEANUP_STATUS_INVALID");
  }
  if (receipt.result.providerScratchEvidence !== null) {
    validateProviderScratchEvidence(receipt.result.providerScratchEvidence);
  }
  if (
    receipt.outcome === "verified" &&
    new Set([
      "spazaone_catalog_function_deployment",
      "spazaone_catalog_policy_deployment",
    ]).has(receipt.kind) &&
    receipt.result.providerScratchEvidence === null
  ) {
    fail("PRODUCTION_RECEIPT_PROVIDER_SCRATCH_EVIDENCE_REQUIRED");
  }
  if (receipt.result.remoteEvidence !== null) {
    validateStoredRemoteEvidence(receipt.result.remoteEvidence, {
      kind: receipt.kind,
      appCommit: receipt.appCommit,
      lane: receipt.operation.lane,
      selector: receipt.operation.selector,
      sourceSha256: receipt.operation.sourceSha256,
      configurationSha256: receipt.operation.configurationSha256,
      operationInputSha256: receipt.operation.operationInputSha256,
      actionStartedAt: receipt.actionStartedAt,
      actionCompletedAt: receipt.actionCompletedAt,
      verifiedAt: receipt.verifiedAt,
    });
  }
  if (
    receipt.result.errorCode !== null &&
    !SAFE_CODE.test(receipt.result.errorCode)
  ) {
    fail("RESULT_ERROR_CODE_INVALID");
  }
  if (
    typeof receipt.remoteWriteAttempted !== "boolean" ||
    receipt.retryAllowed !== false
  ) {
    fail("PRODUCTION_RECEIPT_WRITE_POLICY_INVALID");
  }
  if (receipt.outcome === "verified") {
    if (
      receipt.remoteWriteAttempted !== true ||
      receipt.needsReview !== false ||
      receipt.result.commandExitZero !== true ||
      receipt.result.readbackStatus !== "verified" ||
      receipt.result.cleanupStatus === "needs_review" ||
      receipt.result.errorCode !== null
    ) {
      fail("PRODUCTION_RECEIPT_VERIFIED_RESULT_INVALID");
    }
    if (
      (receipt.lineage.mode === "reviewed_resume_write" &&
        receipt.kind !== "spazaone_catalog_full_reconciliation") ||
      !new Set(["direct_write", "reviewed_resume_write"]).has(
        receipt.lineage.mode,
      )
    ) {
      fail("PRODUCTION_RECEIPT_VERIFIED_LINEAGE_INVALID");
    }
  } else if (receipt.outcome === "needs_review") {
    if (
      receipt.remoteWriteAttempted !== true ||
      receipt.needsReview !== true ||
      receipt.result.errorCode === null
    ) {
      fail("PRODUCTION_RECEIPT_REVIEW_RESULT_INVALID");
    }
    if (
      !new Set(["direct_write", "reviewed_resume_write"]).has(
        receipt.lineage.mode,
      ) ||
      (receipt.lineage.mode === "reviewed_resume_write" &&
        receipt.kind !== "spazaone_catalog_full_reconciliation")
    ) {
      fail("PRODUCTION_RECEIPT_REVIEW_LINEAGE_INVALID");
    }
  } else {
    const recovered = receipt.outcome === "recovered_verified";
    if (
      receipt.remoteWriteAttempted !== false ||
      receipt.needsReview !== false ||
      receipt.result.commandExitZero !== null ||
      receipt.result.readbackStatus !== "verified" ||
      receipt.result.cleanupStatus !== "not_applicable" ||
      receipt.result.errorCode !== null ||
      !receipt.result.remoteEvidence ||
      (recovered && receipt.lineage.mode !== "recovered_readback") ||
      (!recovered &&
        (receipt.kind !== "spazaone_catalog_policy_deployment" ||
          receipt.lineage.mode !== "policy_readback"))
    ) {
      fail("PRODUCTION_RECEIPT_READBACK_RESULT_INVALID");
    }
  }
  string(receipt.redactedReceiptSha256, "PRODUCTION_RECEIPT_SHA256", SHA256);
  if (
    receipt.redactedReceiptSha256 !==
    canonicalSha256(receiptWithoutSeal(receipt))
  ) {
    fail("PRODUCTION_RECEIPT_SEAL_INVALID");
  }
  assertOperationCrossBinding(receipt);
  assertRedacted(receipt);
  // This is schema/cross-binding validation only. It deliberately does not
  // confer production authority, even when auditing a historical record whose
  // stored outcome is `verified`.
  return { structurallyValid: true, outcome: receipt.outcome };
}

function sealProductionWriteReceipt(receipt) {
  const record = plainObject(receipt, "PRODUCTION_RECEIPT");
  // Verified receipts are authority records, not self-attested hashes. While
  // every production executor is disabled, no importable code path may mint
  // one. A future reviewed executor must keep its attestation and closure
  // operation module-private and bind it to the real candidate loader and
  // remote collectors before this gate can be changed.
  if (record.outcome !== "needs_review") {
    fail("PRODUCTION_RECEIPT_ATTESTATION_REQUIRED");
  }
  if (Object.hasOwn(record, "redactedReceiptSha256")) {
    fail("PRODUCTION_RECEIPT_ALREADY_SEALED");
  }
  const sealed = {
    ...record,
    redactedReceiptSha256: canonicalSha256(record),
  };
  validateProductionWriteReceipt(sealed);
  return sealed;
}

export function productionReceiptToolchain() {
  return {
    nodeExecutablePath: PINNED_NODE_RUNTIME.executablePath,
    nodeExecutableRealpath: PINNED_NODE_RUNTIME.executableRealpath,
    nodeExecutableSha256: PINNED_NODE_RUNTIME.executableSha256,
    nodeVersion: PINNED_NODE_RUNTIME.version,
    firebaseCliExecutablePath: PINNED_FIREBASE_CLI.executablePath,
    firebaseCliExecutableRealpath: PINNED_FIREBASE_CLI.executableRealpath,
    firebaseCliExecutableSha256: PINNED_FIREBASE_CLI.executableSha256,
    firebaseCliVersion: PINNED_FIREBASE_CLI.version,
    gcloudCliExecutablePath: PINNED_GCLOUD_CLI.executablePath,
    gcloudCliExecutableRealpath: PINNED_GCLOUD_CLI.executableRealpath,
    gcloudCliExecutableSha256: PINNED_GCLOUD_CLI.executableSha256,
    gcloudCliVersion: PINNED_GCLOUD_CLI.version,
  };
}

export function buildNeedsReviewProductionWriteReceipt(input) {
  exactKeys(input, BUILD_RECEIPT_INPUT_KEYS, "PRODUCTION_RECEIPT_INPUT");
  if (input.outcome !== "needs_review") {
    fail("PRODUCTION_RECEIPT_ATTESTATION_REQUIRED");
  }
  const {
    kind,
    outcome,
    actionStartedAt,
    dispatchStartedAt,
    actionCompletedAt,
    verifiedAt,
    appCommit,
    lane,
    selector,
    sourceSha256,
    configurationSha256,
    candidateManifest,
    candidateManifestSha256,
    operationInputSha256,
    actionAuthorizationSha256,
    actionAuthorizationClaimSha256,
    commandExitZero,
    readbackStatus,
    cleanupStatus,
    remoteEvidence,
    errorCode,
  } = input;
  string(appCommit, "APP_COMMIT", COMMIT);
  string(candidateManifestSha256, "CANDIDATE_MANIFEST_SHA256", SHA256);
  string(operationInputSha256, "OPERATION_INPUT_SHA256", SHA256);
  string(actionAuthorizationSha256, "ACTION_AUTHORIZATION_SHA256", SHA256);
  string(
    actionAuthorizationClaimSha256,
    "ACTION_AUTHORIZATION_CLAIM_SHA256",
    SHA256,
  );
  validateCandidateManifestBinding({
    candidateManifest,
    candidateManifestSha256,
    kind,
    appCommit,
    lane,
    selector,
    operationInputSha256,
  });
  const normalizedRemoteEvidence =
    remoteEvidence === null
      ? null
      : normalizeRemoteEvidence(remoteEvidence, {
          kind,
          appCommit,
          lane,
          selector,
          sourceSha256,
          configurationSha256,
          operationInputSha256,
          actionStartedAt,
          actionCompletedAt,
          verifiedAt,
        });
  return sealProductionWriteReceipt({
    schemaVersion: 4,
    kind,
    outcome,
    actionStartedAt,
    dispatchStartedAt,
    actionCompletedAt,
    verifiedAt,
    authority: { ...PRODUCTION_WRITE_AUTHORITY },
    target: { ...PRODUCTION_WRITE_TARGET },
    toolchain: productionReceiptToolchain(),
    appCommit,
    operation: {
      lane,
      selector,
      sourceSha256,
      configurationSha256,
      candidateManifestSha256,
      operationInputSha256,
      actionAuthorizationSha256,
      actionAuthorizationClaimSha256,
      operatorAuditOnly: true,
    },
    lineage: {
      mode: "direct_write",
      priorReceiptSha256: null,
    },
    result: {
      commandExitZero,
      readbackStatus,
      cleanupStatus,
      providerScratchEvidence: null,
      remoteEvidence: normalizedRemoteEvidence,
      errorCode,
    },
    remoteWriteAttempted: true,
    needsReview: outcome === "needs_review",
    retryAllowed: false,
  });
}

async function missing(pathname, fsImpl) {
  try {
    await fsImpl.lstat(pathname);
    return false;
  } catch (error) {
    if (error?.code === "ENOENT") return true;
    throw error;
  }
}

async function readFileHandleExactly(handle, length) {
  const bytes = Buffer.alloc(length);
  let offset = 0;
  while (offset < length) {
    const { bytesRead } = await handle.read(
      bytes,
      offset,
      length - offset,
      offset,
    );
    if (bytesRead < 1) break;
    offset += bytesRead;
  }
  if (offset !== length) {
    bytes.fill(0);
    fail("PRODUCTION_RECEIPT_VERIFICATION_UNCERTAIN", {
      targetMayExist: true,
    });
  }
  return bytes;
}

async function persistProductionWriteReceipt(
  receipt,
  receiptPath,
  {
    fsImpl = { link, lstat, open, readFile, realpath, unlink },
    uuid = randomUUID,
  } = {},
) {
  validateProductionWriteReceipt(receipt);
  if (
    typeof receiptPath !== "string" ||
    !path.isAbsolute(receiptPath) ||
    path.resolve(receiptPath) !== receiptPath
  ) {
    fail("PRODUCTION_RECEIPT_PATH_INVALID");
  }
  const parent = path.dirname(receiptPath);
  const name = path.basename(receiptPath);
  let parentStat;
  try {
    parentStat = await fsImpl.lstat(parent);
    if (
      !parentStat.isDirectory() ||
      parentStat.isSymbolicLink() ||
      (await fsImpl.realpath(parent)) !== parent ||
      !(await missing(receiptPath, fsImpl))
    ) {
      fail("PRODUCTION_RECEIPT_TARGET_UNSAFE");
    }
  } catch (error) {
    if (error instanceof ProductionReceiptError) throw error;
    fail("PRODUCTION_RECEIPT_TARGET_UNSAFE");
  }

  const bytes = Buffer.from(`${canonicalJson(receipt)}\n`, "utf8");
  const temporaryPath = path.join(parent, `.${name}.tmp-${uuid()}`);
  let handle;
  let targetHandle;
  let linked = false;
  let directoryHandle;
  try {
    handle = await fsImpl.open(temporaryPath, "wx", 0o600);
    await handle.writeFile(bytes);
    await handle.chmod(0o600);
    await handle.sync();
    const temporaryStat = await handle.stat();
    await fsImpl.link(temporaryPath, receiptPath);
    linked = true;

    const postLinkParentStat = await fsImpl.lstat(parent);
    targetHandle = await fsImpl.open(
      receiptPath,
      fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW,
    );
    const targetStatBeforeRead = await targetHandle.stat();
    const persisted = await readFileHandleExactly(targetHandle, bytes.length);
    const targetStatAfterRead = await targetHandle.stat();
    if (
      !postLinkParentStat.isDirectory() ||
      postLinkParentStat.isSymbolicLink() ||
      postLinkParentStat.dev !== parentStat.dev ||
      postLinkParentStat.ino !== parentStat.ino ||
      (await fsImpl.realpath(parent)) !== parent ||
      !targetStatBeforeRead.isFile() ||
      targetStatBeforeRead.isSymbolicLink() ||
      targetStatBeforeRead.dev !== temporaryStat.dev ||
      targetStatBeforeRead.ino !== temporaryStat.ino ||
      targetStatBeforeRead.nlink !== 2 ||
      (targetStatBeforeRead.mode & 0o777) !== 0o600 ||
      targetStatBeforeRead.size !== bytes.length ||
      targetStatAfterRead.dev !== temporaryStat.dev ||
      targetStatAfterRead.ino !== temporaryStat.ino ||
      targetStatAfterRead.nlink !== 2 ||
      !persisted.equals(bytes)
    ) {
      fail("PRODUCTION_RECEIPT_VERIFICATION_UNCERTAIN", {
        targetMayExist: true,
      });
    }
    directoryHandle = await fsImpl.open(parent, "r");
    const openedParentStat = await directoryHandle.stat();
    if (
      !openedParentStat.isDirectory() ||
      openedParentStat.dev !== parentStat.dev ||
      openedParentStat.ino !== parentStat.ino ||
      openedParentStat.nlink !== postLinkParentStat.nlink
    ) {
      fail("PRODUCTION_RECEIPT_VERIFICATION_UNCERTAIN", {
        targetMayExist: true,
      });
    }
    await directoryHandle.sync();
    await fsImpl.unlink(temporaryPath);
    await directoryHandle.sync();
    const postUnlinkParentStat = await directoryHandle.stat();
    if (
      !postUnlinkParentStat.isDirectory() ||
      postUnlinkParentStat.dev !== parentStat.dev ||
      postUnlinkParentStat.ino !== parentStat.ino ||
      postUnlinkParentStat.nlink < 1
    ) {
      fail("PRODUCTION_RECEIPT_VERIFICATION_UNCERTAIN", {
        targetMayExist: true,
      });
    }

    const finalPersisted = await readFileHandleExactly(
      targetHandle,
      bytes.length,
    );
    const finalTargetHandleStat = await targetHandle.stat();
    const finalTargetStat = await fsImpl.lstat(receiptPath);
    const finalOpenedParentStat = await directoryHandle.stat();
    const finalParentStat = await fsImpl.lstat(parent);
    if (
      !finalParentStat.isDirectory() ||
      finalParentStat.isSymbolicLink() ||
      finalParentStat.dev !== parentStat.dev ||
      finalParentStat.ino !== parentStat.ino ||
      finalParentStat.nlink !== postUnlinkParentStat.nlink ||
      finalOpenedParentStat.dev !== parentStat.dev ||
      finalOpenedParentStat.ino !== parentStat.ino ||
      finalOpenedParentStat.nlink !== postUnlinkParentStat.nlink ||
      (await fsImpl.realpath(parent)) !== parent ||
      !(await missing(temporaryPath, fsImpl)) ||
      finalTargetHandleStat.dev !== temporaryStat.dev ||
      finalTargetHandleStat.ino !== temporaryStat.ino ||
      finalTargetHandleStat.nlink !== 1 ||
      (finalTargetHandleStat.mode & 0o777) !== 0o600 ||
      finalTargetHandleStat.size !== bytes.length ||
      !finalTargetStat.isFile() ||
      finalTargetStat.isSymbolicLink() ||
      finalTargetStat.dev !== temporaryStat.dev ||
      finalTargetStat.ino !== temporaryStat.ino ||
      finalTargetStat.nlink !== 1 ||
      (finalTargetStat.mode & 0o777) !== 0o600 ||
      finalTargetStat.size !== bytes.length ||
      !finalPersisted.equals(bytes)
    ) {
      fail("PRODUCTION_RECEIPT_VERIFICATION_UNCERTAIN", {
        targetMayExist: true,
      });
    }
    await targetHandle.close();
    targetHandle = undefined;
    await handle.close();
    handle = undefined;
    await directoryHandle.close();
    directoryHandle = undefined;
    return {
      persisted: true,
      path: receiptPath,
      mode: "0600",
      bytes: bytes.length,
      redactedReceiptSha256: receipt.redactedReceiptSha256,
    };
  } catch (error) {
    try {
      await handle?.close();
    } catch (_) {
      // Preserve the primary persistence failure.
    }
    try {
      await targetHandle?.close();
    } catch (_) {
      // Preserve the primary persistence failure.
    }
    try {
      await directoryHandle?.close();
    } catch (_) {
      // Preserve the primary persistence failure.
    }
    try {
      await fsImpl.unlink(temporaryPath);
    } catch (_) {
      // Best-effort cleanup; linked targets are reported as uncertain below.
    }
    if (error instanceof ProductionReceiptError) throw error;
    throw new ProductionReceiptError(
      linked
        ? "PRODUCTION_RECEIPT_PERSISTENCE_UNCERTAIN"
        : "PRODUCTION_RECEIPT_PERSISTENCE_FAILED",
      { targetMayExist: linked },
    );
  } finally {
    bytes.fill(0);
  }
}

/**
 * Persists only an explicitly unresolved production-write record. This keeps
 * the no-replace, inode-bound, fsync-backed evidence path usable after an
 * ambiguous dispatch without allowing an importer to turn a structurally
 * self-consistent object into verified authority evidence.
 */
export async function persistNeedsReviewProductionWriteReceipt(
  receipt,
  receiptPath,
  options,
) {
  let snapshot;
  try {
    snapshot = structuredClone(receipt);
  } catch (_) {
    fail("PRODUCTION_RECEIPT_SNAPSHOT_INVALID");
  }
  validateProductionWriteReceipt(snapshot);
  if (snapshot.outcome !== "needs_review" || snapshot.needsReview !== true) {
    fail("PRODUCTION_RECEIPT_ATTESTATION_REQUIRED");
  }
  return persistProductionWriteReceipt(snapshot, receiptPath, options);
}
