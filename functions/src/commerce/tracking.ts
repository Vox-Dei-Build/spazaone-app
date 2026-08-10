/** Validates and preserves an optional customer-facing tracking URL. */
export function validatedTrackingUrl(
  value: unknown,
  maxLength = 500,
): string | null {
  const text = String(value ?? "").trim();
  if (!text) return null;
  if (text.length > maxLength) throw new Error("TRACKING_URL_INVALID");

  let url: URL;
  try {
    url = new URL(text);
  } catch (_) {
    throw new Error("TRACKING_URL_INVALID");
  }
  if (
    !["http:", "https:"].includes(url.protocol) ||
    !url.hostname ||
    url.username ||
    url.password
  ) {
    throw new Error("TRACKING_URL_INVALID");
  }
  return text;
}
