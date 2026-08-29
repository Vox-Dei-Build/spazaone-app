import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

const integrationPath = path.resolve(
  "test/whatsapp_catalog_cart.integration.test.mjs",
);
const packagePath = path.resolve("package.json");

test("native catalogue cart integration fails closed without a local emulator", async () => {
  const source = await readFile(integrationPath, "utf8");
  const guardOffset = source.indexOf(
    "WHATSAPP_CATALOG_CART_INTEGRATION_REQUIRES_LOCAL_FIRESTORE_EMULATOR",
  );
  const firebaseInitializationOffset = source.indexOf("admin.initializeApp");
  assert.ok(guardOffset >= 0);
  assert.ok(firebaseInitializationOffset > guardOffset);
  assert.doesNotMatch(
    source,
    /process\.env\.GCLOUD_PROJECT\s*\|\|\s*["']demo-/,
  );

  const result = spawnSync(
    process.execPath,
    ["--test", "--test-concurrency=1", integrationPath],
    {
      cwd: path.resolve("."),
      encoding: "utf8",
      env: {
        HOME: process.env.HOME,
        LANG: "C",
        LC_ALL: "C",
        PATH: process.env.PATH,
      },
    },
  );
  assert.notEqual(result.status, 0);
  assert.match(
    `${result.stdout}\n${result.stderr}`,
    /WHATSAPP_CATALOG_CART_INTEGRATION_REQUIRES_LOCAL_FIRESTORE_EMULATOR/,
  );
});

test("package integration command owns the isolated Firestore emulator lifecycle", async () => {
  const packageJson = JSON.parse(await readFile(packagePath, "utf8"));
  const command = packageJson.scripts["test:whatsapp-catalog-integration"];
  assert.match(command, /firebase emulators:exec/);
  assert.match(command, /--project demo-spazaone-native-cart/);
  assert.match(command, /--only firestore/);
  assert.match(command, /GCLOUD_PROJECT=demo-spazaone-native-cart/);
  assert.match(
    command,
    /node --test --test-concurrency=1 test\/whatsapp_catalog_cart\.integration\.test\.mjs/,
  );
});
