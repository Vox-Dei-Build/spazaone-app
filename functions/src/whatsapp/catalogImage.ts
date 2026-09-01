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
  return type === "image/jpeg" || type === "image/jpg" || type === "image/png";
}

export function detectedCatalogImageContentType(
  value: Uint8Array,
): "image/jpeg" | "image/png" | "" {
  if (
    value.length >= 3 &&
    value[0] === 0xff &&
    value[1] === 0xd8 &&
    value[2] === 0xff
  ) {
    return "image/jpeg";
  }
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  return value.length >= png.length && png.every((byte, i) => value[i] === byte)
    ? "image/png"
    : "";
}

export function classifyCatalogImageResponse(input: {
  status: number;
  contentType: string;
  finalUrlIsHttps: boolean;
  detectedContentType?: string;
}): CatalogImageProbeResult {
  const contentType = input.contentType.split(";")[0].trim().toLowerCase();
  const genericBinary =
    !contentType ||
    contentType === "application/octet-stream" ||
    contentType === "binary/octet-stream";
  const detectedContentType = genericBinary
    ? String(input.detectedContentType ?? "")
    : "";
  const effectiveContentType = supportedCatalogImageContentType(contentType)
    ? contentType === "image/jpg"
      ? "image/jpeg"
      : contentType
    : supportedCatalogImageContentType(detectedContentType)
      ? detectedContentType
      : "";
  if (
    input.finalUrlIsHttps &&
    input.status >= 200 &&
    input.status < 300 &&
    effectiveContentType
  ) {
    return {
      state: "valid",
      code: "IMAGE_OK",
      contentType: effectiveContentType,
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
    let detectedContentType = "";
    if (response.body) {
      if (method === "GET") {
        const reader = response.body.getReader();
        try {
          const first = await reader.read();
          detectedContentType = detectedCatalogImageContentType(
            first.value ?? new Uint8Array(),
          );
        } finally {
          await reader.cancel().catch(() => undefined);
        }
      } else {
        await response.body.cancel().catch(() => undefined);
      }
    }
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
      detectedContentType,
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
