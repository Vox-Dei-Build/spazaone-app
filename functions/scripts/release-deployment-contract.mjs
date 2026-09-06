/**
 * Exact development deployment surface for the 2026-09 read-efficiency
 * release. Keep this data-only contract small so selectors, runtime baselines,
 * index synthesis, and tests cannot drift onto unrelated resources.
 */

export const DEVELOPMENT_FIREBASE_PROJECT_ID = "spazaone-dev";
export const DEVELOPMENT_FIREBASE_PROJECT_NUMBER = "317368517217";

export const DEVELOPMENT_RELEASE_FUNCTIONS = Object.freeze([
  "getWhatsAppCatalogSyncStatusV2",
  "scheduledNPAUpdate",
  "expireAccountSettlementIntents",
  "getEnvironmentInfo",
]);

// V2 is new in development. Its reviewed runtime configuration is inherited
// from V1, the same callable family. Every existing target anchors to itself so
// a broad scheduled-function environment cannot bleed into a narrow callable.
export const DEVELOPMENT_RELEASE_ENVIRONMENT_ANCHORS = Object.freeze({
  getWhatsAppCatalogSyncStatusV2: "getWhatsAppCatalogSyncStatusV1",
  scheduledNPAUpdate: "scheduledNPAUpdate",
  expireAccountSettlementIntents: "expireAccountSettlementIntents",
  getEnvironmentInfo: "getEnvironmentInfo",
});

export const DEVELOPMENT_RELEASE_FUNCTION_SECRET_REFS = Object.freeze({
  getWhatsAppCatalogSyncStatusV2: Object.freeze([
    "WHATSAPP_CATALOG_STATUS_CURSOR_SECRET",
  ]),
  scheduledNPAUpdate: Object.freeze([]),
  expireAccountSettlementIntents: Object.freeze([]),
  getEnvironmentInfo: Object.freeze([]),
});

export const REQUIRED_RELEASE_COMPOSITE_INDEXES = Object.freeze([
  Object.freeze({
    collectionGroup: "customers",
    queryScope: "COLLECTION_GROUP",
    fields: Object.freeze([
      Object.freeze({ fieldPath: "isNPA", order: "ASCENDING" }),
      Object.freeze({ fieldPath: "balance", order: "ASCENDING" }),
      Object.freeze({ fieldPath: "__name__", order: "ASCENDING" }),
    ]),
  }),
  Object.freeze({
    collectionGroup: "paymentIntents",
    queryScope: "COLLECTION",
    fields: Object.freeze([
      Object.freeze({ fieldPath: "purpose", order: "ASCENDING" }),
      Object.freeze({ fieldPath: "status", order: "ASCENDING" }),
      Object.freeze({ fieldPath: "expiresAt", order: "ASCENDING" }),
      Object.freeze({ fieldPath: "__name__", order: "ASCENDING" }),
    ]),
  }),
]);
