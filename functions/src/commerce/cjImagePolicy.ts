/**
 * Exact supplier-owned image hosts returned by CJ's Product API.
 *
 * Keep this policy shared by catalogue ingestion and the promotion proxy so a
 * product can never be accepted into the catalogue with an image that the
 * WhatsApp card later refuses to serve.
 */
const CJ_IMAGE_HOSTS = new Set([
  "oss-cf.cjdropshipping.com",
  "cf.cjdropshipping.com",
  "cdn.cjdropshipping.com",
  "cc-west-usa.oss-us-west-1.aliyuncs.com",
]);

export function safeCjImageUrl(value: unknown): string {
  if (typeof value !== "string") return "";
  const raw = value.trim();
  if (!raw || raw.length > 1000) return "";

  try {
    const parsed = new URL(raw);
    if (parsed.protocol !== "https:" || !CJ_IMAGE_HOSTS.has(parsed.hostname)) {
      return "";
    }
    return parsed.toString();
  } catch (_) {
    return "";
  }
}

export function isCjImageUrl(value: unknown): boolean {
  return safeCjImageUrl(value) !== "";
}
