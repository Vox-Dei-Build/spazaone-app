#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import {
  CATALOG_FUNCTION_LANES,
  CATALOG_POLICY_LANES,
  catalogFunctionSelector,
  catalogPolicySourceContract,
  validateCatalogDeploymentDotenv,
} from "./guard-whatsapp-catalog-functions-deploy.mjs";
import {
  APP_REPOSITORY_ROOT,
  FROZEN_APP_MAIN_COMMIT,
  PRODUCTION_CANDIDATE_RECEIPT_NAMES,
  ProductionCandidateManifestError,
  createCanonicalProductionCandidateManifest,
} from "./production-candidate-manifest.mjs";

const MAX_OPERATION_INPUT_BYTES = 64 * 1024;

function fail(code) {
  throw new ProductionCandidateManifestError(code);
}

function parseArguments(argv) {
  const values = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith("--") || argument.includes("=")) {
      fail("PRODUCTION_CANDIDATE_CREATOR_ARGUMENT_INVALID");
    }
    const key = argument.slice(2);
    const value = argv[index + 1];
    if (!value || value.startsWith("--") || values.has(key)) {
      fail("PRODUCTION_CANDIDATE_CREATOR_ARGUMENT_INVALID");
    }
    values.set(key, value);
    index += 1;
  }
  const allowed = new Set([
    "operation-kind",
    "lane",
    "expected-app-commit",
    "expected-current-main-commit",
    "output-path",
    "app-build-lint-receipt-path",
    "app-whatsapp-catalog-tests-receipt-path",
    "independent-production-review-receipt-path",
  ]);
  if ([...values.keys()].some((key) => !allowed.has(key))) {
    fail("PRODUCTION_CANDIDATE_CREATOR_ARGUMENT_FORBIDDEN");
  }
  const operationKind = String(values.get("operation-kind") ?? "");
  const lane = String(values.get("lane") ?? "");
  const expectedAppCommit = String(values.get("expected-app-commit") ?? "");
  const expectedCurrentMainCommit = String(
    values.get("expected-current-main-commit") ?? "",
  );
  const outputPath = String(values.get("output-path") ?? "");
  if (
    !new Set([
      "function_deployment",
      "policy_deployment",
      "full_reconciliation",
    ]).has(operationKind) ||
    !/^[a-f0-9]{40}$/.test(expectedAppCommit) ||
    expectedCurrentMainCommit !== FROZEN_APP_MAIN_COMMIT ||
    !path.isAbsolute(outputPath) ||
    path.resolve(outputPath) !== outputPath
  ) {
    fail("PRODUCTION_CANDIDATE_CREATOR_ARGUMENT_INVALID");
  }
  const evidenceReceiptPaths = {
    appBuildLintReceiptSha256: String(
      values.get("app-build-lint-receipt-path") ?? "",
    ),
    appWhatsAppCatalogTestsReceiptSha256: String(
      values.get("app-whatsapp-catalog-tests-receipt-path") ?? "",
    ),
    independentProductionReviewReceiptSha256: String(
      values.get("independent-production-review-receipt-path") ?? "",
    ),
  };
  if (
    PRODUCTION_CANDIDATE_RECEIPT_NAMES.some((name) => {
      const value = evidenceReceiptPaths[name];
      return !path.isAbsolute(value) || path.resolve(value) !== value;
    })
  ) {
    fail("PRODUCTION_CANDIDATE_CREATOR_ARGUMENT_INVALID");
  }
  let selector;
  if (
    operationKind === "function_deployment" &&
    CATALOG_FUNCTION_LANES.includes(lane)
  ) {
    selector = catalogFunctionSelector(lane);
  } else if (
    operationKind === "policy_deployment" &&
    CATALOG_POLICY_LANES.includes(lane)
  ) {
    selector =
      lane === "firestore-rules" ? "firestore:rules" : "firestore:indexes";
  } else if (
    operationKind === "full_reconciliation" &&
    lane === "full-reconciliation"
  ) {
    selector = "functions:runWhatsAppCatalogFullReconciliationBotHttp";
  } else {
    fail("PRODUCTION_CANDIDATE_CREATOR_OPERATION_INVALID");
  }
  return {
    operation: { kind: operationKind, lane, selector },
    expectedAppCommit,
    expectedCurrentMainCommit,
    outputPath,
    evidenceReceiptPaths,
  };
}

async function readStandardInputBytes() {
  const chunks = [];
  let length = 0;
  try {
    for await (const chunk of process.stdin) {
      length += chunk.length;
      if (length > MAX_OPERATION_INPUT_BYTES) {
        fail("PRODUCTION_CANDIDATE_OPERATION_INPUT_TOO_LARGE");
      }
      chunks.push(Buffer.from(chunk));
    }
    if (length < 1) fail("PRODUCTION_CANDIDATE_OPERATION_INPUT_REQUIRED");
    return Buffer.concat(chunks);
  } finally {
    chunks.forEach((chunk) => chunk.fill(0));
  }
}

async function exactOperationInput(options) {
  if (options.operation.kind === "policy_deployment") {
    if (!process.stdin.isTTY) {
      fail("PRODUCTION_CANDIDATE_OPERATION_INPUT_FORBIDDEN");
    }
    const contract = await catalogPolicySourceContract(options.operation.lane);
    return readFile(path.join(APP_REPOSITORY_ROOT, contract.sourcePath));
  }
  if (
    options.operation.kind === "function_deployment" &&
    options.operation.lane === "existing-code"
  ) {
    if (!process.stdin.isTTY) {
      fail("PRODUCTION_CANDIDATE_OPERATION_INPUT_FORBIDDEN");
    }
    return Buffer.from(JSON.stringify({ dotenvSha256: null }), "utf8");
  }
  const bytes = await readStandardInputBytes();
  if (options.operation.kind === "function_deployment") {
    let text = "";
    try {
      text = bytes.toString("utf8");
      validateCatalogDeploymentDotenv({
        lane: options.operation.lane,
        text,
        appCommit: options.expectedAppCommit,
      });
    } finally {
      text = "";
    }
  } else {
    let expectedBytes;
    try {
      const document = JSON.parse(bytes.toString("utf8"));
      const expectedKeys = [
        "pageSize",
        "pollMs",
        "maxSteps",
        "maxElapsedMs",
        "requestTimeoutMs",
      ];
      if (
        !document ||
        typeof document !== "object" ||
        Array.isArray(document) ||
        Object.getPrototypeOf(document) !== Object.prototype ||
        Object.hasOwn(document, "reviewedResume") ||
        JSON.stringify(Object.keys(document)) !==
          JSON.stringify(expectedKeys) ||
        !Number.isSafeInteger(document.pageSize) ||
        document.pageSize < 1 ||
        document.pageSize > 200 ||
        !Number.isSafeInteger(document.pollMs) ||
        document.pollMs < 1_000 ||
        document.pollMs > 10 * 60_000 ||
        !Number.isSafeInteger(document.maxSteps) ||
        document.maxSteps < 1 ||
        document.maxSteps > 100_000 ||
        !Number.isSafeInteger(document.maxElapsedMs) ||
        document.maxElapsedMs < 60_000 ||
        document.maxElapsedMs > 7 * 24 * 60 * 60_000 ||
        !Number.isSafeInteger(document.requestTimeoutMs) ||
        document.requestTimeoutMs < 10_000 ||
        document.requestTimeoutMs > 600_000
      ) {
        fail("PRODUCTION_CANDIDATE_OPERATION_INPUT_INVALID");
      }
      expectedBytes = Buffer.from(JSON.stringify(document), "utf8");
      if (!bytes.equals(expectedBytes)) {
        fail("PRODUCTION_CANDIDATE_OPERATION_INPUT_INVALID");
      }
    } catch (error) {
      if (error instanceof ProductionCandidateManifestError) throw error;
      fail("PRODUCTION_CANDIDATE_OPERATION_INPUT_INVALID");
    } finally {
      expectedBytes?.fill?.(0);
    }
  }
  return bytes;
}

async function main() {
  let operationInputBytes;
  try {
    const options = parseArguments(process.argv.slice(2));
    operationInputBytes = await exactOperationInput(options);
    const result = await createCanonicalProductionCandidateManifest({
      manifestPath: options.outputPath,
      expectedAppCommit: options.expectedAppCommit,
      expectedCurrentMainCommit: options.expectedCurrentMainCommit,
      operation: options.operation,
      operationInputBytes,
      evidenceReceiptPaths: options.evidenceReceiptPaths,
    });
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } catch (error) {
    const safe =
      error instanceof ProductionCandidateManifestError
        ? error
        : new ProductionCandidateManifestError(
            "PRODUCTION_CANDIDATE_CREATION_FAILED",
          );
    process.stderr.write(
      `${JSON.stringify({
        outcome: "blocked",
        code: safe.code,
        remoteWriteAttempted: false,
        retryAllowed: false,
      })}\n`,
    );
    process.exitCode = 1;
  } finally {
    operationInputBytes?.fill?.(0);
  }
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
) {
  await main();
}
