import { functions } from "../config/main";

export function commerceCheckoutUrl(listingId: string): string {
  const configured = String(
    process.env.COMMERCE_CHECKOUT_BASE_URL ??
      functions.config().commerce?.checkout_url ??
      "",
  ).trim();
  const projectId = String(
    process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "",
  ).trim();
  const runningInEmulator = process.env.FUNCTIONS_EMULATOR === "true";
  const base =
    configured ||
    (runningInEmulator
      ? `http://127.0.0.1:5001/${projectId || "demo-spazaone"}/us-central1/commerceCheckout`
      : projectId
        ? `https://us-central1-${projectId}.cloudfunctions.net/commerceCheckout`
        : "http://127.0.0.1:5001/demo-spazaone/us-central1/commerceCheckout");
  const url = new URL(base);
  url.searchParams.set("listing", listingId);
  return url.toString();
}
