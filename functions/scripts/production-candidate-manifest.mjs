#!/usr/bin/env node

import { execFile as nodeExecFile } from "node:child_process";
import { createHash } from "node:crypto";
import { constants as fsConstants } from "node:fs";
import { lstat, open, realpath } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { nativeCatalogTargetConfigurationDigestSha256 } from "./whatsapp-catalog-production-target.mjs";

const execFile = promisify(nodeExecFile);
const SCRIPT_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
export const APP_REPOSITORY_ROOT = path.resolve(SCRIPT_DIRECTORY, "../..");
export const FROZEN_APP_MAIN_COMMIT =
  "1672538112fc4b725cd74169df9ae72802db69eb";
export const PRODUCTION_CANDIDATE_RECEIPT_NAMES = Object.freeze([
  "appBuildLintReceiptSha256",
  "appWhatsAppCatalogTestsReceiptSha256",
  "independentProductionReviewReceiptSha256",
]);

const SHA1 = /^[a-f0-9]{40}$/;
const SHA256 = /^[a-f0-9]{64}$/;
const MAX_MANIFEST_BYTES = 64 * 1024;
const MANIFEST_KEYS = Object.freeze([
  "schemaVersion",
  "kind",
  "appCommit",
  "governedMainCommit",
  "gitTreeSha1",
  "immutableTargetConfigurationSha256",
  "operation",
  "receipts",
]);
const OPERATION_KEYS = Object.freeze([
  "kind",
  "lane",
  "selector",
  "inputSha256",
]);

export class ProductionCandidateManifestError extends Error {
  constructor(code) {
    super(code);
    this.name = "ProductionCandidateManifestError";
    this.code = code;
    this.retryAllowed = false;
  }
}

function fail(code) {
  throw new ProductionCandidateManifestError(code);
}

function exactKeys(value, expected, label) {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value) ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) {
    fail(`${label}_INVALID`);
  }
  const actual = Object.keys(value).sort();
  const approved = [...expected].sort();
  if (
    actual.length !== approved.length ||
    actual.some((key, index) => key !== approved[index])
  ) {
    fail(`${label}_KEYSET_INVALID`);
  }
}

function canonicalJson(value) {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "boolean"
  ) {
    return JSON.stringify(value);
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) fail("PRODUCTION_CANDIDATE_NUMBER_INVALID");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalJson(item)).join(",")}]`;
  }
  if (!value || typeof value !== "object") {
    fail("PRODUCTION_CANDIDATE_VALUE_INVALID");
  }
  return `{${Object.keys(value)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
    .join(",")}}`;
}

function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}

export function canonicalProductionCandidateManifestBytes(document) {
  return Buffer.from(`${canonicalJson(document)}\n`, "utf8");
}

function strictEnvironment(environment = process.env) {
  const result = { PATH: "/usr/bin:/bin" };
  for (const name of ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG"]) {
    if (typeof environment[name] === "string") result[name] = environment[name];
  }
  return result;
}

export async function resolveProductionCandidateGitTreeSha1({
  appCommit,
  repositoryRoot = APP_REPOSITORY_ROOT,
  execFileImpl = execFile,
  environment = process.env,
} = {}) {
  if (!SHA1.test(String(appCommit ?? ""))) {
    fail("PRODUCTION_CANDIDATE_APP_COMMIT_INVALID");
  }
  let result;
  try {
    result = await execFileImpl(
      "/usr/bin/git",
      ["-C", repositoryRoot, "rev-parse", `${appCommit}^{tree}`],
      { encoding: "utf8", env: strictEnvironment(environment) },
    );
  } catch (_) {
    fail("PRODUCTION_CANDIDATE_GIT_TREE_UNVERIFIED");
  }
  const tree = String(result?.stdout ?? "").trim();
  if (!SHA1.test(tree)) fail("PRODUCTION_CANDIDATE_GIT_TREE_UNVERIFIED");
  return tree;
}

export async function loadAndValidateProductionCandidateManifest({
  manifestPath,
  expectedManifestSha256,
  expectedAppCommit,
  expectedCurrentMainCommit,
  expectedOperation,
  resolveGitTree = resolveProductionCandidateGitTreeSha1,
  fsImpl = { lstat, open, realpath },
} = {}) {
  if (
    typeof manifestPath !== "string" ||
    !path.isAbsolute(manifestPath) ||
    path.resolve(manifestPath) !== manifestPath ||
    !SHA256.test(String(expectedManifestSha256 ?? ""))
  ) {
    fail("PRODUCTION_CANDIDATE_MANIFEST_REFERENCE_INVALID");
  }
  if (
    !SHA1.test(String(expectedAppCommit ?? "")) ||
    expectedCurrentMainCommit !== FROZEN_APP_MAIN_COMMIT
  ) {
    fail("PRODUCTION_CANDIDATE_EXPECTATION_INVALID");
  }

  let before;
  let after;
  let bytes;
  let document;
  let handle;
  try {
    before = await fsImpl.lstat(manifestPath);
    if (
      !before.isFile() ||
      before.isSymbolicLink() ||
      before.nlink !== 1 ||
      before.size < 2 ||
      before.size > MAX_MANIFEST_BYTES ||
      (before.mode & 0o022) !== 0 ||
      (typeof process.geteuid === "function" &&
        before.uid !== process.geteuid()) ||
      (await fsImpl.realpath(manifestPath)) !== manifestPath
    ) {
      fail("PRODUCTION_CANDIDATE_MANIFEST_FILE_UNSAFE");
    }
    handle = await fsImpl.open(
      manifestPath,
      fsConstants.O_RDONLY | fsConstants.O_NOFOLLOW,
    );
    const opened = await handle.stat();
    bytes = await handle.readFile();
    after = await handle.stat();
    const pathAfter = await fsImpl.lstat(manifestPath);
    document = JSON.parse(bytes.toString("utf8"));
    const canonicalBytes = canonicalProductionCandidateManifestBytes(document);
    if (
      !Buffer.isBuffer(bytes) ||
      opened.dev !== before.dev ||
      opened.ino !== before.ino ||
      opened.nlink !== 1 ||
      opened.size !== before.size ||
      after.dev !== before.dev ||
      after.ino !== before.ino ||
      after.nlink !== 1 ||
      after.size !== before.size ||
      (after.mode & 0o777) !== (before.mode & 0o777) ||
      pathAfter.dev !== before.dev ||
      pathAfter.ino !== before.ino ||
      pathAfter.nlink !== 1 ||
      !bytes.equals(canonicalBytes) ||
      createHash("sha256").update(bytes).digest("hex") !==
        expectedManifestSha256
    ) {
      fail("PRODUCTION_CANDIDATE_MANIFEST_CHANGED");
    }
  } catch (error) {
    if (error instanceof ProductionCandidateManifestError) throw error;
    fail("PRODUCTION_CANDIDATE_MANIFEST_UNREADABLE");
  } finally {
    try {
      await handle?.close();
    } catch (_) {
      // The primary validation error remains authoritative.
    }
    bytes?.fill?.(0);
  }

  exactKeys(document, MANIFEST_KEYS, "PRODUCTION_CANDIDATE_MANIFEST");
  exactKeys(
    document.operation,
    OPERATION_KEYS,
    "PRODUCTION_CANDIDATE_OPERATION",
  );
  exactKeys(
    expectedOperation,
    OPERATION_KEYS,
    "EXPECTED_PRODUCTION_CANDIDATE_OPERATION",
  );
  exactKeys(
    document.receipts,
    PRODUCTION_CANDIDATE_RECEIPT_NAMES,
    "PRODUCTION_CANDIDATE_RECEIPTS",
  );
  const receiptDigests = PRODUCTION_CANDIDATE_RECEIPT_NAMES.map((name) =>
    String(document.receipts[name] ?? ""),
  );
  if (
    document.schemaVersion !== 1 ||
    document.kind !== "spazaone_native_catalog_production_candidate" ||
    document.appCommit !== expectedAppCommit ||
    document.governedMainCommit !== expectedCurrentMainCommit ||
    !SHA1.test(String(document.gitTreeSha1 ?? "")) ||
    document.immutableTargetConfigurationSha256 !==
      nativeCatalogTargetConfigurationDigestSha256() ||
    !new Set([
      "function_deployment",
      "policy_deployment",
      "full_reconciliation",
    ]).has(document.operation.kind) ||
    document.operation.kind !== expectedOperation.kind ||
    document.operation.lane !== expectedOperation.lane ||
    document.operation.selector !== expectedOperation.selector ||
    !SHA256.test(String(document.operation.inputSha256 ?? "")) ||
    document.operation.inputSha256 !== expectedOperation.inputSha256 ||
    receiptDigests.some((digest) => !SHA256.test(digest)) ||
    new Set(receiptDigests).size !== receiptDigests.length
  ) {
    fail("PRODUCTION_CANDIDATE_MANIFEST_BINDING_INVALID");
  }
  const actualTree = await resolveGitTree({ appCommit: expectedAppCommit });
  if (actualTree !== document.gitTreeSha1) {
    fail("PRODUCTION_CANDIDATE_GIT_TREE_MISMATCH");
  }
  const authenticatedManifest = deepFreeze(structuredClone(document));
  return {
    manifestSha256: expectedManifestSha256,
    appCommit: document.appCommit,
    governedMainCommit: document.governedMainCommit,
    gitTreeSha1: document.gitTreeSha1,
    immutableTargetConfigurationSha256:
      document.immutableTargetConfigurationSha256,
    operation: { ...document.operation },
    receiptNames: [...PRODUCTION_CANDIDATE_RECEIPT_NAMES],
    receiptSetSha256: createHash("sha256")
      .update(receiptDigests.join("\n"))
      .digest("hex"),
    authenticatedManifest,
  };
}
