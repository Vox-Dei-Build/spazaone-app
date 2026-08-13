import axios from "axios";
import { db } from "../config/main";
import { safeCjImageUrl } from "./cjImagePolicy";

const CJ_API_BASE = "https://developers.cjdropshipping.com/api2.0/v1";
const FX_API_URLS = [
  "https://api.frankfurter.dev/v1/latest?base=USD&symbols=ZAR",
  "https://api.frankfurter.dev/v2/rate/USD/ZAR?providers=SARB",
];
const REQUEST_TIMEOUT_MS = 15_000;
const CJ_REQUEST_INTERVAL_MS = 1_100;
const CJ_RATE_LIMIT_RETRY_MS = 1_500;
const CJ_GLOBAL_RATE_PATH = "supplierIntegrationState/cjRequestGate";
const CJ_MAX_QUEUE_MS = 30_000;
const TOKEN_SAFETY_MS = 5 * 60 * 1000;
const FX_CACHE_MS = 60 * 60 * 1000;
const FX_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

type JsonObject = Record<string, unknown>;
type CjRequestConfig = Parameters<typeof axios.request>[0];

type TokenCache = {
  accessToken: string;
  expiresAt: number;
};

export type CjFxRate = {
  rate: number;
  rateMicros: number;
  date: string;
  bufferBps: number;
};

export type CjCatalogProduct = {
  productId: string;
  productSku: string;
  title: string;
  image: string;
  category: string;
  productCostUsdMinor: number;
  estimatedProductCostMinor: number;
};

export type CjZaEligibleProduct = CjCatalogProduct & {
  deliverableVariantId: string;
  estimatedDeliveryCostMinor: number;
  estimatedLandedCostMinor: number;
  logisticAging: string;
  deliveryVerifiedAt: string;
};

export type CjVariant = {
  variantId: string;
  productId: string;
  sku: string;
  name: string;
  option: string;
  image: string;
  productCostUsdMinor: number;
  estimatedProductCostMinor: number;
};

export type CjProductDetails = {
  productId: string;
  productSku: string;
  title: string;
  description: string;
  images: string[];
  category: string;
  status: string;
  variants: CjVariant[];
  fx: CjFxRate;
};

export type CjLandedQuote = {
  product: CjProductDetails;
  variant: CjVariant;
  originCountryCode: string;
  stock: number;
  quantity: number;
  logisticName: string;
  logisticAging: string;
  productCostUsdMinor: number;
  shippingCostUsdMinor: number;
  productCostMinor: number;
  shippingCostMinor: number;
  landedCostMinor: number;
  currency: "ZAR";
  fx: CjFxRate;
  verifiedAt: string;
};

export type CjOrderInput = {
  orderNumber: string;
  variantId: string;
  quantity: number;
  logisticName: string;
  fromCountryCode: string;
  shipping: {
    postalCode: string;
    country: string;
    countryCode: "ZA";
    province: string;
    city: string;
    phone: string;
    customerName: string;
    address1: string;
    address2?: string;
    email?: string;
  };
};

export type CjCreatedOrder = {
  orderId: string;
  shipmentOrderId: string;
  orderNumber: string;
  actualPaymentUsdMinor: number;
  orderStatus: string;
  sandbox: boolean;
  requestId: string;
};

export type CjOrderDetail = {
  orderId: string;
  orderNumber: string;
  status: string;
  paid: boolean | null;
  actualPaymentUsdMinor: number | null;
  trackingNumber: string;
  trackingUrl: string;
};

let tokenCache: TokenCache | null = null;
let tokenRequest: Promise<string> | null = null;
let fxCache: (CjFxRate & { cachedAt: number }) | null = null;

export function createRequestScheduler(intervalMs: number) {
  let tail: Promise<void> = Promise.resolve();
  let lastStartedAt = 0;

  return async function schedule<T>(task: () => Promise<T>): Promise<T> {
    const run = tail.then(async () => {
      const waitMs = Math.max(0, lastStartedAt + intervalMs - Date.now());
      if (waitMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, waitMs));
      }
      lastStartedAt = Date.now();
      return task();
    });
    tail = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  };
}

// CJ enforces one request per second for this integration. Keep every request,
// including token exchange, on the same queue so a single function instance
// never creates the burst that previously made valid variants look unavailable.
const scheduleLocalCjRequest = createRequestScheduler(CJ_REQUEST_INTERVAL_MS);

export function calculateCjRequestSlot(
  nowMs: number,
  nextAllowedAtMs: number,
  intervalMs = CJ_REQUEST_INTERVAL_MS,
  maxQueueMs = CJ_MAX_QUEUE_MS,
): { slotAtMs: number; nextAllowedAtMs: number; waitMs: number } {
  const safeNext = Number.isSafeInteger(nextAllowedAtMs)
    ? nextAllowedAtMs
    : nowMs;
  const slotAtMs = Math.max(nowMs, safeNext);
  const waitMs = slotAtMs - nowMs;
  if (waitMs > maxQueueMs) throw new Error("CJ_RATE_LIMITED");
  return {
    slotAtMs,
    nextAllowedAtMs: slotAtMs + intervalMs,
    waitMs,
  };
}

async function reserveGlobalCjRequestSlot(): Promise<void> {
  const gateRef = db.doc(CJ_GLOBAL_RATE_PATH);
  let waitMs = 0;
  try {
    await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(gateRef);
      const nowMs = Date.now();
      const slot = calculateCjRequestSlot(
        nowMs,
        Number(snapshot.data()?.nextAllowedAtMs ?? nowMs),
      );
      waitMs = slot.waitMs;
      tx.set(
        gateRef,
        {
          supplierId: "cj_dropshipping",
          nextAllowedAtMs: slot.nextAllowedAtMs,
          updatedAtMs: nowMs,
          schemaVersion: 1,
        },
        { merge: true },
      );
    });
  } catch (error) {
    if (error instanceof Error && error.message.startsWith("CJ_")) throw error;
    throw new Error("CJ_COORDINATION_UNAVAILABLE");
  }
  if (waitMs > 0) {
    await new Promise((resolve) => setTimeout(resolve, waitMs));
  }
}

async function scheduleCjRequest<T>(task: () => Promise<T>): Promise<T> {
  return scheduleLocalCjRequest(async () => {
    await reserveGlobalCjRequestSlot();
    return task();
  });
}

function object(value: unknown): JsonObject {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as JsonObject)
    : {};
}

function list(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function text(value: unknown, max = 200): string {
  return String(value ?? "")
    .trim()
    .slice(0, max);
}

function positiveInteger(value: unknown): number {
  const amount = Number(value);
  return Number.isFinite(amount) && amount > 0 ? Math.floor(amount) : 0;
}

function apiKey(): string {
  const key = String(process.env.CJ_API_KEY ?? "").trim();
  if (!key) throw new Error("CJ_NOT_CONFIGURED");
  return key;
}

function fxBufferBps(): number {
  const configured = Number(process.env.CJ_FX_BUFFER_BPS ?? 300);
  if (
    !Number.isSafeInteger(configured) ||
    configured < 0 ||
    configured > 2000
  ) {
    return 300;
  }
  return configured;
}

export function usdMinor(value: unknown): number {
  const raw = text(value, 80).replace(/,/g, "");
  const match = raw.match(/-?\d+(?:\.\d+)?/);
  const dollars = match ? Number(match[0]) : Number(value);
  if (!Number.isFinite(dollars) || dollars < 0) {
    throw new Error("CJ_PRICE_INVALID");
  }
  const minor = Math.round(dollars * 100);
  if (!Number.isSafeInteger(minor)) throw new Error("CJ_PRICE_INVALID");
  return minor;
}

export function convertUsdMinorToZarMinor(
  amountUsdMinor: number,
  rate: number,
  bufferBps: number,
): number {
  if (
    !Number.isSafeInteger(amountUsdMinor) ||
    amountUsdMinor < 0 ||
    !Number.isFinite(rate) ||
    rate <= 0 ||
    !Number.isSafeInteger(bufferBps) ||
    bufferBps < 0
  ) {
    throw new Error("CJ_CONVERSION_INVALID");
  }
  const converted = Math.round(
    amountUsdMinor * rate * ((10_000 + bufferBps) / 10_000),
  );
  if (!Number.isSafeInteger(converted)) {
    throw new Error("CJ_CONVERSION_INVALID");
  }
  return converted;
}

function safeImage(value: unknown): string {
  return safeCjImageUrl(value);
}

function cleanDescription(value: unknown): string {
  return String(value ?? "")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 3000);
}

function parseExpiry(value: unknown, fallbackMs: number): number {
  const parsed = Date.parse(String(value ?? ""));
  return Number.isFinite(parsed) ? parsed : Date.now() + fallbackMs;
}

async function exchangeApiKey(retry = true): Promise<string> {
  try {
    const response = await scheduleCjRequest(() =>
      axios.post(
        `${CJ_API_BASE}/authentication/getAccessToken`,
        { apiKey: apiKey() },
        { timeout: REQUEST_TIMEOUT_MS },
      ),
    );
    const payload = object(response.data);
    const data = object(payload.data);
    const responseCode = text(payload.code, 40);
    if (responseCode === "1600200") {
      throw new Error("CJ_RATE_LIMITED");
    }
    // CJ access tokens are currently JWT-sized (observed at 566 characters),
    // despite older field documentation listing a much shorter maximum. Never
    // truncate a credential before sending it back in CJ-Access-Token.
    const accessToken = normalizeCjAccessToken(data.accessToken);
    if (payload.result !== true || !accessToken) {
      throw new Error("CJ_AUTH_FAILED");
    }
    tokenCache = {
      accessToken,
      expiresAt: parseExpiry(
        data.accessTokenExpiryDate,
        12 * 24 * 60 * 60 * 1000,
      ),
    };
    return accessToken;
  } catch (error) {
    const providerError = object(error);
    const response = object(providerError.response);
    const payload = object(response.data);
    // Never serialize the Axios request: it contains the CJ API key body.
    console.warn("CJ authentication failed", {
      responseStatus: Number(response.status) || null,
      upstreamCode: text(payload.code, 40) || null,
      upstreamMessage: text(payload.message, 200) || null,
      networkCode: text(providerError.code, 40) || null,
    });
    const rateLimited =
      Number(response.status) === 429 ||
      text(payload.code, 40) === "1600200" ||
      (error instanceof Error && error.message === "CJ_RATE_LIMITED");
    if (retry && rateLimited) {
      await new Promise((resolve) =>
        setTimeout(
          resolve,
          CJ_RATE_LIMIT_RETRY_MS + Math.floor(Math.random() * 500),
        ),
      );
      return exchangeApiKey(false);
    }
    if (rateLimited) {
      throw new Error("CJ_RATE_LIMITED");
    }
    throw new Error("CJ_AUTH_FAILED");
  }
}

export function normalizeCjAccessToken(value: unknown): string {
  return text(value, 4000);
}

async function accessToken(force = false): Promise<string> {
  if (
    !force &&
    tokenCache &&
    tokenCache.expiresAt - TOKEN_SAFETY_MS > Date.now()
  ) {
    return tokenCache.accessToken;
  }
  if (!force && tokenRequest) return tokenRequest;
  tokenRequest = exchangeApiKey().finally(() => {
    tokenRequest = null;
  });
  return tokenRequest;
}

function cjSucceeded(payload: JsonObject): boolean {
  return payload.result === true || payload.success === true;
}

async function cjRequest<T = unknown>(
  config: CjRequestConfig,
  retry = true,
): Promise<T> {
  const token = await accessToken();
  try {
    const response = await scheduleCjRequest(() =>
      axios.request({
        ...config,
        baseURL: CJ_API_BASE,
        timeout: REQUEST_TIMEOUT_MS,
        headers: {
          ...(config.data == null
            ? {}
            : { "Content-Type": "application/json" }),
          "CJ-Access-Token": token,
          ...(config.headers ?? {}),
        },
      }),
    );
    const payload = object(response.data);
    if (!cjSucceeded(payload)) {
      const code = text(payload.code, 40);
      const message = text(payload.message, 200).toLowerCase();
      if (retry && ["1600001", "1600003"].includes(code)) {
        tokenCache = null;
        await accessToken(true);
        return cjRequest<T>(config, false);
      }
      if (code === "1600200" || message.includes("too many requests")) {
        throw new Error("CJ_RATE_LIMITED");
      }
      if (
        code === "1600300" ||
        message.includes("order not found") ||
        message.includes("order does not exist")
      ) {
        throw new Error("CJ_ORDER_NOT_FOUND");
      }
      if (["1600001", "1600003"].includes(code)) {
        throw new Error("CJ_AUTH_FAILED");
      }
      throw new Error("CJ_UPSTREAM_REJECTED");
    }
    return payload.data as T;
  } catch (error) {
    const errorObject = object(error);
    const response = object(errorObject.response);
    const responseStatus = Number(response.status);
    const upstream = object(response.data);
    const upstreamCode = text(upstream.code, 40);
    const networkCode = text(errorObject.code, 40);
    // Keep enough upstream context to diagnose a supplier outage without
    // ever logging the CJ API key or access token.
    console.warn("CJ request failed", {
      path: text(config.url, 160),
      responseStatus: Number.isFinite(responseStatus) ? responseStatus : null,
      upstreamCode: upstreamCode || null,
      upstreamMessage: text(upstream.message, 200) || null,
      requestId: text(upstream.requestId, 80) || null,
      networkCode: networkCode || null,
    });
    const rateLimited =
      responseStatus === 429 ||
      upstreamCode === "1600200" ||
      (error instanceof Error && error.message === "CJ_RATE_LIMITED");
    if (retry && rateLimited) {
      await new Promise((resolve) =>
        setTimeout(
          resolve,
          CJ_RATE_LIMIT_RETRY_MS + Math.floor(Math.random() * 500),
        ),
      );
      return cjRequest<T>(config, false);
    }
    if (retry && responseStatus === 401) {
      tokenCache = null;
      await accessToken(true);
      return cjRequest<T>(config, false);
    }
    if (responseStatus === 401) throw new Error("CJ_AUTH_FAILED");
    if (rateLimited) throw new Error("CJ_RATE_LIMITED");
    if (error instanceof Error && error.message.startsWith("CJ_")) throw error;
    throw new Error("CJ_UNAVAILABLE");
  }
}

export function normalizeUsdZarRate(value: unknown): {
  rate: number;
  date: string;
} {
  const payload = object(value);
  const rates = object(payload.rates);
  const rate = Number(payload.rate ?? rates.ZAR);
  const date = text(payload.date, 10);
  const rateDate = Date.parse(`${date}T23:59:59Z`);
  if (
    !Number.isFinite(rate) ||
    rate <= 0 ||
    !Number.isFinite(rateDate) ||
    Date.now() - rateDate > FX_MAX_AGE_MS
  ) {
    throw new Error("CJ_FX_STALE");
  }
  return { rate, date };
}

export async function getUsdZarRate(): Promise<CjFxRate> {
  if (fxCache && Date.now() - fxCache.cachedAt < FX_CACHE_MS) {
    return {
      rate: fxCache.rate,
      rateMicros: fxCache.rateMicros,
      date: fxCache.date,
      bufferBps: fxCache.bufferBps,
    };
  }
  for (const url of FX_API_URLS) {
    try {
      const response = await axios.get(url, { timeout: REQUEST_TIMEOUT_MS });
      const normalized = normalizeUsdZarRate(response.data);
      fxCache = {
        rate: normalized.rate,
        rateMicros: Math.round(normalized.rate * 1_000_000),
        date: normalized.date,
        bufferBps: fxBufferBps(),
        cachedAt: Date.now(),
      };
      return {
        rate: fxCache.rate,
        rateMicros: fxCache.rateMicros,
        date: fxCache.date,
        bufferBps: fxCache.bufferBps,
      };
    } catch (error) {
      console.warn("USD/ZAR rate source failed", {
        source: new URL(url).pathname,
        code: error instanceof Error ? error.message : "unknown",
      });
    }
  }
  if (fxCache && Date.now() - fxCache.cachedAt < FX_MAX_AGE_MS) {
    return {
      rate: fxCache.rate,
      rateMicros: fxCache.rateMicros,
      date: fxCache.date,
      bufferBps: fxCache.bufferBps,
    };
  }
  throw new Error("CJ_FX_UNAVAILABLE");
}

export function normalizeCjSearchResponse(
  value: unknown,
  fx: CjFxRate,
): { products: CjCatalogProduct[]; page: number; totalPages: number } {
  const data = object(value);
  // Product List V2 currently wraps its result in a one-item `content`
  // array. Older responses used a direct object, so accept both shapes.
  const contentItems = list(data.content);
  const content = contentItems.length
    ? object(contentItems[0])
    : object(data.content);
  const rawProducts = list(content.productList).length
    ? list(content.productList)
    : list(data.list);
  const products = rawProducts
    .map((item): CjCatalogProduct | null => {
      const product = object(item);
      const productId = text(product.id ?? product.pid, 200);
      const title = text(product.nameEn ?? product.productNameEn, 200);
      if (!productId || !title) return null;
      let productCostUsdMinor: number;
      try {
        productCostUsdMinor = usdMinor(product.sellPrice);
      } catch (_) {
        return null;
      }
      return {
        productId,
        productSku: text(product.sku ?? product.spu ?? product.productSku, 200),
        title,
        image: safeImage(product.bigImage ?? product.productImage),
        category: text(product.threeCategoryName ?? product.categoryName, 160),
        productCostUsdMinor,
        estimatedProductCostMinor: convertUsdMinorToZarMinor(
          productCostUsdMinor,
          fx.rate,
          fx.bufferBps,
        ),
      };
    })
    .filter((product): product is CjCatalogProduct => product !== null);
  return {
    products,
    page: positiveInteger(data.pageNumber ?? data.page ?? data.pageNum) || 1,
    totalPages: Math.min(
      positiveInteger(data.totalPages ?? content.totalPages) ||
        (products.length ? 1 : 0),
      1000,
    ),
  };
}

function normalizeVariant(
  value: unknown,
  productId: string,
  fx: CjFxRate,
): CjVariant | null {
  const variant = object(value);
  const variantId = text(variant.vid, 200);
  if (!variantId) return null;
  let productCostUsdMinor: number;
  try {
    productCostUsdMinor = usdMinor(variant.variantSellPrice);
  } catch (_) {
    return null;
  }
  return {
    variantId,
    productId: text(variant.pid, 200) || productId,
    sku: text(variant.variantSku, 200),
    name: text(variant.variantNameEn ?? variant.variantName, 240),
    option: text(variant.variantKey ?? variant.variantStandard, 240),
    image: safeImage(variant.variantImage),
    productCostUsdMinor,
    estimatedProductCostMinor: convertUsdMinorToZarMinor(
      productCostUsdMinor,
      fx.rate,
      fx.bufferBps,
    ),
  };
}

export function normalizeCjProductDetails(
  value: unknown,
  fx: CjFxRate,
): CjProductDetails {
  const data = object(value);
  const productId = text(data.pid, 200);
  const title = text(data.productNameEn, 200);
  if (!productId || !title) throw new Error("CJ_PRODUCT_INVALID");
  const images = [data.bigImage, ...list(data.productImageSet)]
    .map(safeImage)
    .filter(Boolean)
    .filter((image, index, all) => all.indexOf(image) === index)
    .slice(0, 8);
  const variants = list(data.variants)
    .map((variant) => normalizeVariant(variant, productId, fx))
    .filter((variant): variant is CjVariant => variant !== null);
  if (!variants.length) throw new Error("CJ_VARIANTS_UNAVAILABLE");
  return {
    productId,
    productSku: text(data.productSku, 200),
    title,
    description: cleanDescription(data.description),
    images,
    category: text(data.categoryName, 160),
    status: text(data.status, 20),
    variants,
    fx,
  };
}

export async function searchCjProducts(input: {
  query: string;
  page: number;
  size?: number;
}): Promise<{
  products: CjCatalogProduct[];
  page: number;
  totalPages: number;
  fx: CjFxRate;
}> {
  const fx = await getUsdZarRate();
  const data = await cjRequest({
    method: "GET",
    url: "/product/listV2",
    params: {
      keyWord: input.query || undefined,
      page: input.page,
      size: input.size ?? 20,
      features: "enable_category",
    },
  });
  return { ...normalizeCjSearchResponse(data, fx), fx };
}

export async function getCjProductDetails(
  productId: string,
): Promise<CjProductDetails> {
  const [fx, data] = await Promise.all([
    getUsdZarRate(),
    cjRequest({
      method: "GET",
      url: "/product/query",
      params: { pid: productId },
    }),
  ]);
  return normalizeCjProductDetails(data, fx);
}

function inventoryOrigins(
  value: unknown,
): Array<{ countryCode: string; stock: number }> {
  return list(value)
    .map((item) => {
      const inventory = object(item);
      const countryCode = text(inventory.countryCode, 2).toUpperCase();
      const stock = Math.max(
        positiveInteger(inventory.totalInventory),
        positiveInteger(inventory.totalInventoryNum),
        positiveInteger(inventory.cjInventory),
        positiveInteger(inventory.cjInventoryNum),
        positiveInteger(inventory.factoryInventory),
        positiveInteger(inventory.factoryInventoryNum),
      );
      return { countryCode, stock };
    })
    .filter(
      (origin) => /^[A-Z]{2}$/.test(origin.countryCode) && origin.stock > 0,
    )
    .filter(
      (origin, index, all) =>
        all.findIndex(
          (candidate) => candidate.countryCode === origin.countryCode,
        ) === index,
    )
    .slice(0, 4);
}

type FreightOption = {
  originCountryCode: string;
  stock: number;
  logisticName: string;
  logisticAging: string;
  shippingCostUsdMinor: number;
};

async function freightOptions(
  origins: Array<{ countryCode: string; stock: number }>,
  variantId: string,
  postalCode: string,
  quantity = 1,
): Promise<FreightOption[]> {
  const results = await Promise.allSettled(
    origins.map(async (origin) => {
      const data = await cjRequest({
        method: "POST",
        url: "/logistic/freightCalculate",
        data: {
          startCountryCode: origin.countryCode,
          endCountryCode: "ZA",
          ...(postalCode ? { zip: postalCode } : {}),
          products: [{ quantity, vid: variantId }],
        },
      });
      return list(data)
        .map((item): FreightOption | null => {
          const option = object(item);
          const logisticName = text(option.logisticName, 120);
          if (!logisticName) return null;
          try {
            return {
              originCountryCode: origin.countryCode,
              stock: origin.stock,
              logisticName,
              logisticAging: text(option.logisticAging, 80),
              shippingCostUsdMinor: usdMinor(option.logisticPrice),
            };
          } catch (_) {
            return null;
          }
        })
        .filter((option): option is FreightOption => option !== null);
    }),
  );
  const options = results.flatMap((result) =>
    result.status === "fulfilled" ? result.value : [],
  );
  if (!options.length) {
    const transientFailure = results.find(
      (result): result is PromiseRejectedResult => result.status === "rejected",
    );
    if (transientFailure) throw transientFailure.reason;
  }
  return options;
}

async function quoteCjVariantWithProduct(input: {
  product: CjProductDetails;
  variantId: string;
  postalCode?: string;
  quantity?: number;
}): Promise<CjLandedQuote> {
  const product = input.product;
  const variantValue = await cjRequest({
    method: "GET",
    url: "/product/variant/queryByVid",
    params: { vid: input.variantId, features: "enable_inventory" },
  });
  const variantData = object(variantValue);
  if (product.status && product.status !== "3") {
    throw new Error("CJ_PRODUCT_UNAVAILABLE");
  }
  const variant = normalizeVariant(variantData, product.productId, product.fx);
  if (!variant || variant.productId !== product.productId) {
    throw new Error("CJ_VARIANT_INVALID");
  }
  let origins = inventoryOrigins(variantData.inventories);
  if (!origins.length) {
    const inventory = await cjRequest({
      method: "GET",
      url: "/product/stock/queryByVid",
      params: { vid: input.variantId },
    });
    origins = inventoryOrigins(inventory);
  }
  const quantity = Number(input.quantity ?? 1);
  if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 20) {
    throw new Error("CJ_QUANTITY_INVALID");
  }
  origins = origins.filter((origin) => origin.stock >= quantity);
  if (!origins.length) throw new Error("CJ_OUT_OF_STOCK");
  const options = await freightOptions(
    origins,
    input.variantId,
    text(input.postalCode, 12),
    quantity,
  );
  options.sort((a, b) => a.shippingCostUsdMinor - b.shippingCostUsdMinor);
  const selected = options[0];
  if (!selected) throw new Error("CJ_NO_SHIPPING_TO_ZA");
  const productCostUsdMinor = variant.productCostUsdMinor * quantity;
  const productCostMinor = convertUsdMinorToZarMinor(
    productCostUsdMinor,
    product.fx.rate,
    product.fx.bufferBps,
  );
  const shippingCostMinor = convertUsdMinorToZarMinor(
    selected.shippingCostUsdMinor,
    product.fx.rate,
    product.fx.bufferBps,
  );
  return {
    product,
    variant,
    originCountryCode: selected.originCountryCode,
    stock: selected.stock,
    quantity,
    logisticName: selected.logisticName,
    logisticAging: selected.logisticAging,
    productCostUsdMinor,
    shippingCostUsdMinor: selected.shippingCostUsdMinor,
    productCostMinor,
    shippingCostMinor,
    landedCostMinor: productCostMinor + shippingCostMinor,
    currency: "ZAR",
    fx: product.fx,
    verifiedAt: new Date().toISOString(),
  };
}

export async function quoteCjVariant(input: {
  productId: string;
  variantId: string;
  postalCode?: string;
  quantity?: number;
}): Promise<CjLandedQuote> {
  const product = await getCjProductDetails(input.productId);
  return quoteCjVariantWithProduct({
    product,
    variantId: input.variantId,
    postalCode: input.postalCode,
    quantity: input.quantity,
  });
}

export function cjSandboxMode(): boolean {
  return String(process.env.CJ_SANDBOX_MODE ?? "true").toLowerCase() === "true";
}

/**
 * CJ sandbox orders use provider-supported simulated payment and never deduct
 * the account's real balance. Keep a finite, server-only capacity so the same
 * reservation/locking code is still exercised without representing the real
 * provider balance as sandbox funding.
 */
export function cjSandboxFundingCapacityUsdMinor(): number | null {
  if (!cjSandboxMode()) return null;
  const environment = String(
    process.env.SPAZAONE_ENVIRONMENT ?? "",
  ).toLowerCase();
  if (!new Set(["development", "local"]).has(environment)) {
    throw new Error("CJ_SANDBOX_ENVIRONMENT_INVALID");
  }
  const capacity = Number(
    process.env.CJ_SANDBOX_FUNDING_CAPACITY_USD_MINOR ?? 1_000_000,
  );
  if (
    !Number.isSafeInteger(capacity) ||
    capacity < 1 ||
    capacity > 100_000_000
  ) {
    throw new Error("CJ_SANDBOX_FUNDING_CAPACITY_INVALID");
  }
  return capacity;
}

function requireCjPurchaseAuthority(): boolean {
  const sandbox = cjSandboxMode();
  if (
    !sandbox &&
    String(process.env.CJ_LIVE_FULFILMENT_ENABLED ?? "").toLowerCase() !==
      "true"
  ) {
    throw new Error("CJ_LIVE_FULFILMENT_DISABLED");
  }
  return sandbox;
}

/** Returns live balance or the explicitly labelled sandbox capacity in cents. */
export async function getCjBalanceUsdMinor(): Promise<number> {
  const sandboxCapacity = cjSandboxFundingCapacityUsdMinor();
  if (sandboxCapacity != null) return sandboxCapacity;
  const data = object(
    await cjRequest({
      method: "GET",
      url: "/shopping/pay/getBalance",
    }),
  );
  return usdMinor(data.amount);
}

/** Creates a CJ order without paying it so the actual charge can be checked. */
export async function createCjDropshipOrder(
  input: CjOrderInput,
): Promise<CjCreatedOrder> {
  const sandbox = requireCjPurchaseAuthority();
  const orderNumber = text(input.orderNumber, 50);
  const variantId = text(input.variantId, 50);
  const logisticName = text(input.logisticName, 50);
  const fromCountryCode = text(input.fromCountryCode, 2).toUpperCase();
  if (
    !orderNumber ||
    !variantId ||
    !logisticName ||
    !/^[A-Z]{2}$/.test(fromCountryCode) ||
    !Number.isSafeInteger(input.quantity) ||
    input.quantity <= 0
  ) {
    throw new Error("CJ_ORDER_INPUT_INVALID");
  }
  const shipping = input.shipping;
  const data = object(
    await cjRequest({
      method: "POST",
      url: "/shopping/order/createOrderV2",
      data: {
        orderNumber,
        shippingZip: text(shipping.postalCode, 20),
        shippingCountry: text(shipping.country, 50),
        shippingCountryCode: "ZA",
        shippingProvince: text(shipping.province, 50),
        shippingCity: text(shipping.city, 50),
        shippingPhone: text(shipping.phone, 20),
        shippingCustomerName: text(shipping.customerName, 50),
        shippingAddress: text(shipping.address1, 200),
        shippingAddress2: text(shipping.address2, 200),
        email: text(shipping.email, 50),
        payType: 3,
        isSandbox: sandbox ? 1 : 0,
        logisticName,
        fromCountryCode,
        platform: "api",
        orderFlow: 1,
        products: [
          {
            vid: variantId,
            quantity: input.quantity,
            storeLineItemId: orderNumber,
          },
        ],
      },
    }),
  );
  const orderId = text(data.orderId, 200);
  if (!orderId) throw new Error("CJ_ORDER_CREATE_INVALID");
  return {
    orderId,
    shipmentOrderId: text(data.shipmentOrderId, 200),
    orderNumber: text(data.orderNumber, 200) || orderNumber,
    actualPaymentUsdMinor: usdMinor(data.actualPayment ?? data.orderAmount),
    orderStatus: text(data.orderStatus, 40),
    sandbox,
    requestId: "",
  };
}

/** Pays an already-created single CJ order from the pre-funded balance. */
export async function payCjOrderFromBalance(
  orderIdValue: unknown,
): Promise<void> {
  requireCjPurchaseAuthority();
  const orderId = text(orderIdValue, 200);
  if (!orderId) throw new Error("CJ_ORDER_ID_INVALID");
  await cjRequest({
    method: "POST",
    url: "/shopping/pay/payBalance",
    data: { orderId },
  });
}

/** Reads authoritative CJ order/payment state before any retry or refund. */
export async function getCjOrderDetail(
  orderIdValue: unknown,
): Promise<CjOrderDetail> {
  const orderId = text(orderIdValue, 200);
  if (!orderId) throw new Error("CJ_ORDER_ID_INVALID");
  const data = object(
    await cjRequest({
      method: "GET",
      url: "/shopping/order/getOrderDetail",
      params: { orderId },
    }),
  );
  const status = text(
    data.orderStatus ?? data.status ?? data.orderStatusDesc,
    60,
  ).toUpperCase();
  const paymentStatus = text(
    data.paymentStatus ?? data.payStatus ?? data.paymentStatusDesc,
    60,
  ).toUpperCase();
  const paid =
    data.paid === true ||
    ["PAID", "UNSHIPPED", "SHIPPED", "DELIVERED", "PROCESSING"].includes(
      paymentStatus,
    ) ||
    ["UNSHIPPED", "SHIPPED", "DELIVERED"].includes(status)
      ? true
      : data.paid === false ||
          ["UNPAID", "CREATED", "IN_CART"].includes(paymentStatus) ||
          ["UNPAID", "CREATED", "IN_CART"].includes(status)
        ? false
        : null;
  let actualPaymentUsdMinor: number | null = null;
  try {
    actualPaymentUsdMinor = usdMinor(
      data.actualPayment ?? data.orderAmount ?? data.payAmount,
    );
  } catch (_) {
    actualPaymentUsdMinor = null;
  }
  const trackingNumber = text(
    data.trackingNumber ?? data.trackNumber ?? data.logisticTrackNumber,
    200,
  );
  const trackingUrlValue = text(
    data.trackingUrl ?? data.trackUrl ?? data.logisticTrackingUrl,
    500,
  );
  let trackingUrl = "";
  try {
    const parsed = new URL(trackingUrlValue);
    if (["http:", "https:"].includes(parsed.protocol))
      trackingUrl = parsed.toString();
  } catch (_) {
    trackingUrl = "";
  }
  return {
    orderId: text(data.orderId ?? data.id, 200) || orderId,
    orderNumber: text(data.orderNumber ?? data.orderNum, 200),
    status,
    paid,
    actualPaymentUsdMinor,
    trackingNumber,
    trackingUrl,
  };
}

/** Deletes only provider-confirmed pre-payment states allowed by CJ. */
export async function deleteCjOrderIfUnpaid(
  orderIdValue: unknown,
): Promise<boolean> {
  const detail = await getCjOrderDetail(orderIdValue);
  if (
    detail.paid !== false ||
    !["CREATED", "IN_CART"].includes(detail.status)
  ) {
    return false;
  }
  const result = await cjRequest({
    method: "DELETE",
    url: "/shopping/order/deleteOrder",
    params: { orderId: detail.orderId },
  });
  return result === true || object(result).success === true;
}

/**
 * Finds a current in-stock variant with at least one freight route to ZA.
 * A small variant sample keeps catalogue searches bounded; listing creation
 * and checkout still re-quote the seller/buyer-selected variant.
 */
export async function findCjProductZaDelivery(
  productId: string,
  maxVariants = 2,
  preferredVariantId = "",
): Promise<CjLandedQuote> {
  const product = await getCjProductDetails(productId);
  return findCjProductZaDeliveryFromDetails(
    product,
    maxVariants,
    preferredVariantId,
  );
}

export function prioritizedCjVariants(
  product: CjProductDetails,
  preferredVariantId: string,
  maxVariants: number,
): CjVariant[] {
  const preferred = product.variants.find(
    (variant) => variant.variantId === preferredVariantId,
  );
  const ordered = preferred
    ? [
        preferred,
        ...product.variants.filter((variant) => variant !== preferred),
      ]
    : product.variants;
  return ordered.slice(0, Math.max(1, maxVariants));
}

/**
 * Revalidates a cached recommendation first, then checks a small number of
 * alternatives one at a time. Sequential checks avoid CJ's one-QPS limit and
 * let the sheet recover automatically when an old variant stops shipping.
 */
export async function findCjProductZaDeliveryFromDetails(
  product: CjProductDetails,
  maxVariants = 4,
  preferredVariantId = "",
): Promise<CjLandedQuote> {
  if (product.status && product.status !== "3") {
    throw new Error("CJ_PRODUCT_UNAVAILABLE");
  }
  const variants = prioritizedCjVariants(
    product,
    preferredVariantId,
    maxVariants,
  );
  for (const variant of variants) {
    try {
      return await quoteCjVariantWithProduct({
        product,
        variantId: variant.variantId,
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      if (
        ![
          "CJ_NO_SHIPPING_TO_ZA",
          "CJ_OUT_OF_STOCK",
          "CJ_VARIANT_INVALID",
        ].includes(code)
      ) {
        throw error;
      }
    }
  }
  throw new Error("CJ_NO_SHIPPING_TO_ZA");
}

export function catalogProductWithZaDelivery(
  product: CjCatalogProduct,
  quote: CjLandedQuote,
): CjZaEligibleProduct {
  if (quote.product.productId !== product.productId) {
    throw new Error("CJ_PRODUCT_MISMATCH");
  }
  if (
    !quote.variant.variantId ||
    quote.productCostMinor <= 0 ||
    quote.shippingCostMinor < 0 ||
    quote.landedCostMinor <= 0
  ) {
    throw new Error("CJ_QUOTE_INVALID");
  }
  return {
    ...product,
    deliverableVariantId: quote.variant.variantId,
    estimatedDeliveryCostMinor: quote.shippingCostMinor,
    estimatedLandedCostMinor: quote.landedCostMinor,
    logisticAging: quote.logisticAging,
    deliveryVerifiedAt: quote.verifiedAt,
  };
}
