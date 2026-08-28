import { resolveEnvironment, SpazaEnvironment } from "../config/environment";

export type MetaCatalogProviderMode = "disabled" | "stub" | "test" | "live";

export type WhatsAppCatalogRuntimeConfig = {
  environment: SpazaEnvironment;
  queueEnabled: boolean;
  syncEnabled: boolean;
  providerMode: MetaCatalogProviderMode;
  catalogId: string;
  graphApiVersion: string;
  canaryMerchantIds: ReadonlySet<string>;
  fullRolloutEnabled: boolean;
  maxBatchSize: number;
};

function value(name: string): string {
  return String(process.env[name] ?? "").trim();
}

function enabled(name: string): boolean {
  return value(name).toLowerCase() === "true";
}

function boundedInteger(name: string, fallback: number, max: number): number {
  const configured = Number(value(name));
  return Number.isSafeInteger(configured) && configured > 0
    ? Math.min(max, configured)
    : fallback;
}

function providerMode(environment: SpazaEnvironment): MetaCatalogProviderMode {
  const raw = value("META_CATALOG_PROVIDER_MODE").toLowerCase();
  const inferred = raw || (environment === "local" ? "stub" : "disabled");
  if (!(["disabled", "stub", "test", "live"] as string[]).includes(inferred)) {
    throw new Error("META_CATALOG_PROVIDER_MODE_INVALID");
  }
  const mode = inferred as MetaCatalogProviderMode;
  if (environment === "development" && !["disabled", "test"].includes(mode)) {
    throw new Error("DEVELOPMENT_META_CATALOG_MODE_INVALID");
  }
  if (environment === "production" && !["disabled", "live"].includes(mode)) {
    throw new Error("PRODUCTION_META_CATALOG_MODE_INVALID");
  }
  if (environment === "local" && !["disabled", "stub"].includes(mode)) {
    throw new Error("LOCAL_META_CATALOG_MODE_INVALID");
  }
  return mode;
}

function canaryMerchantIds(): ReadonlySet<string> {
  const ids = value("WHATSAPP_CATALOG_CANARY_MERCHANT_IDS")
    .split(",")
    .map((id) => id.trim())
    .filter((id) => /^[A-Za-z0-9_-]{1,200}$/.test(id));
  return new Set(ids);
}

export function whatsappCatalogRuntimeConfig(): WhatsAppCatalogRuntimeConfig {
  const environment = resolveEnvironment();
  const queueEnabled = enabled("WHATSAPP_CATALOG_QUEUE_ENABLED");
  const syncEnabled = enabled("WHATSAPP_CATALOG_SYNC_ENABLED");
  const mode = providerMode(environment);
  const catalogId = value("WHATSAPP_CATALOG_ID");
  const graphApiVersion = value("META_GRAPH_API_VERSION") || "v25.0";
  const fullRolloutEnabled = enabled("WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED");
  const canaries = canaryMerchantIds();

  if (syncEnabled) {
    if (!queueEnabled) throw new Error("WHATSAPP_CATALOG_QUEUE_REQUIRED");
    if (mode === "disabled") throw new Error("META_CATALOG_PROVIDER_DISABLED");
    if (!/^\d{5,30}$/.test(catalogId)) {
      throw new Error("WHATSAPP_CATALOG_ID_INVALID");
    }
    if (!/^v\d{1,2}\.\d$/.test(graphApiVersion)) {
      throw new Error("META_GRAPH_API_VERSION_INVALID");
    }
    if (!fullRolloutEnabled && canaries.size === 0) {
      throw new Error("WHATSAPP_CATALOG_CANARY_REQUIRED");
    }
    if (environment === "development") {
      if (fullRolloutEnabled) {
        throw new Error("DEVELOPMENT_WHATSAPP_CATALOG_FULL_ROLLOUT_FORBIDDEN");
      }
      if (canaries.size !== 1) {
        throw new Error(
          "DEVELOPMENT_WHATSAPP_CATALOG_SINGLE_MERCHANT_REQUIRED",
        );
      }
    }
  }

  return {
    environment,
    queueEnabled,
    syncEnabled,
    providerMode: mode,
    catalogId,
    graphApiVersion,
    canaryMerchantIds: canaries,
    fullRolloutEnabled,
    maxBatchSize: boundedInteger("WHATSAPP_CATALOG_MAX_BATCH_SIZE", 10, 10),
  };
}

export function whatsappCatalogMerchantAllowed(
  config: WhatsAppCatalogRuntimeConfig,
  merchantId: string,
): boolean {
  return (
    config.syncEnabled &&
    (config.fullRolloutEnabled || config.canaryMerchantIds.has(merchantId))
  );
}

export function metaCatalogAccessToken(): string {
  const token = value("META_CATALOG_ACCESS_TOKEN");
  if (!token) throw new Error("META_CATALOG_ACCESS_TOKEN_MISSING");
  return token;
}
