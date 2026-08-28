import axios, { isAxiosError } from "axios";
import { createHash } from "crypto";
import {
  WhatsAppCatalogRuntimeConfig,
  metaCatalogAccessToken,
} from "./catalogConfig";
import { MerchantCatalogProjection } from "./catalogProjection";

export type MetaCatalogMutation =
  | {
      action: "upsert";
      retailerId: string;
      projection: MerchantCatalogProjection;
    }
  | { action: "delete"; retailerId: string };

export type MetaCatalogBatchStatus = {
  state: "pending" | "complete";
  handle: string;
  invalidRetailerIds: ReadonlySet<string>;
  errors: number;
  warnings: number;
};

type MetaBatchRequest = {
  method: "UPDATE" | "DELETE";
  data: Record<string, unknown>;
};

export class MetaCatalogProviderError extends Error {
  constructor(
    public readonly providerCode: string,
    public readonly retryable: boolean,
  ) {
    super(providerCode);
  }
}

function formattedPrice(minor: number, currency: string): string {
  return `${(minor / 100).toFixed(2)} ${currency}`;
}

export function buildMetaCatalogBatchRequests(
  mutations: readonly MetaCatalogMutation[],
): MetaBatchRequest[] {
  return mutations.map((mutation) => {
    if (mutation.action === "delete") {
      return { method: "DELETE", data: { id: mutation.retailerId } };
    }
    const item = mutation.projection;
    return {
      method: "UPDATE",
      data: {
        id: mutation.retailerId,
        title: item.title,
        description: item.description,
        image_link: item.imageUrl,
        link: item.link,
        brand: item.brand,
        price: formattedPrice(item.priceMinor, item.currency),
        availability: item.availability,
        visibility: "published",
        condition: item.condition,
      },
    };
  });
}

function graphUrl(config: WhatsAppCatalogRuntimeConfig, edge: string): string {
  return `https://graph.facebook.com/${config.graphApiVersion}/${config.catalogId}/${edge}`;
}

function providerError(error: unknown): MetaCatalogProviderError {
  if (error instanceof MetaCatalogProviderError) return error;
  if (!isAxiosError(error)) {
    return new MetaCatalogProviderError("META_CATALOG_NETWORK_ERROR", true);
  }
  const status = Number(error.response?.status ?? 0);
  const response = error.response?.data as
    | {
        error?: {
          code?: unknown;
          error_subcode?: unknown;
          is_transient?: unknown;
        };
      }
    | undefined;
  const code = Number(response?.error?.code ?? 0);
  const subcode = Number(response?.error?.error_subcode ?? 0);
  const retryable =
    response?.error?.is_transient === true ||
    status === 0 ||
    status === 408 ||
    status === 429 ||
    status >= 500;
  const providerCode = ["META_CATALOG", status || "NETWORK", code, subcode]
    .filter((part) => part !== 0)
    .join("_")
    .slice(0, 100);
  return new MetaCatalogProviderError(providerCode, retryable);
}

function stubHandle(requests: readonly MetaBatchRequest[]): string {
  return `stub_${createHash("sha256")
    .update(JSON.stringify(requests))
    .digest("hex")
    .slice(0, 24)}`;
}

export async function submitMetaCatalogBatch(
  mutations: readonly MetaCatalogMutation[],
  config: WhatsAppCatalogRuntimeConfig,
): Promise<{ handle: string }> {
  if (!mutations.length || mutations.length > config.maxBatchSize) {
    throw new Error("META_CATALOG_BATCH_SIZE_INVALID");
  }
  const requests = buildMetaCatalogBatchRequests(mutations);
  if (config.providerMode === "stub") return { handle: stubHandle(requests) };
  if (!(config.providerMode === "test" || config.providerMode === "live")) {
    throw new MetaCatalogProviderError("META_CATALOG_PROVIDER_DISABLED", false);
  }

  const body = new URLSearchParams();
  body.set("allow_upsert", "true");
  body.set("item_type", "PRODUCT_ITEM");
  body.set("requests", JSON.stringify(requests));
  try {
    const response = await axios.post(graphUrl(config, "items_batch"), body, {
      timeout: 20_000,
      headers: {
        Authorization: `Bearer ${metaCatalogAccessToken()}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
    });
    const handles = Array.isArray(response.data?.handles)
      ? response.data.handles.map(String).filter(Boolean)
      : [];
    if (!handles.length) {
      throw new MetaCatalogProviderError(
        "META_CATALOG_BATCH_HANDLE_MISSING",
        true,
      );
    }
    return { handle: handles[0] };
  } catch (error) {
    throw providerError(error);
  }
}

function numeric(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

export function parseMetaCatalogBatchStatus(
  value: unknown,
  fallbackHandle: string,
): MetaCatalogBatchStatus {
  const envelope =
    value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : {};
  const data = Array.isArray(envelope.data) ? envelope.data[0] : envelope;
  const result =
    data && typeof data === "object" ? (data as Record<string, unknown>) : {};
  const rawStatus = String(result.status ?? "")
    .trim()
    .toLowerCase();
  const complete = [
    "complete",
    "completed",
    "done",
    "finished",
    "success",
  ].includes(rawStatus);
  const invalid = Array.isArray(result.ids_of_invalid_requests)
    ? result.ids_of_invalid_requests.map(String).filter(Boolean)
    : [];
  return {
    state: complete ? "complete" : "pending",
    handle: String(result.handle ?? fallbackHandle),
    invalidRetailerIds: new Set(invalid),
    errors: numeric(result.errors_total_count),
    warnings: numeric(result.warnings_total_count),
  };
}

export async function checkMetaCatalogBatch(
  handle: string,
  config: WhatsAppCatalogRuntimeConfig,
): Promise<MetaCatalogBatchStatus> {
  if (config.providerMode === "stub") {
    return {
      state: "complete",
      handle,
      invalidRetailerIds: new Set(),
      errors: 0,
      warnings: 0,
    };
  }
  if (!(config.providerMode === "test" || config.providerMode === "live")) {
    throw new MetaCatalogProviderError("META_CATALOG_PROVIDER_DISABLED", false);
  }
  try {
    const response = await axios.get(
      graphUrl(config, "check_batch_request_status"),
      {
        timeout: 15_000,
        headers: { Authorization: `Bearer ${metaCatalogAccessToken()}` },
        params: {
          fields:
            "handle,status,errors_total_count,warnings_total_count,ids_of_invalid_requests",
          handle,
          load_ids_of_invalid_requests: true,
        },
      },
    );
    return parseMetaCatalogBatchStatus(response.data, handle);
  } catch (error) {
    throw providerError(error);
  }
}
