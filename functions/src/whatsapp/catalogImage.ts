export type CatalogImageProbeResult = {
  state: "valid" | "invalid" | "transient";
  code: string;
  contentType: string;
  httpStatus: number;
};

export function supportedCatalogImageContentType(value: unknown): boolean {
  const type = String(value ?? "")
    .split(";")[0]
    .trim()
    .toLowerCase();
  return type === "image/jpeg" || type === "image/png";
}

export function classifyCatalogImageResponse(input: {
  status: number;
  contentType: string;
  finalUrlIsHttps: boolean;
}): CatalogImageProbeResult {
  const contentType = input.contentType.split(";")[0].trim().toLowerCase();
  if (
    input.finalUrlIsHttps &&
    input.status >= 200 &&
    input.status < 300 &&
    supportedCatalogImageContentType(contentType)
  ) {
    return {
      state: "valid",
      code: "IMAGE_OK",
      contentType,
      httpStatus: input.status,
    };
  }
  if (
    input.status === 0 ||
    input.status === 408 ||
    input.status === 425 ||
    input.status === 429 ||
    input.status >= 500
  ) {
    return {
      state: "transient",
      code: `IMAGE_TRANSIENT_${input.status || "NETWORK"}`,
      contentType,
      httpStatus: input.status,
    };
  }
  return {
    state: "invalid",
    code: !input.finalUrlIsHttps
      ? "IMAGE_REDIRECT_NOT_HTTPS"
      : supportedCatalogImageContentType(contentType)
        ? `IMAGE_HTTP_${input.status}`
        : "IMAGE_CONTENT_TYPE_UNSUPPORTED",
    contentType,
    httpStatus: input.status,
  };
}

async function imageRequest(
  url: string,
  method: "HEAD" | "GET",
): Promise<CatalogImageProbeResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 6_000);
  try {
    const response = await fetch(url, {
      method,
      redirect: "follow",
      signal: controller.signal,
      headers: method === "GET" ? { Range: "bytes=0-2047" } : undefined,
    });
    if (response.body) await response.body.cancel().catch(() => undefined);
    let finalUrlIsHttps = false;
    try {
      finalUrlIsHttps = new URL(response.url).protocol === "https:";
    } catch (_) {
      finalUrlIsHttps = false;
    }
    return classifyCatalogImageResponse({
      status: response.status,
      contentType: response.headers.get("content-type") ?? "",
      finalUrlIsHttps,
    });
  } catch (_) {
    return {
      state: "transient",
      code: "IMAGE_TRANSIENT_NETWORK",
      contentType: "",
      httpStatus: 0,
    };
  } finally {
    clearTimeout(timer);
  }
}

/** Read-only media preflight. No image bytes are retained. */
export async function probeCatalogImageUrl(
  url: string,
): Promise<CatalogImageProbeResult> {
  const head = await imageRequest(url, "HEAD");
  if (head.state === "valid") return head;
  return imageRequest(url, "GET");
}
