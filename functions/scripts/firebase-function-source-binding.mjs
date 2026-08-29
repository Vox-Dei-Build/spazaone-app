import { execFile as nodeExecFile } from "node:child_process";
import { createHash } from "node:crypto";
import { lstat, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

const execFile = promisify(nodeExecFile);
const SHA1 = /^[a-f0-9]{40}$/;
const SHA256 = /^[a-f0-9]{64}$/;
const MAX_FIREBASE_OUTPUT_BYTES = 10 * 1024 * 1024;
// Keep the forbidden module specifier out of this guard's own uploaded bytes;
// the contract scans the complete Firebase package, including this script.
const FIREBASE_PARAMS_MODULE_REFERENCE = Buffer.from(
  ["firebase-functions", "params"].join("/"),
  "utf8",
);

const FIREBASE_TOOLS_ROOT = "/opt/homebrew/lib/node_modules/firebase-tools/lib";

/**
 * These files are the complete firebase-tools 15.21.0 path from source
 * packaging through the firebase-functions-hash label. The executable itself
 * is pinned by production-write-receipt.mjs; these additional pins prevent a
 * same-version module-tree replacement from changing the hash contract.
 */
export const FIREBASE_FUNCTION_HASH_IMPLEMENTATION = Object.freeze([
  Object.freeze({
    path: `${FIREBASE_TOOLS_ROOT}/fsAsync.js`,
    sha256: "c8989264cfe50f902dfd1015a4c060ff36e114cbf24ac63dc5e254284a3ab3a2",
  }),
  Object.freeze({
    path: `${FIREBASE_TOOLS_ROOT}/deploy/functions/prepareFunctionsUpload.js`,
    sha256: "db73eefa9de70e77a0f8bb0f602e87e6a97c067fd8362f8931a54230803e07cb",
  }),
  Object.freeze({
    path: `${FIREBASE_TOOLS_ROOT}/deploy/functions/cache/hash.js`,
    sha256: "08c47bed36408fc1578178d9eceefc970f3bd5b1300132b11dbde37beca3eb5f",
  }),
  Object.freeze({
    path: `${FIREBASE_TOOLS_ROOT}/deploy/functions/cache/applyHash.js`,
    sha256: "0fec597fcc9b0b40a25f24757ccc13178ee44c9e62adc29c1c06de1465007638",
  }),
  Object.freeze({
    path: `${FIREBASE_TOOLS_ROOT}/deploy/functions/prepare.js`,
    sha256: "de1221a9368b8372a8b094fdebdc0b6b562ed9fc6822182b3e97a8fe6b19ac56",
  }),
  Object.freeze({
    path: `${FIREBASE_TOOLS_ROOT}/functions/secrets.js`,
    sha256: "108fba357330ae16ad225c2883d5e4d4989bce742569fbd26aa5f6ba8a0f629b",
  }),
  Object.freeze({
    path: `${FIREBASE_TOOLS_ROOT}/functions/env.js`,
    sha256: "8d6a5e640f8273000e6d0aa3b51eba3ad375d9c1f4214ad97454410e34b91338",
  }),
  Object.freeze({
    path: `${FIREBASE_TOOLS_ROOT}/functionsConfig.js`,
    sha256: "04733fd2f736358e79e0a668f817e442766f462d30148074646f2d48ebe5d043",
  }),
  Object.freeze({
    path: `${FIREBASE_TOOLS_ROOT}/functions/projectConfig.js`,
    sha256: "8c21eb94c7a8d3e534a1b08c58287c6f7cb5cf3fae7afceb6135cbac7495d2ca",
  }),
]);

export const FIREBASE_FUNCTION_SOURCE_IGNORES = Object.freeze([
  "node_modules",
  ".git",
  "firebase-debug.log",
  "firebase-debug.*.log",
  ".runtimeconfig.json",
]);

export class FirebaseFunctionSourceBindingError extends Error {
  constructor(code) {
    super(code);
    this.name = "FirebaseFunctionSourceBindingError";
    this.code = code;
    this.retryAllowed = false;
  }
}

function fail(code) {
  throw new FirebaseFunctionSourceBindingError(code);
}

function hash(algorithm, value) {
  return createHash(algorithm).update(value).digest("hex");
}

function sha1(value) {
  return hash("sha1", value);
}

function sha256(value) {
  return hash("sha256", value);
}

function plainObject(value) {
  return (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    Object.getPrototypeOf(value) === Object.prototype
  );
}

function firebaseSortedKeyValueArray(value) {
  if (typeof value !== "object" || value === null) return value;
  return Object.keys(value)
    .sort()
    .map((key) => ({ key, value: firebaseSortedKeyValueArray(value[key]) }));
}

/** Mirrors prepareFunctionsUpload.convertToSortedKeyValueArray exactly. */
export function firebaseGen1RuntimeConfigHashSha1(
  firebaseConfig,
  legacyRuntimeConfig,
) {
  if (!plainObject(firebaseConfig) || !plainObject(legacyRuntimeConfig)) {
    fail("FIREBASE_RUNTIME_CONFIG_SHAPE_INVALID");
  }
  if (Object.hasOwn(legacyRuntimeConfig, "firebase")) {
    fail("FIREBASE_RUNTIME_CONFIG_RESERVED_NAMESPACE_PRESENT");
  }
  return sha1(
    JSON.stringify(
      firebaseSortedKeyValueArray({
        firebase: firebaseConfig,
        ...legacyRuntimeConfig,
      }),
    ),
  );
}

/** Mirrors cache/hash.getEndpointHash exactly. */
export function firebaseEndpointHashSha1({
  sourceHashSha1,
  environmentVariables,
  secretVersions,
}) {
  if (
    !/^[a-f0-9]{40}(?:\.[a-f0-9]{40})?$/.test(String(sourceHashSha1 ?? "")) ||
    !plainObject(environmentVariables) ||
    !plainObject(secretVersions) ||
    Object.values(environmentVariables).some(
      (value) => typeof value !== "string",
    ) ||
    Object.values(secretVersions).some(
      (value) => typeof value !== "string" || !/^[1-9][0-9]*$/.test(value),
    )
  ) {
    fail("FIREBASE_ENDPOINT_HASH_INPUT_INVALID");
  }
  const environmentHash = sha1(JSON.stringify(environmentVariables));
  const secretsHash = sha1(JSON.stringify(secretVersions));
  return sha1(`${sourceHashSha1}${environmentHash}${secretsHash}`);
}

export async function assertPinnedFirebaseFunctionHashImplementation({
  readFileImpl = readFile,
} = {}) {
  for (const descriptor of FIREBASE_FUNCTION_HASH_IMPLEMENTATION) {
    let bytes;
    try {
      bytes = await readFileImpl(descriptor.path);
    } catch (_) {
      fail("FIREBASE_FUNCTION_HASH_IMPLEMENTATION_UNREADABLE");
    }
    if (!Buffer.isBuffer(bytes) || sha256(bytes) !== descriptor.sha256) {
      bytes?.fill?.(0);
      fail("FIREBASE_FUNCTION_HASH_IMPLEMENTATION_MISMATCH");
    }
    bytes.fill(0);
  }
  return sha256(
    FIREBASE_FUNCTION_HASH_IMPLEMENTATION.map(
      ({ path: implementationPath, sha256: digest }) =>
        `${implementationPath}\u0000${digest}`,
    ).join("\n"),
  );
}

function ignoredFirebaseSourcePath(relativePath) {
  const normalized = relativePath.split(path.sep).join("/");
  const segments = normalized.split("/");
  if (segments.includes("node_modules") || segments.includes(".git")) {
    return true;
  }
  const basename = segments.at(-1) ?? "";
  return (
    basename === "firebase-debug.log" ||
    /^firebase-debug\..*\.log$/.test(basename) ||
    basename === ".runtimeconfig.json"
  );
}

async function walkPackagedFiles(
  root,
  { lstatImpl = lstat, readdirImpl = readdir } = {},
) {
  const files = [];
  const visit = async (directory, relativeDirectory = "") => {
    let entries;
    try {
      entries = await readdirImpl(directory, { withFileTypes: true });
    } catch (_) {
      fail("FIREBASE_CANDIDATE_SOURCE_UNREADABLE");
    }
    entries.sort((left, right) => left.name.localeCompare(right.name));
    for (const entry of entries) {
      const relativePath = relativeDirectory
        ? `${relativeDirectory}/${entry.name}`
        : entry.name;
      if (ignoredFirebaseSourcePath(relativePath)) continue;
      const absolutePath = path.join(root, ...relativePath.split("/"));
      let stat;
      try {
        stat = await lstatImpl(absolutePath);
      } catch (_) {
        fail("FIREBASE_CANDIDATE_SOURCE_UNREADABLE");
      }
      if (stat.isSymbolicLink()) fail("FIREBASE_CANDIDATE_SOURCE_SYMLINK");
      if (stat.isDirectory()) {
        await visit(absolutePath, relativePath);
      } else if (stat.isFile()) {
        files.push(relativePath);
      } else {
        fail("FIREBASE_CANDIDATE_SOURCE_SPECIAL_FILE");
      }
    }
  };
  await visit(root);
  return files.sort();
}

export async function listCandidateFirebasePackageFiles(
  functionsDirectory,
  { lstatImpl = lstat, readdirImpl = readdir } = {},
) {
  if (!path.isAbsolute(String(functionsDirectory ?? ""))) {
    fail("FIREBASE_CANDIDATE_SOURCE_ROOT_INVALID");
  }
  return walkPackagedFiles(functionsDirectory, { lstatImpl, readdirImpl });
}

function parseGitTree(buffer, functionsRelativePath) {
  if (!Buffer.isBuffer(buffer)) fail("FIREBASE_CANDIDATE_GIT_TREE_INVALID");
  const prefix = `${functionsRelativePath}/`;
  const entries = new Map();
  for (const record of buffer.toString("utf8").split("\u0000")) {
    if (!record) continue;
    const match = record.match(/^(100644|100755) blob ([a-f0-9]{40})\t(.+)$/);
    if (!match || !match[3].startsWith(prefix)) {
      fail("FIREBASE_CANDIDATE_GIT_TREE_INVALID");
    }
    const relativePath = match[3].slice(prefix.length);
    if (
      !relativePath ||
      relativePath.includes("\\") ||
      relativePath.split("/").some((segment) => !segment || segment === "..") ||
      entries.has(relativePath)
    ) {
      fail("FIREBASE_CANDIDATE_GIT_TREE_INVALID");
    }
    entries.set(relativePath, { mode: match[1], blobSha1: match[2] });
  }
  if (!entries.size) fail("FIREBASE_CANDIDATE_GIT_TREE_INVALID");
  return entries;
}

async function loadCandidateGitTree({
  repositoryRoot,
  functionsDirectory,
  expectedAppCommit,
  execFileImpl = execFile,
  environment = process.env,
}) {
  const functionsRelativePath = path
    .relative(repositoryRoot, functionsDirectory)
    .split(path.sep)
    .join("/");
  if (
    !functionsRelativePath ||
    functionsRelativePath.startsWith("../") ||
    path.isAbsolute(functionsRelativePath)
  ) {
    fail("FIREBASE_CANDIDATE_SOURCE_ROOT_INVALID");
  }
  let result;
  try {
    result = await execFileImpl(
      "/usr/bin/git",
      [
        "-C",
        repositoryRoot,
        "ls-tree",
        "-rz",
        expectedAppCommit,
        "--",
        functionsRelativePath,
      ],
      {
        encoding: null,
        maxBuffer: MAX_FIREBASE_OUTPUT_BYTES,
        env: environment,
      },
    );
  } catch (_) {
    fail("FIREBASE_CANDIDATE_GIT_TREE_UNVERIFIED");
  }
  const bytes = Buffer.isBuffer(result?.stdout)
    ? result.stdout
    : Buffer.from(String(result?.stdout ?? ""), "utf8");
  try {
    return {
      functionsRelativePath,
      entries: parseGitTree(bytes, functionsRelativePath),
    };
  } finally {
    bytes.fill(0);
  }
}

function gitBlobSha1(bytes) {
  const header = Buffer.from(`blob ${bytes.length}\u0000`, "utf8");
  return createHash("sha1").update(header).update(bytes).digest("hex");
}

function expectedGeneratedFiles(trackedFiles) {
  const generated = [];
  for (const relativePath of trackedFiles) {
    if (
      relativePath.startsWith("src/") &&
      relativePath.endsWith(".ts") &&
      !relativePath.endsWith(".d.ts")
    ) {
      const stem = relativePath.slice("src/".length, -".ts".length);
      generated.push(`lib/${stem}.js`, `lib/${stem}.js.map`);
    }
  }
  return generated.sort();
}

/**
 * Computes the exact base source hash used by firebase-tools packaging and
 * binds every non-generated byte to the reviewed commit's Git blob.
 */
export async function computeCandidateFirebaseSourceContract({
  repositoryRoot,
  functionsDirectory,
  gitFunctionsDirectory = functionsDirectory,
  expectedAppCommit,
  runtimeConfigHashSha1,
  loadGitTree = loadCandidateGitTree,
  readFileImpl = readFile,
  lstatImpl = lstat,
  readdirImpl = readdir,
  assertImplementation = assertPinnedFirebaseFunctionHashImplementation,
  execFileImpl = execFile,
  environment = process.env,
} = {}) {
  if (
    !path.isAbsolute(String(repositoryRoot ?? "")) ||
    !path.isAbsolute(String(functionsDirectory ?? "")) ||
    !path.isAbsolute(String(gitFunctionsDirectory ?? "")) ||
    !SHA1.test(String(expectedAppCommit ?? "")) ||
    !SHA1.test(String(runtimeConfigHashSha1 ?? ""))
  ) {
    fail("FIREBASE_CANDIDATE_SOURCE_INPUT_INVALID");
  }
  const implementationDigestSha256 = await assertImplementation();
  if (!SHA256.test(implementationDigestSha256)) {
    fail("FIREBASE_FUNCTION_HASH_IMPLEMENTATION_MISMATCH");
  }
  const tree = await loadGitTree({
    repositoryRoot,
    functionsDirectory: gitFunctionsDirectory,
    expectedAppCommit,
    execFileImpl,
    environment,
  });
  const trackedFiles = [...tree.entries.keys()].sort();
  const expectedFiles = [
    ...trackedFiles.filter(
      (relativePath) => !ignoredFirebaseSourcePath(relativePath),
    ),
    ...expectedGeneratedFiles(trackedFiles),
  ].sort();
  const actualFiles = await listCandidateFirebasePackageFiles(
    functionsDirectory,
    {
      lstatImpl,
      readdirImpl,
    },
  );
  if (
    expectedFiles.length !== new Set(expectedFiles).size ||
    JSON.stringify(actualFiles) !== JSON.stringify(expectedFiles)
  ) {
    fail("FIREBASE_CANDIDATE_SOURCE_INVENTORY_MISMATCH");
  }
  const packageFileHashes = [];
  const fileEvidence = [];
  let firebaseParamsModuleReferenceCount = 0;
  for (const relativePath of actualFiles) {
    let bytes;
    try {
      bytes = await readFileImpl(
        path.join(functionsDirectory, ...relativePath.split("/")),
      );
    } catch (_) {
      fail("FIREBASE_CANDIDATE_SOURCE_UNREADABLE");
    }
    if (!Buffer.isBuffer(bytes)) {
      fail("FIREBASE_CANDIDATE_SOURCE_UNREADABLE");
    }
    const fileSha1 = sha1(bytes);
    const tracked = tree.entries.get(relativePath);
    if (tracked && gitBlobSha1(bytes) !== tracked.blobSha1) {
      bytes.fill(0);
      fail("FIREBASE_CANDIDATE_SOURCE_GIT_BLOB_MISMATCH");
    }
    if (bytes.includes(FIREBASE_PARAMS_MODULE_REFERENCE)) {
      firebaseParamsModuleReferenceCount += 1;
    }
    packageFileHashes.push(fileSha1);
    fileEvidence.push([relativePath, sha256(bytes)]);
    bytes.fill(0);
  }
  // prepare.js appends every resolved non-internal Firebase parameter to the
  // codebase-level environment before hashing it. This deployment contract has
  // no such entries, so any params-module reference must be reviewed and
  // modeled explicitly before the provider label can be reconstructed safely.
  if (firebaseParamsModuleReferenceCount !== 0) {
    fail("FIREBASE_CANDIDATE_PARAMS_UNSUPPORTED");
  }
  const sourceBaseHashSha1 = sha1(packageFileHashes.sort().join(""));
  const sourceV1HashSha1 = `${sourceBaseHashSha1}.${runtimeConfigHashSha1}`;
  const contractEvidence = {
    schemaVersion: 1,
    expectedAppCommit,
    functionsRelativePath: tree.functionsRelativePath,
    codebase: "default",
    implementationDigestSha256,
    ignoreContractSha256: sha256(
      JSON.stringify(FIREBASE_FUNCTION_SOURCE_IGNORES),
    ),
    packagedFileCount: actualFiles.length,
    generatedFileCount: expectedGeneratedFiles(trackedFiles).length,
    firebaseParamsModuleReferenceCount,
    fileSetSha256: sha256(JSON.stringify(fileEvidence)),
    sourceBaseHashDigestSha256: sha256(sourceBaseHashSha1),
    gen1SourceHashDigestSha256: sha256(sourceV1HashSha1),
    gen2SourceHashDigestSha256: sha256(sourceBaseHashSha1),
  };
  return {
    ...contractEvidence,
    contractSha256: sha256(JSON.stringify(contractEvidence)),
    // Private operational inputs: callers must never serialize these fields.
    sourceV1HashSha1,
    sourceV2HashSha1: sourceBaseHashSha1,
    packageFileEvidence: Object.freeze(
      fileEvidence.map(([relativePath, fileSha256]) =>
        Object.freeze({ relativePath, sha256: fileSha256 }),
      ),
    ),
  };
}

function strictJsonBuffer(result) {
  const bytes = Buffer.isBuffer(result?.stdout)
    ? result.stdout
    : Buffer.from(String(result?.stdout ?? ""), "utf8");
  if (bytes.length < 2 || bytes.length > MAX_FIREBASE_OUTPUT_BYTES) {
    bytes.fill(0);
    fail("FIREBASE_RUNTIME_CONFIG_READBACK_INVALID");
  }
  return bytes;
}

function unwrapFirebaseJson(value) {
  if (plainObject(value) && plainObject(value.result)) return value.result;
  return value;
}

/**
 * Reads the two inputs Firebase itself places in Gen 1 .runtimeconfig.json.
 * Secret-bearing legacy values exist only in this function's memory; the
 * returned value is a one-way SHA-1 component required by Firebase's label.
 */
export async function collectFirebaseGen1RuntimeConfigHashSha1({
  firebaseCliPath,
  projectId,
  account,
  anchorFunctionId,
  execFileImpl = execFile,
  environment = process.env,
} = {}) {
  if (
    firebaseCliPath !== "/opt/homebrew/bin/firebase" ||
    !/^[a-z][a-z0-9-]{4,62}$/.test(String(projectId ?? "")) ||
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(account ?? "")) ||
    !/^[A-Za-z][A-Za-z0-9_-]{0,62}$/.test(String(anchorFunctionId ?? ""))
  ) {
    fail("FIREBASE_RUNTIME_CONFIG_READBACK_INPUT_INVALID");
  }
  const childEnvironment = {
    PATH: "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    FIREBASE_CLI_EXPERIMENTS: "legacyRuntimeConfigCommands",
  };
  for (const name of [
    "HOME",
    "USER",
    "LOGNAME",
    "TMPDIR",
    "SHELL",
    "TERM",
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
  ]) {
    if (typeof environment[name] === "string") {
      childEnvironment[name] = environment[name];
    }
  }
  let listBytes;
  let legacyBytes;
  try {
    const common = [
      "--project",
      projectId,
      "--account",
      account,
      "--non-interactive",
      "--json",
    ];
    listBytes = strictJsonBuffer(
      await execFileImpl(firebaseCliPath, [...common, "functions:list"], {
        encoding: null,
        maxBuffer: MAX_FIREBASE_OUTPUT_BYTES,
        env: childEnvironment,
      }),
    );
    legacyBytes = strictJsonBuffer(
      await execFileImpl(firebaseCliPath, [...common, "functions:config:get"], {
        encoding: null,
        maxBuffer: MAX_FIREBASE_OUTPUT_BYTES,
        env: childEnvironment,
      }),
    );
    const listed = unwrapFirebaseJson(JSON.parse(listBytes.toString("utf8")));
    const endpoints = Array.isArray(listed)
      ? listed
      : Array.isArray(listed?.result)
        ? listed.result
        : null;
    const anchor = endpoints?.filter(
      (endpoint) => String(endpoint?.id ?? "") === anchorFunctionId,
    );
    if (anchor?.length !== 1) {
      fail("FIREBASE_RUNTIME_CONFIG_ANCHOR_INVALID");
    }
    const firebaseConfigText = anchor[0]?.environmentVariables?.FIREBASE_CONFIG;
    if (typeof firebaseConfigText !== "string") {
      fail("FIREBASE_RUNTIME_CONFIG_ANCHOR_INVALID");
    }
    const firebaseConfig = JSON.parse(firebaseConfigText);
    const legacyRuntimeConfig = unwrapFirebaseJson(
      JSON.parse(legacyBytes.toString("utf8")),
    );
    if (
      !plainObject(firebaseConfig) ||
      firebaseConfig.projectId !== projectId ||
      !plainObject(legacyRuntimeConfig)
    ) {
      fail("FIREBASE_RUNTIME_CONFIG_READBACK_INVALID");
    }
    return firebaseGen1RuntimeConfigHashSha1(
      firebaseConfig,
      legacyRuntimeConfig,
    );
  } catch (error) {
    if (error instanceof FirebaseFunctionSourceBindingError) throw error;
    fail("FIREBASE_RUNTIME_CONFIG_READBACK_FAILED");
  } finally {
    listBytes?.fill?.(0);
    legacyBytes?.fill?.(0);
  }
}

function expectedSecretVersionObject(endpoint, expectedSecretKeys) {
  const remote = endpoint?.secretEnvironmentVariables;
  if (!Array.isArray(remote) || remote.length !== expectedSecretKeys.length) {
    return null;
  }
  const result = {};
  for (let index = 0; index < expectedSecretKeys.length; index += 1) {
    const expectedKey = expectedSecretKeys[index];
    const entry = remote[index];
    const secret = String(entry?.secret ?? "");
    const version = String(entry?.version ?? "");
    if (
      String(entry?.key ?? "") !== expectedKey ||
      (secret !== expectedKey && !secret.endsWith(`/secrets/${expectedKey}`)) ||
      !/^[1-9][0-9]*$/.test(version)
    ) {
      return null;
    }
    result[expectedKey] = version;
  }
  return result;
}

function expectedConfiguredBackendEnvironment(
  endpoint,
  configuredEnvironmentEntries,
  projectId,
) {
  const raw = endpoint?.environmentVariables;
  if (!plainObject(raw) || typeof raw.FIREBASE_CONFIG !== "string") return null;
  let firebaseConfig;
  try {
    firebaseConfig = JSON.parse(raw.FIREBASE_CONFIG);
  } catch (_) {
    return null;
  }
  if (!plainObject(firebaseConfig) || firebaseConfig.projectId !== projectId) {
    return null;
  }
  return {
    ...Object.fromEntries(configuredEnvironmentEntries),
    FIREBASE_CONFIG: raw.FIREBASE_CONFIG,
    GCLOUD_PROJECT: projectId,
  };
}

function expectedExistingCodeBackendEnvironment(endpoint, baseline, projectId) {
  if (!plainObject(baseline?.environmentVariables)) return null;
  const firebaseConfig = endpoint?.environmentVariables?.FIREBASE_CONFIG;
  if (typeof firebaseConfig !== "string") return null;
  let parsed;
  try {
    parsed = JSON.parse(firebaseConfig);
  } catch (_) {
    return null;
  }
  if (!plainObject(parsed) || parsed.projectId !== projectId) return null;
  return {
    FIREBASE_CONFIG: firebaseConfig,
    GCLOUD_PROJECT: projectId,
  };
}

/**
 * Proves each remote firebase-functions-hash label was computed from this
 * candidate source and the exact codebase-level backend environment plus
 * endpoint secret-version inputs. Firebase adds EVENTARC and merges preserved
 * values only on each endpoint after setting wantBackend.environmentVariables;
 * cache/hash.js hashes the latter. Only SHA-256 evidence is returned.
 */
export function verifyCandidateFirebaseFunctionHashes({
  endpoints,
  expectedFunctionNames,
  expectedSecretReferences,
  sourceContract,
  projectId,
  region,
  codebase = "default",
  configuredEnvironmentEntries,
  existingEnvironmentBaselines,
} = {}) {
  if (
    !Array.isArray(endpoints) ||
    !Array.isArray(expectedFunctionNames) ||
    !plainObject(expectedSecretReferences) ||
    !sourceContract ||
    !SHA256.test(String(sourceContract.contractSha256 ?? "")) ||
    sourceContract.firebaseParamsModuleReferenceCount !== 0 ||
    !/^[a-f0-9]{40}\.[a-f0-9]{40}$/.test(
      String(sourceContract.sourceV1HashSha1 ?? ""),
    ) ||
    !SHA1.test(String(sourceContract.sourceV2HashSha1 ?? "")) ||
    !/^[a-z][a-z0-9-]{4,62}$/.test(String(projectId ?? "")) ||
    !/^[a-z]+-[a-z]+[0-9]$/.test(String(region ?? "")) ||
    codebase !== "default"
  ) {
    fail("FIREBASE_CANDIDATE_HASH_VERIFICATION_INPUT_INVALID");
  }
  const configured = Array.isArray(configuredEnvironmentEntries);
  const baselines = existingEnvironmentBaselines ?? {};
  if (configured === Boolean(existingEnvironmentBaselines)) {
    fail("FIREBASE_CANDIDATE_HASH_MODE_INVALID");
  }
  const expectedNames = [...expectedFunctionNames].sort();
  const selected = endpoints
    .filter((endpoint) => expectedNames.includes(String(endpoint?.id ?? "")))
    .sort((left, right) => String(left.id).localeCompare(String(right.id)));
  if (
    selected.length !== expectedNames.length ||
    JSON.stringify(selected.map((endpoint) => String(endpoint.id))) !==
      JSON.stringify(expectedNames)
  ) {
    fail("FIREBASE_CANDIDATE_HASH_SELECTOR_MISMATCH");
  }
  let matches = true;
  const evidence = [];
  for (const endpoint of selected) {
    const id = String(endpoint.id);
    const platform = String(endpoint.platform ?? "");
    const normalizedIdentity =
      endpoint.region === region &&
      endpoint.codebase === codebase &&
      endpoint.runtime === "nodejs20" &&
      endpoint.entryPoint === id &&
      (platform === "gcfv1" || platform === "gcfv2");
    const expectedSecrets = expectedSecretReferences[id];
    const secretVersions = Array.isArray(expectedSecrets)
      ? expectedSecretVersionObject(endpoint, expectedSecrets)
      : null;
    const environmentVariables = configured
      ? expectedConfiguredBackendEnvironment(
          endpoint,
          configuredEnvironmentEntries,
          projectId,
        )
      : expectedExistingCodeBackendEnvironment(
          endpoint,
          baselines[id],
          projectId,
        );
    let expectedProviderHash = null;
    if (normalizedIdentity && secretVersions && environmentVariables) {
      try {
        expectedProviderHash = firebaseEndpointHashSha1({
          sourceHashSha1:
            platform === "gcfv1"
              ? sourceContract.sourceV1HashSha1
              : sourceContract.sourceV2HashSha1,
          environmentVariables,
          secretVersions,
        });
      } catch (_) {
        expectedProviderHash = null;
      }
    }
    const endpointMatches =
      expectedProviderHash !== null && endpoint.hash === expectedProviderHash;
    if (!endpointMatches) matches = false;
    evidence.push([
      id,
      platform,
      endpointMatches,
      expectedProviderHash ? sha256(expectedProviderHash) : null,
    ]);
  }
  return {
    candidateSourceBindingMatches: matches,
    candidateSourceContractSha256: sourceContract.contractSha256,
    candidateSourceFileCount: sourceContract.packagedFileCount,
    candidateGeneratedFileCount: sourceContract.generatedFileCount,
    candidateProviderBindingSetSha256: sha256(JSON.stringify(evidence)),
  };
}
