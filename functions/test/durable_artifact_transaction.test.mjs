import assert from "node:assert/strict";
import {
  chmod,
  link,
  lstat,
  mkdtemp,
  open,
  readFile,
  realpath,
  rename,
  rm,
  symlink,
  unlink,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  createDurableArtifactTransaction,
  DurableArtifactTransactionError,
} from "../scripts/durable-artifact-transaction.mjs";

async function temporaryDirectory(prefix) {
  return realpath(await mkdtemp(path.join(os.tmpdir(), prefix)));
}

function transactionOptions(root, overrides = {}) {
  return {
    targetPath: path.join(root, "receipt.json"),
    redactedIntentBytes: '{"operation":"catalog-write","redacted":true}\n',
    uuid: () => "fixed",
    ...overrides,
  };
}

async function assertMissing(pathname) {
  await assert.rejects(lstat(pathname), (error) => error?.code === "ENOENT");
}

test("durable transaction stages an intent and persists exact opaque bytes no-replace", async () => {
  const root = await temporaryDirectory("durable-artifact-happy-");
  try {
    const intent = Buffer.from("redacted intent\n", "utf8");
    const transaction = await createDurableArtifactTransaction(
      transactionOptions(root, { redactedIntentBytes: intent }),
    );
    intent.fill(0x78);

    assert.equal(transaction.state, "prepared");
    assert.equal(
      await readFile(transaction.intentPath, "utf8"),
      "redacted intent\n",
    );
    const intentStat = await lstat(transaction.intentPath);
    assert.equal(intentStat.isFile(), true);
    assert.equal(intentStat.isSymbolicLink(), false);
    assert.equal(intentStat.mode & 0o777, 0o600);
    assert.equal(intentStat.nlink, 1);
    await assertMissing(transaction.targetPath);

    assert.deepEqual(await transaction.verifyReadyForDispatch(), {
      ready: true,
      targetPath: transaction.targetPath,
    });
    transaction.markDispatchStarted();

    const finalBytes = Buffer.from('{"opaque":"canonical"}\n', "utf8");
    const expected = Buffer.from(finalBytes);
    const persistence = transaction.persistFinal(finalBytes);
    finalBytes.fill(0x79);
    const result = await persistence;

    assert.deepEqual(result, {
      persisted: true,
      path: transaction.targetPath,
      mode: "0600",
      bytes: expected.length,
    });
    assert.equal(transaction.state, "persisted");
    assert.deepEqual(await readFile(transaction.targetPath), expected);
    const targetStat = await lstat(transaction.targetPath);
    assert.equal(targetStat.mode & 0o777, 0o600);
    assert.equal(targetStat.nlink, 1);
    await assertMissing(transaction.intentPath);
    await assertMissing(path.join(root, ".receipt.json.stage-fixed"));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("target path, parent identity, ownership mode, and no-replace checks fail closed", async () => {
  const root = await temporaryDirectory("durable-artifact-path-");
  const linkedParent = `${root}-link`;
  try {
    await assert.rejects(
      createDurableArtifactTransaction({
        targetPath: "relative.json",
        redactedIntentBytes: "redacted",
      }),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.code === "DURABLE_ARTIFACT_TARGET_PATH_INVALID",
    );

    await symlink(root, linkedParent);
    await assert.rejects(
      createDurableArtifactTransaction(
        transactionOptions(linkedParent, { uuid: () => "symlink" }),
      ),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.code === "DURABLE_ARTIFACT_PARENT_UNSAFE",
    );

    await assert.rejects(
      createDurableArtifactTransaction(
        transactionOptions(root, {
          uuid: () => "wrong-owner",
          fsImpl: {
            lstat: async (pathname) => {
              const stat = await lstat(pathname);
              if (pathname !== root) return stat;
              return {
                ...stat,
                uid: stat.uid + 1,
                isDirectory: () => stat.isDirectory(),
                isFile: () => stat.isFile(),
                isSymbolicLink: () => stat.isSymbolicLink(),
              };
            },
          },
        }),
      ),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.code === "DURABLE_ARTIFACT_PARENT_UNSAFE",
    );

    await chmod(root, 0o777);
    await assert.rejects(
      createDurableArtifactTransaction(
        transactionOptions(root, { uuid: () => "unsafe-mode" }),
      ),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.code === "DURABLE_ARTIFACT_PARENT_UNSAFE",
    );
    await chmod(root, 0o700);

    const targetPath = path.join(root, "receipt.json");
    await writeFile(targetPath, "existing", { mode: 0o600 });
    await assert.rejects(
      createDurableArtifactTransaction(transactionOptions(root)),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.code === "DURABLE_ARTIFACT_TARGET_EXISTS" &&
        error.retryAllowed === false,
    );
    assert.equal(await readFile(targetPath, "utf8"), "existing");
  } finally {
    await rm(linkedParent, { force: true });
    await rm(root, { recursive: true, force: true });
  }
});

test("cancellation removes the intent only before dispatch", async () => {
  const root = await temporaryDirectory("durable-artifact-cancel-");
  try {
    const cancelled = await createDurableArtifactTransaction(
      transactionOptions(root, { uuid: () => "cancelled" }),
    );
    const cancelledIntent = cancelled.intentPath;
    assert.deepEqual(await cancelled.cancelBeforeDispatch(), {
      cancelled: true,
    });
    assert.equal(cancelled.state, "cancelled");
    await assertMissing(cancelledIntent);
    await assertMissing(cancelled.targetPath);

    const dispatched = await createDurableArtifactTransaction(
      transactionOptions(root, { uuid: () => "dispatched" }),
    );
    dispatched.markDispatchStarted();
    await assert.rejects(
      dispatched.cancelBeforeDispatch(),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.code ===
          "DURABLE_ARTIFACT_CANCELLATION_AFTER_DISPATCH_FORBIDDEN" &&
        error.needsReview === true &&
        error.retryAllowed === false,
    );
    assert.equal(
      await readFile(dispatched.intentPath, "utf8"),
      '{"operation":"catalog-write","redacted":true}\n',
    );
    await assertMissing(dispatched.targetPath);
    await dispatched.persistFinal("review closure\n");
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("intent path replacement and parent identity drift are detected", async () => {
  const root = await temporaryDirectory("durable-artifact-identity-");
  try {
    const replaced = await createDurableArtifactTransaction(
      transactionOptions(root, { uuid: () => "replace-intent" }),
    );
    const movedIntent = `${replaced.intentPath}.moved`;
    await rename(replaced.intentPath, movedIntent);
    await writeFile(replaced.intentPath, await readFile(movedIntent), {
      mode: 0o600,
    });
    await assert.rejects(
      replaced.verifyReadyForDispatch(),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.code === "DURABLE_ARTIFACT_FILE_IDENTITY_CHANGED",
    );
    await unlink(replaced.intentPath);
    await rename(movedIntent, replaced.intentPath);
    await replaced.cancelBeforeDispatch();

    let driftParent = false;
    const drifted = await createDurableArtifactTransaction(
      transactionOptions(root, {
        targetPath: path.join(root, "drifted.json"),
        uuid: () => "drift-parent",
        fsImpl: {
          lstat: async (pathname) => {
            const stat = await lstat(pathname);
            if (driftParent && pathname === root) {
              return {
                ...stat,
                ino: stat.ino + 1,
                isDirectory: () => stat.isDirectory(),
                isFile: () => stat.isFile(),
                isSymbolicLink: () => stat.isSymbolicLink(),
              };
            }
            return stat;
          },
        },
      }),
    );
    driftParent = true;
    await assert.rejects(
      drifted.verifyReadyForDispatch(),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.code === "DURABLE_ARTIFACT_PARENT_IDENTITY_CHANGED",
    );
    driftParent = false;
    await drifted.cancelBeforeDispatch();
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("a racing existing target is never overwritten and is non-retryable after dispatch", async () => {
  const root = await temporaryDirectory("durable-artifact-target-race-");
  try {
    const targetPath = path.join(root, "receipt.json");
    const transaction = await createDurableArtifactTransaction(
      transactionOptions(root, {
        fsImpl: {
          link: async (source, target) => {
            await writeFile(target, "racing target", {
              flag: "wx",
              mode: 0o600,
            });
            await link(source, target);
          },
        },
      }),
    );
    transaction.markDispatchStarted();
    await assert.rejects(
      transaction.persistFinal("canonical bytes"),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.targetMayExist === true &&
        error.needsReview === true &&
        error.retryAllowed === false,
    );
    assert.equal(await readFile(targetPath, "utf8"), "racing target");
    assert.equal(
      await readFile(transaction.intentPath, "utf8"),
      '{"operation":"catalog-write","redacted":true}\n',
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("post-link uncertainty reports targetMayExist and preserves review evidence", async () => {
  const root = await temporaryDirectory("durable-artifact-post-link-");
  try {
    const transaction = await createDurableArtifactTransaction(
      transactionOptions(root, {
        fsImpl: {
          link: async (source, target) => {
            await link(source, target);
            throw new Error("simulated acknowledgement loss");
          },
        },
      }),
    );
    transaction.markDispatchStarted();
    await assert.rejects(
      transaction.persistFinal("canonical receipt\n"),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.code === "DURABLE_ARTIFACT_PERSISTENCE_UNCERTAIN" &&
        error.targetMayExist === true &&
        error.needsReview === true &&
        error.retryAllowed === false,
    );
    assert.equal(
      await readFile(transaction.targetPath, "utf8"),
      "canonical receipt\n",
    );
    assert.equal((await lstat(transaction.targetPath)).nlink, 2);
    assert.equal(
      await readFile(transaction.intentPath, "utf8"),
      '{"operation":"catalog-write","redacted":true}\n',
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("extra hardlinks and same-byte target substitution cannot pass final verification", async () => {
  const hardlinkRoot = await temporaryDirectory("durable-artifact-hardlink-");
  const substitutionRoot = await temporaryDirectory(
    "durable-artifact-substitution-",
  );
  try {
    const extraPath = path.join(hardlinkRoot, "extra-link");
    const hardlinked = await createDurableArtifactTransaction(
      transactionOptions(hardlinkRoot, {
        fsImpl: {
          link: async (source, target) => {
            await link(source, target);
            await link(source, extraPath);
          },
        },
      }),
    );
    hardlinked.markDispatchStarted();
    await assert.rejects(
      hardlinked.persistFinal("canonical hardlink bytes"),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.targetMayExist === true &&
        error.retryAllowed === false,
    );

    const replacementBytes = "identical replacement bytes";
    const substituted = await createDurableArtifactTransaction(
      transactionOptions(substitutionRoot, {
        fsImpl: {
          link: async (source, target) => {
            await link(source, target);
            await unlink(target);
            await writeFile(target, replacementBytes, {
              flag: "wx",
              mode: 0o600,
            });
          },
        },
      }),
    );
    substituted.markDispatchStarted();
    await assert.rejects(
      substituted.persistFinal(replacementBytes),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.code === "DURABLE_ARTIFACT_LINK_VERIFICATION_UNCERTAIN" &&
        error.targetMayExist === true &&
        error.needsReview === true &&
        error.retryAllowed === false,
    );
  } finally {
    await rm(hardlinkRoot, { recursive: true, force: true });
    await rm(substitutionRoot, { recursive: true, force: true });
  }
});

test("artifact persistence requires an explicit dispatch transition", async () => {
  const root = await temporaryDirectory("durable-artifact-state-");
  try {
    const transaction = await createDurableArtifactTransaction(
      transactionOptions(root),
    );
    await assert.rejects(
      transaction.persistFinal("must not persist"),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.code === "DURABLE_ARTIFACT_DISPATCH_NOT_STARTED" &&
        error.retryAllowed === false,
    );
    await assertMissing(transaction.targetPath);
    assert.equal(
      await readFile(transaction.intentPath, "utf8"),
      '{"operation":"catalog-write","redacted":true}\n',
    );
    await transaction.cancelBeforeDispatch();
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("invalid final bytes after dispatch preserve the intent and require review", async () => {
  const root = await temporaryDirectory("durable-artifact-invalid-final-");
  try {
    const transaction = await createDurableArtifactTransaction(
      transactionOptions(root),
    );
    transaction.markDispatchStarted();
    await assert.rejects(
      transaction.persistFinal(undefined),
      (error) =>
        error instanceof DurableArtifactTransactionError &&
        error.code === "DURABLE_ARTIFACT_FINAL_BYTES_INVALID" &&
        error.targetMayExist === false &&
        error.needsReview === true &&
        error.retryAllowed === false,
    );
    await assertMissing(transaction.targetPath);
    assert.equal(
      await readFile(transaction.intentPath, "utf8"),
      '{"operation":"catalog-write","redacted":true}\n',
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
