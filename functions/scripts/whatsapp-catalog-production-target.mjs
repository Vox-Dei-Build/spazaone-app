import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const TARGET_DOCUMENT_PATH = new URL(
  "../config/whatsapp-catalog-production-target.json",
  import.meta.url,
);
const SHA256 = /^[a-f0-9]{64}$/;
const DECIMAL_IDENTIFIER = /^[0-9]{6,32}$/;

function exactKeys(value, expected, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label}_INVALID`);
  }
  const actual = Object.keys(value).sort();
  const approved = [...expected].sort();
  if (
    actual.length !== approved.length ||
    actual.some((key, index) => key !== approved[index])
  ) {
    throw new Error(`${label}_KEYSET_INVALID`);
  }
}

function loadCheckedTargetDocument() {
  let document;
  try {
    document = JSON.parse(readFileSync(TARGET_DOCUMENT_PATH, "utf8"));
  } catch (_) {
    throw new Error("WHATSAPP_CATALOG_PRODUCTION_TARGET_UNREADABLE");
  }
  exactKeys(
    document,
    [
      "schemaVersion",
      "firebaseProjectId",
      "firebaseAccount",
      "functionRegions",
      "catalogId",
      "senderPhoneNumberId",
      "graphApiVersion",
      "immutableTargetConfiguration",
      "targetConfigurationDigestSha256",
      "operatorModulePath",
      "runtimeModulePath",
    ],
    "WHATSAPP_CATALOG_PRODUCTION_TARGET",
  );
  exactKeys(
    document.immutableTargetConfiguration,
    [
      "schemaVersion",
      "SPAZAONE_ENVIRONMENT",
      "SPAZAONE_FIREBASE_PROJECT_ID",
      "WHATSAPP_CATALOG_ID",
      "WHATSAPP_CATALOG_MAX_BATCH_SIZE",
      "META_GRAPH_API_VERSION",
      "WHATSAPP_SENDER_NUMBER_ID",
      "WHATSAPP_PRODUCT_LIST_RECIPIENT_COOLDOWN_MS",
      "WHATSAPP_PRODUCT_LIST_MAX_ATTEMPTS",
      "WHATSAPP_CATALOG_PAIR_LIMIT_PAUSE_MS",
    ],
    "WHATSAPP_CATALOG_IMMUTABLE_TARGET",
  );
  const digest = createHash("sha256")
    .update(JSON.stringify(document.immutableTargetConfiguration))
    .digest("hex");
  if (
    document.schemaVersion !== 1 ||
    document.firebaseProjectId !== "pasella-ledger" ||
    document.firebaseAccount !== "tsepo.ntsaba@thedelta.io" ||
    JSON.stringify(document.functionRegions) !==
      JSON.stringify(["us-central1"]) ||
    !DECIMAL_IDENTIFIER.test(String(document.catalogId ?? "")) ||
    !DECIMAL_IDENTIFIER.test(String(document.senderPhoneNumberId ?? "")) ||
    !/^v[0-9]{1,3}\.[0-9]{1,3}$/.test(String(document.graphApiVersion ?? "")) ||
    !SHA256.test(String(document.targetConfigurationDigestSha256 ?? "")) ||
    document.targetConfigurationDigestSha256 !== digest ||
    document.immutableTargetConfiguration.schemaVersion !== 1 ||
    document.immutableTargetConfiguration.SPAZAONE_ENVIRONMENT !==
      "production" ||
    document.immutableTargetConfiguration.SPAZAONE_FIREBASE_PROJECT_ID !==
      document.firebaseProjectId ||
    document.immutableTargetConfiguration.WHATSAPP_CATALOG_ID !==
      document.catalogId ||
    document.immutableTargetConfiguration.META_GRAPH_API_VERSION !==
      document.graphApiVersion ||
    document.immutableTargetConfiguration.WHATSAPP_SENDER_NUMBER_ID !==
      document.senderPhoneNumberId ||
    document.operatorModulePath !==
      "functions/scripts/whatsapp-catalog-production-target.mjs" ||
    document.runtimeModulePath !==
      "functions/src/whatsapp/catalogProductionTarget.ts"
  ) {
    throw new Error("WHATSAPP_CATALOG_PRODUCTION_TARGET_INVALID");
  }
  return Object.freeze(document);
}

export const PRODUCTION_TARGET_DOCUMENT = loadCheckedTargetDocument();

export const PRODUCTION_FIREBASE_PROJECT_ID =
  PRODUCTION_TARGET_DOCUMENT.firebaseProjectId;
export const PRODUCTION_FIREBASE_ACCOUNT =
  PRODUCTION_TARGET_DOCUMENT.firebaseAccount;
export const RECONCILIATION_FUNCTION_URL = `https://${PRODUCTION_TARGET_DOCUMENT.functionRegions[0]}-${PRODUCTION_FIREBASE_PROJECT_ID}.cloudfunctions.net/runWhatsAppCatalogFullReconciliationBotHttp`;

export const PRODUCTION_NATIVE_CATALOG_TARGET = Object.freeze({
  catalogId: PRODUCTION_TARGET_DOCUMENT.catalogId,
  senderPhoneNumberId: PRODUCTION_TARGET_DOCUMENT.senderPhoneNumberId,
  graphApiVersion: PRODUCTION_TARGET_DOCUMENT.graphApiVersion,
});

/**
 * Canonical insertion order is part of the production receipt contract.
 * Runtime switches, rollout scope, secret bindings, and BUILD_COMMIT are
 * intentionally absent because they are verified through separate evidence.
 */
export const IMMUTABLE_TARGET_CONFIGURATION = Object.freeze({
  ...PRODUCTION_TARGET_DOCUMENT.immutableTargetConfiguration,
});

export function nativeCatalogTargetConfigurationDigestSha256() {
  return PRODUCTION_TARGET_DOCUMENT.targetConfigurationDigestSha256;
}
