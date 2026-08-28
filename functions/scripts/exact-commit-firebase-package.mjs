import { execFile as nodeExecFile } from "node:child_process";
import { createHash } from "node:crypto";
import { constants as fsConstants } from "node:fs";
import {
  chmod,
  lstat,
  mkdir,
  mkdtemp,
  open,
  readFile,
  readdir,
  readlink,
  realpath,
  rm,
  stat,
  unlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

import { canonicalJson } from "./production-write-receipt.mjs";

const execFile = promisify(nodeExecFile);
const SHA1 = /^[a-f0-9]{40}$/;
const SHA256 = /^[a-f0-9]{64}$/;
const MAX_ARCHIVE_BYTES = 128 * 1024 * 1024;
const MAX_COMMAND_BYTES = 32 * 1024 * 1024;
const MAX_DOTENV_BYTES = 16 * 1024;
const SAFE_DIRECTORY_MODE = 0o700;
const SAFE_FILE_MODE = 0o600;
const IMAGE_FILE_MODE = 0o400;
const packages = new WeakMap();
const images = new WeakMap();
const workspaces = new WeakMap();

export const PINNED_LOCAL_PACKAGE_TOOLCHAIN = Object.freeze({
  node: Object.freeze({
    path: "/opt/homebrew/bin/node",
    realpath: "/opt/homebrew/Cellar/node/24.4.1/bin/node",
    sha256: "0747ad5579627f4c31f899bc980979aeb082a38b02415a749c9ee6e061370b01",
    version: "v24.4.1",
  }),
  npm: Object.freeze({
    path: "/opt/homebrew/lib/node_modules/npm/bin/npm-cli.js",
    realpath: "/opt/homebrew/lib/node_modules/npm/bin/npm-cli.js",
    sha256: "8e5f6f3429f8cdbe693cdc29904e9d5a7b127a494bd15c804bd54c7403bfcbe7",
    version: "11.4.2",
  }),
  git: Object.freeze({
    path: "/usr/bin/git",
    realpath: "/usr/bin/git",
    sha256: "9b11ead1ca76a03d61108ad5bf2c913d6aa8daa7deb9fd28893e847e3680e5e7",
    version: "git version 2.39.5 (Apple Git-154)",
  }),
  tar: Object.freeze({
    path: "/usr/bin/tar",
    realpath: "/usr/bin/bsdtar",
    sha256: "b95e5568b25eb8df7f98390277186f09f143847458f3ec91b309cea33a6c147c",
    versionPrefix: "bsdtar 3.5.3",
  }),
  hdiutil: Object.freeze({
    path: "/usr/bin/hdiutil",
    realpath: "/usr/bin/hdiutil",
    sha256: "1fc093f7694f8b35c4cc0ef4e6ce89b48f0674c560d025695e30c33548fd73aa",
  }),
  firebase: Object.freeze({
    path: "/opt/homebrew/lib/node_modules/firebase-tools/lib/bin/firebase.js",
    realpath:
      "/opt/homebrew/lib/node_modules/firebase-tools/lib/bin/firebase.js",
    sha256: "1e05ff8373e5a5c7222475a0d90d4db58c85c2f281d44d4884bc96062288b864",
    version: "15.21.0",
  }),
});

export class ExactCommitFirebasePackageError extends Error {
  constructor(code, { cause } = {}) {
    super(code, cause === undefined ? undefined : { cause });
    this.name = "ExactCommitFirebasePackageError";
    this.code = code;
    this.retryAllowed = false;
  }
}

function fail(code, details) {
  throw new ExactCommitFirebasePackageError(code, details);
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function canonicalRoot(value, label) {
  if (
    typeof value !== "string" ||
    !path.isAbsolute(value) ||
    path.resolve(value) !== value
  ) {
    fail(`${label}_INVALID`);
  }
  return value;
}

async function exactFileIdentity(tool) {
  let bytes;
  try {
    const resolved = await realpath(tool.path);
    const fileStat = await lstat(resolved);
    bytes = await readFile(resolved);
    if (
      resolved !== tool.realpath ||
      !fileStat.isFile() ||
      fileStat.isSymbolicLink() ||
      (fileStat.mode & 0o022) !== 0 ||
      sha256(bytes) !== tool.sha256
    ) {
      fail("EXACT_COMMIT_PACKAGE_TOOLCHAIN_MISMATCH");
    }
  } catch (error) {
    if (error instanceof ExactCommitFirebasePackageError) throw error;
    fail("EXACT_COMMIT_PACKAGE_TOOLCHAIN_UNREADABLE", { cause: error });
  } finally {
    bytes?.fill?.(0);
  }
}

function commandEnvironment(homePath) {
  return {
    HOME: homePath,
    USER: "admin",
    LOGNAME: "admin",
    TMPDIR: "/private/tmp",
    LANG: "C",
    LC_ALL: "C",
    PATH: "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    FIREBASE_CLI_DISABLE_UPDATE_CHECK: "1",
  };
}

async function assertPinnedPackageToolchain(runCommand, homePath) {
  for (const tool of Object.values(PINNED_LOCAL_PACKAGE_TOOLCHAIN)) {
    await exactFileIdentity(tool);
  }
  const environment = commandEnvironment(homePath);
  const [node, npm, git, tar, firebase] = await Promise.all([
    runCommand(PINNED_LOCAL_PACKAGE_TOOLCHAIN.node.path, ["--version"], {
      environment,
    }),
    runCommand(
      PINNED_LOCAL_PACKAGE_TOOLCHAIN.node.path,
      [PINNED_LOCAL_PACKAGE_TOOLCHAIN.npm.path, "--version"],
      { environment },
    ),
    runCommand(PINNED_LOCAL_PACKAGE_TOOLCHAIN.git.path, ["--version"], {
      environment,
    }),
    runCommand(PINNED_LOCAL_PACKAGE_TOOLCHAIN.tar.path, ["--version"], {
      environment,
    }),
    runCommand(
      PINNED_LOCAL_PACKAGE_TOOLCHAIN.node.path,
      [PINNED_LOCAL_PACKAGE_TOOLCHAIN.firebase.path, "--version"],
      { environment },
    ),
  ]);
  if (
    node.stdout.trim() !== PINNED_LOCAL_PACKAGE_TOOLCHAIN.node.version ||
    npm.stdout.trim() !== PINNED_LOCAL_PACKAGE_TOOLCHAIN.npm.version ||
    git.stdout.trim() !== PINNED_LOCAL_PACKAGE_TOOLCHAIN.git.version ||
    !tar.stdout.includes(PINNED_LOCAL_PACKAGE_TOOLCHAIN.tar.versionPrefix) ||
    firebase.stdout.trim() !== PINNED_LOCAL_PACKAGE_TOOLCHAIN.firebase.version
  ) {
    fail("EXACT_COMMIT_PACKAGE_TOOLCHAIN_VERSION_MISMATCH");
  }
}

async function defaultRunCommand(command, args, options = {}) {
  try {
    const result = await execFile(command, args, {
      cwd: options.cwd,
      env: options.environment,
      encoding: options.encoding ?? "utf8",
      maxBuffer: options.maxBuffer ?? MAX_COMMAND_BYTES,
      timeout: options.timeout ?? 120_000,
    });
    return {
      stdout: Buffer.isBuffer(result.stdout)
        ? result.stdout.toString("utf8")
        : String(result.stdout ?? ""),
      stderr: Buffer.isBuffer(result.stderr)
        ? result.stderr.toString("utf8")
        : String(result.stderr ?? ""),
      stdoutBytes: Buffer.isBuffer(result.stdout)
        ? Buffer.from(result.stdout)
        : null,
    };
  } catch (error) {
    fail("EXACT_COMMIT_PACKAGE_COMMAND_FAILED", { cause: error });
  }
}

async function writeExactFile(filePath, bytes, mode = SAFE_FILE_MODE) {
  let handle;
  try {
    handle = await open(
      filePath,
      fsConstants.O_CREAT |
        fsConstants.O_EXCL |
        fsConstants.O_RDWR |
        fsConstants.O_NOFOLLOW,
      mode,
    );
    await handle.writeFile(bytes);
    await handle.sync();
    const stored = Buffer.alloc(bytes.length);
    const extra = Buffer.alloc(1);
    try {
      const fileStat = await handle.stat();
      const { bytesRead } = await handle.read(stored, 0, stored.length, 0);
      const { bytesRead: extraBytesRead } = await handle.read(
        extra,
        0,
        1,
        bytes.length,
      );
      if (
        !fileStat.isFile() ||
        fileStat.nlink !== 1 ||
        (fileStat.mode & 0o777) !== mode ||
        bytesRead !== bytes.length ||
        extraBytesRead !== 0 ||
        !stored.equals(bytes)
      ) {
        fail("EXACT_COMMIT_PACKAGE_FILE_WRITE_UNCERTAIN");
      }
    } finally {
      stored.fill(0);
      extra.fill(0);
    }
  } finally {
    await handle?.close().catch(() => {});
  }
}

function safeSymlinkTarget(rootPath, absolutePath, target) {
  if (
    typeof target !== "string" ||
    !target ||
    path.isAbsolute(target) ||
    target.includes("\u0000")
  ) {
    return false;
  }
  const resolved = path.resolve(path.dirname(absolutePath), target);
  return resolved === rootPath || resolved.startsWith(`${rootPath}${path.sep}`);
}

async function inventory(rootPath) {
  const rows = [];
  const visit = async (directory, relativeDirectory = "") => {
    const entries = await readdir(directory, { withFileTypes: true });
    entries.sort((left, right) => left.name.localeCompare(right.name));
    for (const entry of entries) {
      const relativePath = relativeDirectory
        ? `${relativeDirectory}/${entry.name}`
        : entry.name;
      const absolutePath = path.join(directory, entry.name);
      const item = await lstat(absolutePath);
      if (item.isDirectory() && !item.isSymbolicLink()) {
        rows.push([relativePath, "directory", item.mode & 0o777, 0, null]);
        await visit(absolutePath, relativePath);
      } else if (item.isFile() && !item.isSymbolicLink()) {
        const bytes = await readFile(absolutePath);
        try {
          rows.push([
            relativePath,
            "file",
            item.mode & 0o777,
            item.size,
            sha256(bytes),
          ]);
        } finally {
          bytes.fill(0);
        }
      } else if (item.isSymbolicLink()) {
        const target = await readlink(absolutePath);
        if (!safeSymlinkTarget(rootPath, absolutePath, target)) {
          fail("EXACT_COMMIT_PACKAGE_SYMLINK_UNSAFE");
        }
        rows.push([
          relativePath,
          "symlink",
          item.mode & 0o777,
          Buffer.byteLength(target),
          sha256(target),
        ]);
      } else {
        fail("EXACT_COMMIT_PACKAGE_INVENTORY_UNSAFE");
      }
    }
  };
  await visit(rootPath);
  return rows;
}

function inventoryDigest(rows) {
  return sha256(canonicalJson(rows));
}

function reviewedRowsOnly(rows) {
  return rows.filter(
    ([relativePath]) =>
      relativePath !== "functions/lib" &&
      !relativePath.startsWith("functions/lib/") &&
      relativePath !== "functions/node_modules" &&
      !relativePath.startsWith("functions/node_modules/"),
  );
}

async function runNpmCi({ functionsPath, homePath, omitDev, runCommand }) {
  const npmrcPath = path.join(homePath, "empty-npmrc");
  const environment = {
    ...commandEnvironment(homePath),
    npm_config_cache: "/Users/admin/.npm",
    npm_config_userconfig: npmrcPath,
    npm_config_offline: "true",
    npm_config_ignore_scripts: "true",
    npm_config_audit: "false",
    npm_config_fund: "false",
    npm_config_update_notifier: "false",
    npm_config_progress: "false",
    npm_config_loglevel: "error",
  };
  const args = [
    PINNED_LOCAL_PACKAGE_TOOLCHAIN.npm.path,
    "ci",
    "--offline",
    "--ignore-scripts",
    "--no-audit",
    "--no-fund",
    "--progress=false",
  ];
  if (omitDev) args.push("--omit=dev");
  await runCommand(PINNED_LOCAL_PACKAGE_TOOLCHAIN.node.path, args, {
    cwd: functionsPath,
    environment,
    timeout: 180_000,
  });
}

async function verifyRuntimeDependencyClosure(functionsPath) {
  const packageLock = JSON.parse(
    await readFile(path.join(functionsPath, "package-lock.json"), "utf8"),
  );
  const rootDependencies = packageLock.packages?.[""]?.dependencies;
  if (!rootDependencies || typeof rootDependencies !== "object") {
    fail("EXACT_COMMIT_PACKAGE_LOCK_INVALID");
  }
  for (const dependencyName of Object.keys(rootDependencies).sort()) {
    const lockEntry = packageLock.packages[`node_modules/${dependencyName}`];
    const installed = JSON.parse(
      await readFile(
        path.join(
          functionsPath,
          "node_modules",
          dependencyName,
          "package.json",
        ),
        "utf8",
      ),
    );
    if (
      !lockEntry ||
      typeof lockEntry.integrity !== "string" ||
      !lockEntry.integrity.startsWith("sha512-") ||
      installed.name !== dependencyName ||
      installed.version !== lockEntry.version
    ) {
      fail("EXACT_COMMIT_PACKAGE_DEPENDENCY_MISMATCH");
    }
  }
  const firebaseBinary = path.join(
    functionsPath,
    "node_modules/.bin/firebase-functions",
  );
  const binaryStat = await lstat(firebaseBinary);
  const target = await readlink(firebaseBinary);
  if (
    !binaryStat.isSymbolicLink() ||
    !safeSymlinkTarget(functionsPath, firebaseBinary, target)
  ) {
    fail("EXACT_COMMIT_PACKAGE_FIREBASE_DISCOVERY_MISSING");
  }
}

export async function prepareExactCommitFirebasePackage({
  repositoryRoot,
  expectedAppCommit,
  temporaryRoot = os.tmpdir(),
  runCommand = defaultRunCommand,
} = {}) {
  canonicalRoot(repositoryRoot, "EXACT_COMMIT_PACKAGE_REPOSITORY_ROOT");
  canonicalRoot(temporaryRoot, "EXACT_COMMIT_PACKAGE_TEMPORARY_ROOT");
  if (!SHA1.test(String(expectedAppCommit ?? ""))) {
    fail("EXACT_COMMIT_PACKAGE_COMMIT_INVALID");
  }
  const rootPath = await realpath(
    await mkdtemp(path.join(temporaryRoot, "spazaone-exact-package-")),
  );
  const archiveRoot = path.join(rootPath, "archive");
  const homePath = path.join(rootPath, "home");
  const archivePath = path.join(rootPath, "reviewed-commit.tar");
  try {
    await mkdir(archiveRoot, { mode: SAFE_DIRECTORY_MODE });
    await mkdir(homePath, { mode: SAFE_DIRECTORY_MODE });
    await writeExactFile(path.join(homePath, "empty-npmrc"), Buffer.alloc(0));
    await assertPinnedPackageToolchain(runCommand, homePath);
    const environment = commandEnvironment(homePath);
    const commit = await runCommand(
      PINNED_LOCAL_PACKAGE_TOOLCHAIN.git.path,
      ["-C", repositoryRoot, "rev-parse", `${expectedAppCommit}^{commit}`],
      { environment },
    );
    if (commit.stdout.trim() !== expectedAppCommit) {
      fail("EXACT_COMMIT_PACKAGE_COMMIT_MISMATCH");
    }
    const archived = await execFile(
      PINNED_LOCAL_PACKAGE_TOOLCHAIN.git.path,
      ["-C", repositoryRoot, "archive", "--format=tar", expectedAppCommit],
      {
        encoding: null,
        env: environment,
        maxBuffer: MAX_ARCHIVE_BYTES,
        timeout: 60_000,
      },
    ).catch((error) =>
      fail("EXACT_COMMIT_PACKAGE_ARCHIVE_FAILED", { cause: error }),
    );
    const archiveBytes = Buffer.from(archived.stdout);
    const gitArchiveSha256 = sha256(archiveBytes);
    try {
      await writeExactFile(archivePath, archiveBytes);
    } finally {
      archiveBytes.fill(0);
    }
    await runCommand(
      PINNED_LOCAL_PACKAGE_TOOLCHAIN.tar.path,
      ["-xf", archivePath, "-C", archiveRoot],
      { environment },
    );
    await unlink(archivePath);
    const functionsPath = path.join(archiveRoot, "functions");
    const functionsStat = await stat(functionsPath);
    if (!functionsStat.isDirectory()) {
      fail("EXACT_COMMIT_PACKAGE_FUNCTIONS_MISSING");
    }
    const reviewedRows = await inventory(archiveRoot);
    const reviewedArchiveInventorySha256 = inventoryDigest(reviewedRows);
    const packageJsonBytes = await readFile(
      path.join(functionsPath, "package.json"),
    );
    const packageLockBytes = await readFile(
      path.join(functionsPath, "package-lock.json"),
    );
    const packageJsonSha256 = sha256(packageJsonBytes);
    const packageLockSha256 = sha256(packageLockBytes);
    packageJsonBytes.fill(0);
    packageLockBytes.fill(0);

    await runNpmCi({
      functionsPath,
      homePath,
      omitDev: false,
      runCommand,
    });
    const typescriptEntry = path.join(
      functionsPath,
      "node_modules/typescript/bin/tsc",
    );
    await runCommand(
      PINNED_LOCAL_PACKAGE_TOOLCHAIN.node.path,
      [typescriptEntry],
      {
        cwd: functionsPath,
        environment: commandEnvironment(homePath),
        timeout: 180_000,
      },
    );
    const generatedLibRows = await inventory(path.join(functionsPath, "lib"));
    if (generatedLibRows.length < 1) {
      fail("EXACT_COMMIT_PACKAGE_BUILD_EMPTY");
    }
    const generatedLibInventorySha256 = inventoryDigest(generatedLibRows);
    await runNpmCi({
      functionsPath,
      homePath,
      omitDev: true,
      runCommand,
    });
    if (
      inventoryDigest(await inventory(path.join(functionsPath, "lib"))) !==
      generatedLibInventorySha256
    ) {
      fail("EXACT_COMMIT_PACKAGE_BUILD_CHANGED");
    }
    const postBuildRows = await inventory(archiveRoot);
    if (
      canonicalJson(reviewedRowsOnly(postBuildRows)) !==
      canonicalJson(reviewedRowsOnly(reviewedRows))
    ) {
      fail("EXACT_COMMIT_PACKAGE_REVIEWED_SOURCE_CHANGED");
    }
    await verifyRuntimeDependencyClosure(functionsPath);
    const dependencyRows = await inventory(
      path.join(functionsPath, "node_modules"),
    );
    const dependencyClosureSha256 = inventoryDigest(dependencyRows);
    const finalRows = await inventory(archiveRoot);
    const packageInventorySha256 = inventoryDigest(finalRows);
    const descriptor = Object.freeze({
      expectedAppCommit,
      gitArchiveSha256,
      reviewedArchiveInventorySha256,
      packageJsonSha256,
      packageLockSha256,
      generatedLibInventorySha256,
      dependencyClosureSha256,
      dependencyFileCount: dependencyRows.length,
      packageInventorySha256,
      packageEntryCount: finalRows.length,
      builtFromExactCommit: true,
      offlineInstall: true,
      scriptsDisabledDuringInstall: true,
      productionDependenciesIncluded: true,
      authorizesProduction: false,
    });
    packages.set(descriptor, {
      rootPath,
      archiveRoot,
      functionsPath,
      finalRows,
      mounted: false,
      cleaned: false,
    });
    return descriptor;
  } catch (error) {
    await rm(rootPath, { recursive: true, force: true }).catch(() => {});
    if (error instanceof ExactCommitFirebasePackageError) throw error;
    fail("EXACT_COMMIT_PACKAGE_PREPARATION_FAILED", { cause: error });
  }
}

export function exactCommitFirebasePackagePath(
  packageDescriptor,
  relativePath,
) {
  const state = packages.get(packageDescriptor);
  if (!state || state.cleaned || typeof relativePath !== "string") {
    fail("EXACT_COMMIT_PACKAGE_NOT_ACTIVE");
  }
  const segments = relativePath.split("/");
  if (
    segments.some((segment) => !segment || segment === "." || segment === "..")
  ) {
    fail("EXACT_COMMIT_PACKAGE_PATH_INVALID");
  }
  return path.join(state.archiveRoot, ...segments);
}

export async function verifyExactCommitFirebasePackage(packageDescriptor) {
  const state = packages.get(packageDescriptor);
  if (!state || state.cleaned) fail("EXACT_COMMIT_PACKAGE_NOT_ACTIVE");
  const rows = await inventory(state.archiveRoot);
  if (
    inventoryDigest(rows) !== packageDescriptor.packageInventorySha256 ||
    canonicalJson(rows) !== canonicalJson(state.finalRows)
  ) {
    fail("EXACT_COMMIT_PACKAGE_CHANGED");
  }
  return Object.freeze({
    verified: true,
    packageInventorySha256: packageDescriptor.packageInventorySha256,
    dependencyClosureSha256: packageDescriptor.dependencyClosureSha256,
    generatedLibInventorySha256: packageDescriptor.generatedLibInventorySha256,
  });
}

export async function assertKernelReadOnlyMount(
  mountRoot,
  { writeFileImpl = writeFile } = {},
) {
  canonicalRoot(mountRoot, "KERNEL_READ_ONLY_MOUNT_ROOT");
  const sentinel = path.join(mountRoot, ".spazaone-readonly-probe");
  try {
    await writeFileImpl(sentinel, "must-not-write", {
      flag: "wx",
      mode: SAFE_FILE_MODE,
    });
  } catch (error) {
    if (error?.code === "EROFS") {
      return Object.freeze({ kernelReadOnly: true, writeErrorCode: "EROFS" });
    }
    fail("KERNEL_READ_ONLY_MOUNT_UNVERIFIED", { cause: error });
  }
  await unlink(sentinel).catch(() => {});
  fail("KERNEL_READ_ONLY_MOUNT_WRITABLE");
}

export async function mountExactCommitFirebasePackageReadOnly(
  packageDescriptor,
  { runCommand = defaultRunCommand } = {},
) {
  const state = packages.get(packageDescriptor);
  if (!state || state.cleaned || state.mounted) {
    fail("EXACT_COMMIT_PACKAGE_NOT_MOUNTABLE");
  }
  const imagePath = path.join(state.rootPath, "provider-input.dmg");
  const mountRoot = path.join(state.rootPath, "provider-input");
  const homePath = path.join(state.rootPath, "home");
  await mkdir(mountRoot, { mode: SAFE_DIRECTORY_MODE });
  await verifyExactCommitFirebasePackage(packageDescriptor);
  const environment = commandEnvironment(homePath);
  await runCommand(
    PINNED_LOCAL_PACKAGE_TOOLCHAIN.hdiutil.path,
    [
      "create",
      "-quiet",
      "-format",
      "UDRO",
      "-fs",
      "HFS+",
      "-volname",
      `spazaone-${packageDescriptor.expectedAppCommit.slice(0, 12)}`,
      "-srcfolder",
      state.archiveRoot,
      imagePath,
    ],
    { environment, timeout: 180_000 },
  );
  await chmod(imagePath, IMAGE_FILE_MODE);
  await runCommand(
    PINNED_LOCAL_PACKAGE_TOOLCHAIN.hdiutil.path,
    [
      "attach",
      "-quiet",
      "-readonly",
      "-nobrowse",
      "-mountpoint",
      mountRoot,
      imagePath,
    ],
    { environment, timeout: 60_000 },
  );
  try {
    await assertKernelReadOnlyMount(mountRoot);
    const mountedRows = await inventory(mountRoot);
    if (
      inventoryDigest(mountedRows) !== packageDescriptor.packageInventorySha256
    ) {
      fail("KERNEL_READ_ONLY_PACKAGE_INVENTORY_MISMATCH");
    }
    const descriptor = Object.freeze({
      expectedAppCommit: packageDescriptor.expectedAppCommit,
      packageInventorySha256: packageDescriptor.packageInventorySha256,
      dependencyClosureSha256: packageDescriptor.dependencyClosureSha256,
      generatedLibInventorySha256:
        packageDescriptor.generatedLibInventorySha256,
      kernelReadOnly: true,
      authorizesProduction: false,
    });
    state.mounted = true;
    images.set(descriptor, {
      packageDescriptor,
      mountRoot,
      imagePath,
      functionsPath: path.join(mountRoot, "functions"),
      runCommand,
      environment,
      detached: false,
    });
    return descriptor;
  } catch (error) {
    await runCommand(
      PINNED_LOCAL_PACKAGE_TOOLCHAIN.hdiutil.path,
      ["detach", "-quiet", mountRoot],
      { environment },
    ).catch(() => {});
    throw error;
  }
}

function exactDotenv(text) {
  if (
    typeof text !== "string" ||
    Buffer.byteLength(text) > MAX_DOTENV_BYTES ||
    text.includes("\u0000") ||
    (text.length > 0 && !text.endsWith("\n"))
  ) {
    fail("FIREBASE_PROVIDER_OVERLAY_DOTENV_INVALID");
  }
  return text;
}

export async function createFirebaseProviderWorkspace({
  mountedPackage,
  projectId,
  dotenvText = "",
  temporaryRoot = os.tmpdir(),
  emulatorPorts = {},
} = {}) {
  const image = images.get(mountedPackage);
  canonicalRoot(temporaryRoot, "FIREBASE_PROVIDER_WORKSPACE_ROOT");
  if (
    !image ||
    image.detached ||
    typeof projectId !== "string" ||
    !/^(?:demo-)?[a-z][a-z0-9-]{4,29}$/.test(projectId)
  ) {
    fail("FIREBASE_PROVIDER_WORKSPACE_INPUT_INVALID");
  }
  const normalizedDotenv = exactDotenv(dotenvText);
  const rootPath = await realpath(
    await mkdtemp(path.join(temporaryRoot, "spazaone-provider-workspace-")),
  );
  const configDir = path.join(rootPath, "config");
  const providerHome = path.join(rootPath, "provider-home");
  await mkdir(configDir, { mode: SAFE_DIRECTORY_MODE });
  await mkdir(providerHome, { mode: SAFE_DIRECTORY_MODE });
  const dotenvPath = path.join(configDir, `.env.${projectId}`);
  await writeExactFile(
    dotenvPath,
    Buffer.from(normalizedDotenv, "utf8"),
    SAFE_FILE_MODE,
  );
  const config = {
    functions: [
      {
        source: image.functionsPath,
        codebase: "default",
        configDir,
        ignore: [
          "node_modules",
          ".git",
          "firebase-debug.log",
          "firebase-debug.*.log",
        ],
      },
    ],
    emulators: {
      singleProjectMode: true,
      functions: {
        host: "127.0.0.1",
        port: emulatorPorts.functions ?? 56101,
      },
      hub: { host: "127.0.0.1", port: emulatorPorts.hub ?? 56102 },
      logging: {
        host: "127.0.0.1",
        port: emulatorPorts.logging ?? 56103,
      },
    },
  };
  const configBytes = Buffer.from(`${JSON.stringify(config, null, 2)}\n`);
  const configPath = path.join(rootPath, "firebase.json");
  await writeExactFile(configPath, configBytes, SAFE_FILE_MODE);
  const descriptor = Object.freeze({
    projectId,
    configSha256: sha256(configBytes),
    dotenvSha256: sha256(normalizedDotenv),
    writableOverlay: true,
    sourceKernelReadOnly: true,
    authorizesProduction: false,
  });
  configBytes.fill(0);
  workspaces.set(descriptor, {
    rootPath,
    configDir,
    configPath,
    dotenvPath,
    providerHome,
    mountedPackage,
    expectedConfigEntries: ["config", "firebase.json", "provider-home"],
    expectedOverlayEntries: [`.env.${projectId}`],
    cleaned: false,
  });
  return descriptor;
}

async function verifyProviderWorkspace(workspace, state) {
  const configBytes = await readFile(state.configPath);
  const dotenvBytes = await readFile(state.dotenvPath);
  try {
    const rootEntries = (await readdir(state.rootPath)).sort();
    const overlayEntries = (await readdir(state.configDir)).sort();
    if (
      sha256(configBytes) !== workspace.configSha256 ||
      sha256(dotenvBytes) !== workspace.dotenvSha256 ||
      canonicalJson(rootEntries) !==
        canonicalJson(state.expectedConfigEntries) ||
      canonicalJson(overlayEntries) !==
        canonicalJson(state.expectedOverlayEntries)
    ) {
      fail("FIREBASE_PROVIDER_WORKSPACE_CHANGED");
    }
  } finally {
    configBytes.fill(0);
    dotenvBytes.fill(0);
  }
}

async function providerScratchEvidence(state) {
  const providerHomeStat = await lstat(state.providerHome);
  if (
    !providerHomeStat.isDirectory() ||
    providerHomeStat.isSymbolicLink() ||
    (providerHomeStat.mode & 0o077) !== 0
  ) {
    fail("FIREBASE_PROVIDER_SCRATCH_UNSAFE");
  }
  const rows = await inventory(state.providerHome);
  const totalBytes = rows.reduce((total, row) => total + row[3], 0);
  if (rows.length > 100 || totalBytes > 1024 * 1024) {
    fail("FIREBASE_PROVIDER_SCRATCH_UNBOUNDED");
  }
  return Object.freeze({
    entryCount: rows.length,
    totalBytes,
    inventorySha256: inventoryDigest(rows),
  });
}

export async function inspectFirebaseProviderWorkspace(workspace) {
  const state = workspaces.get(workspace);
  if (!state || state.cleaned) fail("FIREBASE_PROVIDER_WORKSPACE_NOT_ACTIVE");
  return Object.freeze({
    rootEntries: Object.freeze((await readdir(state.rootPath)).sort()),
    overlayEntries: Object.freeze((await readdir(state.configDir)).sort()),
  });
}

export async function probeFirebasePackageLocally({
  mountedPackage,
  workspace,
  runCommand = defaultRunCommand,
} = {}) {
  const image = images.get(mountedPackage);
  const state = workspaces.get(workspace);
  if (
    !image ||
    image.detached ||
    !state ||
    state.cleaned ||
    state.mountedPackage !== mountedPackage ||
    !workspace.projectId.startsWith("demo-")
  ) {
    fail("FIREBASE_LOCAL_PROBE_INPUT_INVALID");
  }
  await verifyProviderWorkspace(workspace, state);
  const scratchBefore = await providerScratchEvidence(state);
  if (scratchBefore.entryCount !== 0) {
    fail("FIREBASE_PROVIDER_SCRATCH_NOT_EMPTY");
  }
  await assertKernelReadOnlyMount(image.mountRoot);
  const environment = {
    ...commandEnvironment(state.providerHome),
    FIREBASE_CLI_DISABLE_UPDATE_CHECK: "1",
    FIREBASE_FUNCTIONS_DISCOVERY_OUTPUT_PATH: "true",
    CI: "1",
  };
  const result = await runCommand(
    PINNED_LOCAL_PACKAGE_TOOLCHAIN.node.path,
    [
      PINNED_LOCAL_PACKAGE_TOOLCHAIN.firebase.path,
      "--config",
      state.configPath,
      "--project",
      workspace.projectId,
      "--non-interactive",
      "emulators:exec",
      "--only",
      "functions",
      "/usr/bin/true",
    ],
    { cwd: state.rootPath, environment, timeout: 120_000 },
  );
  await assertKernelReadOnlyMount(image.mountRoot);
  await verifyProviderWorkspace(workspace, state);
  const scratchAfter = await providerScratchEvidence(state);
  return Object.freeze({
    firebaseCliVersion: PINNED_LOCAL_PACKAGE_TOOLCHAIN.firebase.version,
    exactCommit:
      image.packageDescriptor?.expectedAppCommit ??
      mountedPackage.expectedAppCommit,
    packageInventorySha256: mountedPackage.packageInventorySha256,
    dependencyClosureSha256: mountedPackage.dependencyClosureSha256,
    generatedLibInventorySha256: mountedPackage.generatedLibInventorySha256,
    stdoutSha256: sha256(result.stdout),
    stderrSha256: sha256(result.stderr),
    providerScratchInventorySha256: scratchAfter.inventorySha256,
    providerScratchEntryCount: scratchAfter.entryCount,
    localDemoProject: workspace.projectId,
    providerPackageConsumed: true,
    productionWriteAttempted: false,
    authorizesProduction: false,
  });
}

export async function cleanupFirebaseProviderWorkspace(workspace) {
  const state = workspaces.get(workspace);
  if (!state || state.cleaned) fail("FIREBASE_PROVIDER_WORKSPACE_NOT_ACTIVE");
  await rm(state.rootPath, { recursive: true, force: false });
  state.cleaned = true;
  workspaces.delete(workspace);
}

export async function cleanupExactCommitFirebasePackage({
  mountedPackage,
  packageDescriptor,
} = {}) {
  const image = mountedPackage ? images.get(mountedPackage) : null;
  const selectedPackage = packageDescriptor ?? image?.packageDescriptor;
  const state = packages.get(selectedPackage);
  if (!state || state.cleaned) fail("EXACT_COMMIT_PACKAGE_NOT_ACTIVE");
  if (image && !image.detached) {
    await image.runCommand(
      PINNED_LOCAL_PACKAGE_TOOLCHAIN.hdiutil.path,
      ["detach", "-quiet", image.mountRoot],
      { environment: image.environment, timeout: 60_000 },
    );
    image.detached = true;
    images.delete(mountedPackage);
  }
  await chmod(state.rootPath, SAFE_DIRECTORY_MODE).catch(() => {});
  await rm(state.rootPath, { recursive: true, force: false });
  state.cleaned = true;
  packages.delete(selectedPackage);
}
