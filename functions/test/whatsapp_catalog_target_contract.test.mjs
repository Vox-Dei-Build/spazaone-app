import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  IMMUTABLE_TARGET_CONFIGURATION,
  PRODUCTION_FIREBASE_ACCOUNT,
  PRODUCTION_FIREBASE_PROJECT_ID,
  PRODUCTION_NATIVE_CATALOG_TARGET,
  nativeCatalogTargetConfigurationDigestSha256,
} from "../scripts/whatsapp-catalog-production-target.mjs";
import {
  immutableWhatsAppCatalogTargetConfiguration,
  whatsappCatalogTargetConfigurationDigestSha256,
} from "../lib/whatsapp/catalogProductionTarget.js";

const target = JSON.parse(
  readFileSync(
    new URL(
      "../config/whatsapp-catalog-production-target.json",
      import.meta.url,
    ),
    "utf8",
  ),
);

test("operator MJS and runtime TS match the checked production target JSON", () => {
  assert.equal(PRODUCTION_FIREBASE_PROJECT_ID, target.firebaseProjectId);
  assert.equal(PRODUCTION_FIREBASE_ACCOUNT, target.firebaseAccount);
  assert.deepEqual(PRODUCTION_NATIVE_CATALOG_TARGET, {
    catalogId: target.catalogId,
    senderPhoneNumberId: target.senderPhoneNumberId,
    graphApiVersion: target.graphApiVersion,
  });
  assert.deepEqual(
    IMMUTABLE_TARGET_CONFIGURATION,
    target.immutableTargetConfiguration,
  );
  assert.equal(
    nativeCatalogTargetConfigurationDigestSha256(),
    target.targetConfigurationDigestSha256,
  );

  const previous = {};
  for (const [key, value] of Object.entries(
    target.immutableTargetConfiguration,
  )) {
    if (key === "schemaVersion") continue;
    previous[key] = process.env[key];
    process.env[key] = String(value);
  }
  try {
    assert.deepEqual(
      immutableWhatsAppCatalogTargetConfiguration(),
      target.immutableTargetConfiguration,
    );
    assert.equal(
      whatsappCatalogTargetConfigurationDigestSha256(),
      target.targetConfigurationDigestSha256,
    );
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }

  assert.equal(
    createHash("sha256")
      .update(JSON.stringify(target.immutableTargetConfiguration))
      .digest("hex"),
    target.targetConfigurationDigestSha256,
  );
});
