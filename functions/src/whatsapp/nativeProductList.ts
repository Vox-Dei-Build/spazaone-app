import { createHash, createHmac } from "crypto";
import { resolveEnvironment, SpazaEnvironment } from "../config/environment";
import { whatsappCatalogRuntimeConfig } from "./catalogConfig";

export const WHATSAPP_CATALOG_MIN_FIRST_PAGE_ITEMS = 5;
export const WHATSAPP_CATALOG_MAX_PAGE_ITEMS = 10;
export const WHATSAPP_PRODUCT_LIST_MIN_ITEMS =
  WHATSAPP_CATALOG_MIN_FIRST_PAGE_ITEMS;
export const WHATSAPP_PRODUCT_LIST_MAX_ITEMS = WHATSAPP_CATALOG_MAX_PAGE_ITEMS;

export type MetaWhatsAppMessageProviderMode =
  | "disabled"
  | "stub"
  | "test"
  | "live";

export type WhatsAppProductListRuntimeConfig = {
  environment: SpazaEnvironment;
  enabled: boolean;
  providerMode: MetaWhatsAppMessageProviderMode;
  catalogId: string;
  phoneNumberId: string;
  graphApiVersion: string;
  canaryMerchantIds: ReadonlySet<string>;
  fullRolloutEnabled: boolean;
  catalogSyncEnabled: boolean;
  catalogCanaryMerchantIds: ReadonlySet<string>;
  catalogFullRolloutEnabled: boolean;
  controlledRecipientHashes: ReadonlySet<string>;
  recipientCooldownMs: number;
  pairLimitPauseMs: number;
  maxAttempts: number;
};

export type WhatsAppCatalogDeliveryFormat =
  | "product_carousel"
  | "product_list"
  | "single_product";

type MetaWhatsAppInteractiveEnvelope<T> = {
  messaging_product: "whatsapp";
  recipient_type: "individual";
  to: string;
  type: "interactive";
  interactive: T;
};

export type MetaWhatsAppProductCarouselPayload =
  MetaWhatsAppInteractiveEnvelope<{
    type: "carousel";
    body: { text: string };
    action: {
      cards: Array<{
        card_index: number;
        type: "product";
        action: {
          catalog_id: string;
          product_retailer_id: string;
        };
      }>;
    };
  }>;

export type MetaWhatsAppProductListPayload = MetaWhatsAppInteractiveEnvelope<{
  type: "product_list";
  header: { type: "text"; text: string };
  body: { text: string };
  footer: { text: string };
  action: {
    catalog_id: string;
    sections: Array<{
      title: string;
      product_items: Array<{ product_retailer_id: string }>;
    }>;
  };
}>;

export type MetaWhatsAppSingleProductPayload = MetaWhatsAppInteractiveEnvelope<{
  type: "product";
  body: { text: string };
  footer: { text: string };
  action: {
    catalog_id: string;
    product_retailer_id: string;
  };
}>;

export type MetaWhatsAppCatalogPayload =
  | MetaWhatsAppProductCarouselPayload
  | MetaWhatsAppProductListPayload
  | MetaWhatsAppSingleProductPayload;

export type CatalogPageItem = {
  retailerId: string;
  lastAppliedRevision: string;
};

export type NativeCatalogPageDecision<T extends CatalogPageItem> =
  | {
      outcome: "ready";
      format: "product_carousel" | "single_product";
      page: number;
      pageCount: number;
      catalogVersion: string;
      items: T[];
    }
  | {
      outcome: "fallback";
      reason:
        | "fewer_than_five_ready_products"
        | "catalog_version_required"
        | "catalog_changed"
        | "page_out_of_range";
      page: number;
      pageCount: number;
      catalogVersion: string;
      availableProducts: number;
    };

export type NativeProductListDeliveryRecord = {
  fingerprint?: unknown;
  status?: unknown;
  attempts?: unknown;
  leaseUntilMs?: unknown;
  nextAttemptAtMs?: unknown;
  wamid?: unknown;
};

export type NativeProductListClaimDecision =
  | { action: "send"; attempt: number }
  | { action: "duplicate"; wamid: string }
  | {
      action:
        | "idempotency_conflict"
        | "in_progress"
        | "needs_review"
        | "retry_later"
        | "failed";
      retryAfterMs?: number;
    };

export class MetaWhatsAppProductListError extends Error {
  constructor(
    public readonly providerCode: string,
    public readonly retryable: boolean,
    public readonly ambiguous: boolean,
    public readonly retryAfterMs = 0,
  ) {
    super(providerCode);
    this.name = "MetaWhatsAppProductListError";
  }
}

function value(name: string): string {
  return String(process.env[name] ?? "").trim();
}

function enabled(name: string): boolean {
  return value(name).toLowerCase() === "true";
}

function boundedInteger(
  name: string,
  fallback: number,
  minimum: number,
  maximum: number,
): number {
  const configured = Number(value(name));
  return Number.isSafeInteger(configured) && configured >= minimum
    ? Math.min(maximum, configured)
    : fallback;
}

function providerMode(
  environment: SpazaEnvironment,
): MetaWhatsAppMessageProviderMode {
  const raw = value("META_WHATSAPP_MESSAGE_PROVIDER_MODE").toLowerCase();
  const inferred = raw || (environment === "local" ? "stub" : "disabled");
  if (!(<string[]>["disabled", "stub", "test", "live"]).includes(inferred)) {
    throw new Error("META_WHATSAPP_MESSAGE_PROVIDER_MODE_INVALID");
  }
  const mode = inferred as MetaWhatsAppMessageProviderMode;
  if (environment === "local" && !["disabled", "stub"].includes(mode)) {
    throw new Error("LOCAL_META_WHATSAPP_MESSAGE_MODE_INVALID");
  }
  if (environment === "development" && !["disabled", "test"].includes(mode)) {
    throw new Error("DEVELOPMENT_META_WHATSAPP_MESSAGE_MODE_INVALID");
  }
  if (environment === "production" && !["disabled", "live"].includes(mode)) {
    throw new Error("PRODUCTION_META_WHATSAPP_MESSAGE_MODE_INVALID");
  }
  return mode;
}

function canaryMerchantIds(): ReadonlySet<string> {
  const ids = value("WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS")
    .split(",")
    .map((id) => id.trim())
    .filter((id) => /^[A-Za-z0-9_-]{1,200}$/.test(id));
  return new Set(ids);
}

function controlledRecipientHashes(): ReadonlySet<string> {
  const raw = value("WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES");
  if (!raw) return new Set();
  const hashes = raw
    .split(",")
    .map((hash) => hash.trim().toLowerCase())
    .filter(Boolean);
  if (
    hashes.some((hash) => !/^[a-f0-9]{64}$/.test(hash)) ||
    new Set(hashes).size !== hashes.length
  ) {
    throw new Error("WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES_INVALID");
  }
  return new Set(hashes);
}

function controlledRecipientHashKey(): string {
  const key = value("WHATSAPP_CATALOG_RECIPIENT_HASH_KEY");
  if (key.length < 32 || key.length > 512) {
    throw new Error("WHATSAPP_CATALOG_RECIPIENT_HASH_KEY_INVALID");
  }
  return key;
}

export function whatsappProductListRuntimeConfig(): WhatsAppProductListRuntimeConfig {
  const environment = resolveEnvironment();
  const isEnabled = enabled("WHATSAPP_PRODUCT_LIST_ENABLED");
  const mode = providerMode(environment);
  const catalogId = value("WHATSAPP_CATALOG_ID");
  const phoneNumberId = value("WHATSAPP_SENDER_NUMBER_ID");
  const graphApiVersion = value("META_GRAPH_API_VERSION") || "v25.0";
  const canaries = canaryMerchantIds();
  const fullRolloutEnabled = enabled(
    "WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED",
  );
  const recipientHashes = controlledRecipientHashes();
  let catalogSyncEnabled = false;
  let catalogCanaries: ReadonlySet<string> = new Set();
  let catalogFullRolloutEnabled = false;

  if (isEnabled) {
    const catalogConfig = whatsappCatalogRuntimeConfig();
    catalogSyncEnabled = catalogConfig.syncEnabled;
    catalogCanaries = catalogConfig.canaryMerchantIds;
    catalogFullRolloutEnabled = catalogConfig.fullRolloutEnabled;
    if (!catalogSyncEnabled) {
      throw new Error("WHATSAPP_CATALOG_SYNC_REQUIRED");
    }
    if (catalogConfig.catalogId !== catalogId) {
      throw new Error("WHATSAPP_CATALOG_SCOPE_MISMATCH");
    }
    if (mode === "disabled") {
      throw new Error("META_WHATSAPP_MESSAGE_PROVIDER_DISABLED");
    }
    if (!/^\d{5,30}$/.test(catalogId)) {
      throw new Error("WHATSAPP_CATALOG_ID_INVALID");
    }
    if (!/^\d{5,30}$/.test(phoneNumberId)) {
      throw new Error("WHATSAPP_SENDER_NUMBER_ID_INVALID");
    }
    if (!/^v\d{1,2}\.\d$/.test(graphApiVersion)) {
      throw new Error("META_GRAPH_API_VERSION_INVALID");
    }
    if (!fullRolloutEnabled && canaries.size === 0) {
      throw new Error("WHATSAPP_PRODUCT_LIST_CANARY_REQUIRED");
    }
    const globalFullRollout = fullRolloutEnabled && catalogFullRolloutEnabled;
    if (!globalFullRollout && recipientHashes.size === 0) {
      throw new Error("WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_REQUIRED");
    }
    // Delivery ledgers and cart idempotency always use a keyed recipient
    // digest, including during full rollout. Only the membership list becomes
    // optional once both independent full-rollout switches are enabled.
    controlledRecipientHashKey();
    if (environment === "development") {
      if (fullRolloutEnabled) {
        throw new Error(
          "DEVELOPMENT_WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_FORBIDDEN",
        );
      }
      if (canaries.size !== 1) {
        throw new Error(
          "DEVELOPMENT_WHATSAPP_PRODUCT_LIST_SINGLE_MERCHANT_REQUIRED",
        );
      }
    }
  }

  return {
    environment,
    enabled: isEnabled,
    providerMode: mode,
    catalogId,
    phoneNumberId,
    graphApiVersion,
    canaryMerchantIds: canaries,
    fullRolloutEnabled,
    catalogSyncEnabled,
    catalogCanaryMerchantIds: catalogCanaries,
    catalogFullRolloutEnabled,
    controlledRecipientHashes: recipientHashes,
    recipientCooldownMs: boundedInteger(
      "WHATSAPP_PRODUCT_LIST_RECIPIENT_COOLDOWN_MS",
      7_000,
      1_000,
      60_000,
    ),
    pairLimitPauseMs: boundedInteger(
      "WHATSAPP_CATALOG_PAIR_LIMIT_PAUSE_MS",
      24 * 60 * 60_000,
      60_000,
      7 * 24 * 60 * 60_000,
    ),
    maxAttempts: boundedInteger("WHATSAPP_PRODUCT_LIST_MAX_ATTEMPTS", 3, 1, 3),
  };
}

export function whatsappProductListMerchantAllowed(
  config: WhatsAppProductListRuntimeConfig,
  merchantId: string,
): boolean {
  return (
    config.enabled &&
    config.catalogSyncEnabled &&
    (config.fullRolloutEnabled || config.canaryMerchantIds.has(merchantId)) &&
    (config.catalogFullRolloutEnabled ||
      config.catalogCanaryMerchantIds.has(merchantId))
  );
}

/**
 * Keyed one-way digest for controlled handset rollout. Plain phone numbers are
 * never stored in configuration or Firestore policy records.
 */
export function controlledWhatsAppRecipientDigest(
  recipient: string,
  hashKey: string,
): string {
  if (hashKey.length < 32 || hashKey.length > 512) {
    throw new Error("WHATSAPP_CATALOG_RECIPIENT_HASH_KEY_INVALID");
  }
  return createHmac("sha256", hashKey)
    .update(
      `spazaone:whatsapp-catalog-recipient:v1\u0000${normalizeWhatsAppRecipient(recipient)}`,
    )
    .digest("hex");
}

export function whatsappProductListRecipientAllowed(
  config: WhatsAppProductListRuntimeConfig,
  recipient: string,
): boolean {
  if (!config.enabled || !config.catalogSyncEnabled) {
    return false;
  }
  if (config.fullRolloutEnabled && config.catalogFullRolloutEnabled) {
    return true;
  }
  if (config.controlledRecipientHashes.size === 0) return false;
  return config.controlledRecipientHashes.has(
    currentControlledWhatsAppRecipientDigest(recipient),
  );
}

export function currentControlledWhatsAppRecipientDigest(
  recipient: string,
): string {
  return controlledWhatsAppRecipientDigest(
    recipient,
    controlledRecipientHashKey(),
  );
}

export function whatsappNativeCatalogAccessReason(
  config: WhatsAppProductListRuntimeConfig,
  merchantId: string,
  recipient: string,
):
  | "feature_disabled"
  | "merchant_not_allowed"
  | "recipient_not_allowed"
  | undefined {
  if (!config.enabled) return "feature_disabled";
  if (!whatsappProductListMerchantAllowed(config, merchantId)) {
    return "merchant_not_allowed";
  }
  if (!whatsappProductListRecipientAllowed(config, recipient)) {
    return "recipient_not_allowed";
  }
  return undefined;
}

export function metaWhatsAppAccessToken(): string {
  const token = value("META_WHATSAPP_ACCESS_TOKEN");
  if (!token) throw new Error("META_WHATSAPP_ACCESS_TOKEN_MISSING");
  return token;
}

export function normalizeWhatsAppRecipient(value: unknown): string {
  const compact = String(value ?? "").replace(/[^\d+]/g, "");
  const normalized = compact.startsWith("0")
    ? `+27${compact.slice(1)}`
    : compact.startsWith("+")
      ? compact
      : `+${compact}`;
  if (!/^\+[1-9]\d{7,14}$/.test(normalized)) {
    throw new Error("WHATSAPP_RECIPIENT_INVALID");
  }
  return normalized;
}

function normalizedRetailerIds(
  values: readonly string[],
  minimum: number,
  errorCode: string,
): string[] {
  const ids = values.map((id) => id.trim());
  if (
    ids.length < minimum ||
    ids.length > WHATSAPP_CATALOG_MAX_PAGE_ITEMS ||
    new Set(ids).size !== ids.length ||
    ids.some((id) => !/^spz_[a-f0-9]{32}$/.test(id))
  ) {
    throw new Error(errorCode);
  }
  return ids;
}

function normalizedCatalogId(value: string): string {
  const catalogId = value.trim();
  if (!/^\d{5,30}$/.test(catalogId)) {
    throw new Error("WHATSAPP_CATALOG_ID_INVALID");
  }
  return catalogId;
}

function envelope<T>(
  recipient: string,
  interactive: T,
): MetaWhatsAppInteractiveEnvelope<T> {
  return {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: normalizeWhatsAppRecipient(recipient).slice(1),
    type: "interactive",
    interactive,
  };
}

/** Exact Meta interactive product-carousel shape: one request, 2-10 cards. */
export function buildMetaWhatsAppProductCarouselPayload(input: {
  recipient: string;
  catalogId: string;
  productRetailerIds: readonly string[];
  page?: number;
  pageCount?: number;
}): MetaWhatsAppProductCarouselPayload {
  const catalogId = normalizedCatalogId(input.catalogId);
  const ids = normalizedRetailerIds(
    input.productRetailerIds,
    2,
    "WHATSAPP_PRODUCT_CAROUSEL_ITEMS_INVALID",
  );
  const page = Number(input.page ?? 0);
  const pageCount = Number(input.pageCount ?? 1);
  if (
    !Number.isSafeInteger(page) ||
    !Number.isSafeInteger(pageCount) ||
    page < 0 ||
    pageCount < 1 ||
    page >= pageCount
  ) {
    throw new Error("WHATSAPP_PRODUCT_CAROUSEL_PAGE_INVALID");
  }
  const navigation =
    page + 1 < pageCount && page > 0
      ? "Reply More for the next products or Back for the previous products."
      : page + 1 < pageCount
        ? "Reply More for the next products."
        : page > 0
          ? "Reply Back for the previous products."
          : "";
  return envelope(input.recipient, {
    type: "carousel",
    body: {
      text: [
        "Browse this shop's pictured products. Select one to view details and choose a quantity.",
        navigation,
      ]
        .filter(Boolean)
        .join(" "),
    },
    action: {
      cards: ids.map((productRetailerId, cardIndex) => ({
        card_index: cardIndex,
        type: "product",
        action: {
          catalog_id: catalogId,
          product_retailer_id: productRetailerId,
        },
      })),
    },
  });
}

/** Native product-list fallback; never used as ordinary Botpress cards. */
export function buildMetaWhatsAppProductListPayload(input: {
  recipient: string;
  catalogId: string;
  productRetailerIds: readonly string[];
}): MetaWhatsAppProductListPayload {
  const catalogId = normalizedCatalogId(input.catalogId);
  const ids = normalizedRetailerIds(
    input.productRetailerIds,
    2,
    "WHATSAPP_PRODUCT_LIST_ITEMS_INVALID",
  );
  return envelope(input.recipient, {
    type: "product_list",
    header: { type: "text", text: "Shop products" },
    body: {
      text: "Browse pictures and prices from this shop. Select one to view details and choose a quantity.",
    },
    footer: { text: "Send More or Back to browse pages" },
    action: {
      catalog_id: catalogId,
      sections: [
        {
          title: "Products",
          product_items: ids.map((productRetailerId) => ({
            product_retailer_id: productRetailerId,
          })),
        },
      ],
    },
  });
}

export function buildMetaWhatsAppSingleProductPayload(input: {
  recipient: string;
  catalogId: string;
  productRetailerId: string;
}): MetaWhatsAppSingleProductPayload {
  const catalogId = normalizedCatalogId(input.catalogId);
  const [productRetailerId] = normalizedRetailerIds(
    [input.productRetailerId],
    1,
    "WHATSAPP_SINGLE_PRODUCT_ITEM_INVALID",
  );
  return envelope(input.recipient, {
    type: "product",
    body: {
      text: "Here is the final product. Select it to view details and choose a quantity.",
    },
    footer: { text: "Send Back to return to the previous products" },
    action: { catalog_id: catalogId, product_retailer_id: productRetailerId },
  });
}

export function orderedCatalogVersion(
  items: readonly CatalogPageItem[],
): string {
  return createHash("sha256")
    .update(
      JSON.stringify(
        items.map(({ retailerId, lastAppliedRevision }) => [
          retailerId,
          lastAppliedRevision,
        ]),
      ),
    )
    .digest("hex");
}

/**
 * Slices an already deterministically ordered projection. A version is bound
 * to every continuation so catalog churn cannot create duplicate or skipped
 * products between explicit More/Back requests.
 */
export function selectNativeCatalogPage<T extends CatalogPageItem>(input: {
  items: readonly T[];
  page: number;
  catalogVersion?: string;
}): NativeCatalogPageDecision<T> {
  const catalogVersion = orderedCatalogVersion(input.items);
  const pageCount = Math.ceil(
    input.items.length / WHATSAPP_CATALOG_MAX_PAGE_ITEMS,
  );
  const fallback = (
    reason: Extract<
      NativeCatalogPageDecision<T>,
      { outcome: "fallback" }
    >["reason"],
  ): NativeCatalogPageDecision<T> => ({
    outcome: "fallback",
    reason,
    page: input.page,
    pageCount,
    catalogVersion,
    availableProducts: input.items.length,
  });
  if (input.catalogVersion && input.catalogVersion !== catalogVersion) {
    return fallback("catalog_changed");
  }
  if (
    input.page === 0 &&
    input.items.length < WHATSAPP_CATALOG_MIN_FIRST_PAGE_ITEMS
  ) {
    return fallback("fewer_than_five_ready_products");
  }
  if (input.page > 0 && !input.catalogVersion) {
    return fallback("catalog_version_required");
  }
  const start = input.page * WHATSAPP_CATALOG_MAX_PAGE_ITEMS;
  if (start >= input.items.length) return fallback("page_out_of_range");
  const items = input.items.slice(
    start,
    start + WHATSAPP_CATALOG_MAX_PAGE_ITEMS,
  );
  return {
    outcome: "ready",
    format: items.length === 1 ? "single_product" : "product_carousel",
    page: input.page,
    pageCount,
    catalogVersion,
    items,
  };
}

export function productListDeliveryFingerprint(input: {
  merchantId: string;
  recipientHash: string;
  senderPhoneNumberId: string;
  catalogId: string;
  format?: WhatsAppCatalogDeliveryFormat;
  page: number;
  pageCount?: number;
  catalogVersion?: string;
  productRetailerIds: readonly string[];
}): string {
  if (!/^[a-f0-9]{64}$/.test(input.recipientHash)) {
    throw new Error("WHATSAPP_RECIPIENT_HASH_INVALID");
  }
  return createHash("sha256")
    .update(
      JSON.stringify({
        merchantId: input.merchantId,
        recipientHash: input.recipientHash,
        senderPhoneNumberId: input.senderPhoneNumberId,
        catalogId: input.catalogId,
        format: input.format ?? "product_list",
        page: input.page,
        pageCount: input.pageCount ?? 1,
        catalogVersion: input.catalogVersion ?? "",
        productRetailerIds: [...input.productRetailerIds],
      }),
    )
    .digest("hex");
}

export function opaqueProductListId(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export function decideNativeProductListClaim(input: {
  existing?: NativeProductListDeliveryRecord;
  fingerprint: string;
  nowMs: number;
  recipientNextAllowedAtMs: number;
  maxAttempts: number;
}): NativeProductListClaimDecision {
  const existing = input.existing;
  if (existing && String(existing.fingerprint ?? "") !== input.fingerprint) {
    return { action: "idempotency_conflict" };
  }
  const status = String(existing?.status ?? "");
  const wamid = String(existing?.wamid ?? "").trim();
  if (status === "sent" && wamid) {
    return { action: "duplicate", wamid };
  }
  if (status === "needs_review") return { action: "needs_review" };
  if (status === "failed") return { action: "failed" };
  if (status === "sending") {
    const leaseUntilMs = Number(existing?.leaseUntilMs ?? 0);
    return leaseUntilMs > input.nowMs
      ? { action: "in_progress", retryAfterMs: leaseUntilMs - input.nowMs }
      : { action: "needs_review" };
  }
  const attempts = Number(existing?.attempts ?? 0);
  if (attempts >= input.maxAttempts) return { action: "failed" };
  const nextAttemptAtMs = Number(existing?.nextAttemptAtMs ?? 0);
  // Pair-limit and cooldown state applies to every attempt, including a retry
  // of an existing delivery. Otherwise a short per-delivery backoff could
  // bypass the recipient-wide 131056 pause.
  const retryAtMs = Math.max(nextAttemptAtMs, input.recipientNextAllowedAtMs);
  if (retryAtMs > input.nowMs) {
    return { action: "retry_later", retryAfterMs: retryAtMs - input.nowMs };
  }
  return { action: "send", attempt: attempts + 1 };
}

export function productListRetryDelayMs(attempt: number): number {
  const exponent = Math.max(0, Math.min(2, attempt - 1));
  return Math.min(60_000, 7_000 * Math.pow(2, exponent));
}

function safeProviderCode(value: unknown): string {
  return String(value ?? "META_WHATSAPP_MESSAGE_FAILED")
    .replace(/[^A-Za-z0-9_-]/g, "_")
    .slice(0, 100);
}

function retryAfterMs(response: Response): number {
  const seconds = Number(response.headers.get("retry-after") ?? 0);
  return Number.isFinite(seconds) && seconds > 0
    ? Math.min(15 * 60_000, Math.round(seconds * 1000))
    : 0;
}

export async function sendMetaWhatsAppCatalog(input: {
  config: WhatsAppProductListRuntimeConfig;
  payload: MetaWhatsAppCatalogPayload;
  fetchImpl?: typeof fetch;
}): Promise<{ wamid: string }> {
  const encoded = JSON.stringify(input.payload);
  if (input.config.providerMode === "stub") {
    return {
      wamid: `wamid.stub.${createHash("sha256")
        .update(encoded)
        .digest("hex")
        .slice(0, 32)}`,
    };
  }
  if (!(<string[]>["test", "live"]).includes(input.config.providerMode)) {
    throw new MetaWhatsAppProductListError(
      "META_WHATSAPP_MESSAGE_PROVIDER_DISABLED",
      false,
      false,
    );
  }
  const url =
    `https://graph.facebook.com/${input.config.graphApiVersion}/` +
    `${input.config.phoneNumberId}/messages`;
  let response: Response;
  try {
    response = await (input.fetchImpl ?? fetch)(url, {
      method: "POST",
      headers: {
        authorization: `Bearer ${metaWhatsAppAccessToken()}`,
        "content-type": "application/json",
      },
      body: encoded,
      signal: AbortSignal.timeout(20_000),
    });
  } catch (_) {
    throw new MetaWhatsAppProductListError(
      "META_WHATSAPP_MESSAGE_NETWORK_OUTCOME_UNKNOWN",
      false,
      true,
    );
  }
  let body: Record<string, unknown> = {};
  try {
    body = (await response.json()) as Record<string, unknown>;
  } catch (_) {
    // The HTTP status still determines whether another attempt is safe.
  }
  if (!response.ok) {
    const error =
      body.error && typeof body.error === "object"
        ? (body.error as Record<string, unknown>)
        : {};
    const status = response.status;
    const providerErrorCode = Number(error.code ?? 0);
    const code = safeProviderCode(
      `META_WHATSAPP_${status}_${providerErrorCode || "ERROR"}_` +
        `${error.error_subcode ?? ""}`,
    );
    const rateLimited =
      status === 429 || [4, 80007, 130429, 131056].includes(providerErrorCode);
    const ambiguous = status === 408 || status >= 500;
    throw new MetaWhatsAppProductListError(
      code,
      rateLimited,
      ambiguous,
      retryAfterMs(response),
    );
  }
  const messages = Array.isArray(body.messages) ? body.messages : [];
  const first = messages[0];
  const wamid =
    first && typeof first === "object"
      ? String((first as Record<string, unknown>).id ?? "").trim()
      : "";
  if (!wamid || messages.length !== 1) {
    throw new MetaWhatsAppProductListError(
      "META_WHATSAPP_MESSAGE_ID_OUTCOME_UNKNOWN",
      false,
      true,
    );
  }
  return { wamid };
}

/**
 * Ordered native fallback. A second provider request is permitted only after
 * Meta definitively rejected the carousel before accepting a message. Rate
 * limits and ambiguous/post-dispatch outcomes are returned to the delivery
 * ledger without another request.
 */
export async function sendMetaWhatsAppCatalogWithFallback(input: {
  config: WhatsAppProductListRuntimeConfig;
  primaryPayload: MetaWhatsAppCatalogPayload;
  productListFallbackPayload?: MetaWhatsAppProductListPayload;
  fetchImpl?: typeof fetch;
}): Promise<{
  wamid: string;
  format: WhatsAppCatalogDeliveryFormat;
  providerRequests: 1 | 2;
}> {
  const primaryFormat: WhatsAppCatalogDeliveryFormat =
    input.primaryPayload.interactive.type === "carousel"
      ? "product_carousel"
      : input.primaryPayload.interactive.type === "product_list"
        ? "product_list"
        : "single_product";
  try {
    const result = await sendMetaWhatsAppCatalog({
      config: input.config,
      payload: input.primaryPayload,
      ...(input.fetchImpl ? { fetchImpl: input.fetchImpl } : {}),
    });
    return { ...result, format: primaryFormat, providerRequests: 1 };
  } catch (error) {
    if (
      !(error instanceof MetaWhatsAppProductListError) ||
      error.retryable ||
      error.ambiguous ||
      primaryFormat !== "product_carousel" ||
      !input.productListFallbackPayload
    ) {
      throw error;
    }
  }
  const fallback = await sendMetaWhatsAppCatalog({
    config: input.config,
    payload: input.productListFallbackPayload,
    ...(input.fetchImpl ? { fetchImpl: input.fetchImpl } : {}),
  });
  return { ...fallback, format: "product_list", providerRequests: 2 };
}

export const sendMetaWhatsAppProductList = sendMetaWhatsAppCatalog;
