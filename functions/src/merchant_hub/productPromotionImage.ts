import axios from "axios";
import { db, functions } from "../config/main";

const PLACEHOLDER_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZlVQAAAAASUVORK5CYII=",
  "base64",
);
const ALLOWED_IMAGE_HOSTS = new Set([
  "firebasestorage.googleapis.com",
  "storage.googleapis.com",
]);
const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/jpg", "image/png"]);

function sendPlaceholder(res: functions.Response): void {
  res.set("Content-Type", "image/png");
  res.set("Cache-Control", "public, max-age=300");
  res.status(200).send(PLACEHOLDER_PNG);
}

function safeId(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return /^[A-Za-z0-9_-]{1,160}$/.test(trimmed) ? trimmed : null;
}

/**
 * Stable, public image URL used by the approved product-promotion card.
 *
 * WhatsApp requires the media template to keep a fixed host. The endpoint
 * resolves the selected merchant/product at send time and proxies only images
 * from the project's Firebase Storage hosts. Missing or stale products degrade
 * to a valid placeholder so an image problem cannot crash an entire campaign.
 */
export const productPromotionImage = functions.https.onRequest(
  async (req, res) => {
    if (req.method !== "GET") {
      res.status(405).send("Method not allowed");
      return;
    }

    const pathParts = req.path.split("/").filter(Boolean);
    const pathMerchantId = pathParts.length === 2 ? pathParts[0] : undefined;
    const pathProductId =
      pathParts.length === 2 ? pathParts[1].replace(/\.png$/i, "") : undefined;
    const merchantId = safeId(pathMerchantId ?? req.query.merchantId);
    const productId = safeId(pathProductId ?? req.query.productId);
    if (!merchantId || !productId) {
      sendPlaceholder(res);
      return;
    }

    // Twilio resolves this URL while validating the template samples.
    if (merchantId === "sample" && productId === "sample") {
      sendPlaceholder(res);
      return;
    }

    try {
      const snap = await db
        .collection("users")
        .doc(merchantId)
        .collection("products")
        .doc(productId)
        .get();
      const data = snap.data();
      const rawUrl = data?.imageUrl ?? data?.image;
      if (typeof rawUrl !== "string" || !rawUrl.trim()) {
        sendPlaceholder(res);
        return;
      }

      const url = new URL(rawUrl);
      if (url.protocol !== "https:" || !ALLOWED_IMAGE_HOSTS.has(url.hostname)) {
        console.warn("[PRODUCT PROMO IMAGE] rejected image host", url.hostname);
        sendPlaceholder(res);
        return;
      }

      const image = await axios.get<ArrayBuffer>(url.toString(), {
        responseType: "arraybuffer",
        timeout: 10000,
        maxContentLength: 5 * 1024 * 1024,
      });
      const contentType = String(image.headers["content-type"] || "");
      if (!ALLOWED_IMAGE_TYPES.has(contentType.split(";")[0].toLowerCase())) {
        sendPlaceholder(res);
        return;
      }

      res.set("Content-Type", contentType);
      res.set("Cache-Control", "public, max-age=86400");
      res.status(200).send(Buffer.from(image.data));
    } catch (error: any) {
      console.warn(
        "[PRODUCT PROMO IMAGE] using placeholder",
        error?.message || error,
      );
      sendPlaceholder(res);
    }
  },
);
