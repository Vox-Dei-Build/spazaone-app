#!/usr/bin/env node

import { realpathSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

import { DEVELOPMENT_FIREBASE_PROJECT_ID } from "./release-deployment-contract.mjs";

const SCRIPT_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = path.resolve(SCRIPT_DIRECTORY, "../..");
const FUNCTIONS_DIRECTORY = path.join(REPOSITORY_ROOT, "functions");

export class DevelopmentReleasePredeployError extends Error {
  constructor(code) {
    super(code);
    this.name = "DevelopmentReleasePredeployError";
    this.code = code;
    this.retryAllowed = false;
  }
}

function fail(code) {
  throw new DevelopmentReleasePredeployError(code);
}

export function assertDevelopmentReleasePredeployContext({
  resource,
  environment = process.env,
  resolvePath = realpathSync,
} = {}) {
  if (resource !== "functions" && resource !== "firestore") {
    fail("DEVELOPMENT_RELEASE_RESOURCE_INVALID");
  }
  if (environment.GCLOUD_PROJECT === "pasella-ledger") {
    fail("DEVELOPMENT_RELEASE_PRODUCTION_FORBIDDEN");
  }
  if (environment.GCLOUD_PROJECT !== DEVELOPMENT_FIREBASE_PROJECT_ID) {
    fail("DEVELOPMENT_RELEASE_PROJECT_MISMATCH");
  }
  let projectDirectory;
  let resourceDirectory;
  let temporaryRoot;
  try {
    projectDirectory = resolvePath(String(environment.PROJECT_DIR ?? ""));
    resourceDirectory = resolvePath(String(environment.RESOURCE_DIR ?? ""));
    temporaryRoot = resolvePath(os.tmpdir());
  } catch (_) {
    fail("DEVELOPMENT_RELEASE_CONTEXT_PATH_INVALID");
  }
  const projectParent = path.dirname(projectDirectory);
  const projectName = path.basename(projectDirectory);
  const expectedResourceDirectory =
    resource === "functions" ? FUNCTIONS_DIRECTORY : projectDirectory;
  if (
    projectParent !== temporaryRoot ||
    !projectName.startsWith("spazaone-development-release-") ||
    resourceDirectory !== expectedResourceDirectory
  ) {
    fail("DEVELOPMENT_RELEASE_CONTEXT_PATH_MISMATCH");
  }
  return Object.freeze({
    outcome: "verified",
    firebaseProjectId: DEVELOPMENT_FIREBASE_PROJECT_ID,
    resource,
    retryAllowed: false,
  });
}

function parseArguments(argv) {
  if (
    argv.length !== 2 ||
    argv[0] !== "--resource" ||
    !new Set(["functions", "firestore"]).has(argv[1])
  ) {
    fail("DEVELOPMENT_RELEASE_ARGUMENT_INVALID");
  }
  return argv[1];
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href
) {
  try {
    const result = assertDevelopmentReleasePredeployContext({
      resource: parseArguments(process.argv.slice(2)),
    });
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } catch (error) {
    const safe =
      error instanceof DevelopmentReleasePredeployError
        ? error
        : new DevelopmentReleasePredeployError(
            "DEVELOPMENT_RELEASE_PREDEPLOY_FAILED",
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
  }
}
