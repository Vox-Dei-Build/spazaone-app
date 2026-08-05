import axios from "axios";
import { db, functions } from "../config/main";
import { isCjImageUrl } from "../commerce/cjImagePolicy";

const PLACEHOLDER_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZlVQAAAAASUVORK5CYII=",
  "base64",
);
const ALLOWED_IMAGE_HOSTS = new Set([
  "firebasestorage.googleapis.com",
  "storage.googleapis.com",
]);
const ALLOWED_IMAGE_TYPES = new Set(["image/jpeg", "image/jpg", "image/png"]);

export type ProductPromotionImageSource =
  | "firebase_storage"
  | "verified_supplier"
  | "rejected";

type SellerProductImagePolicyData = {
  isDropshipListing?: unknown;
  commerceListingId?: unknown;
};

type CommerceListingImagePolicyData = {
  sellerId?: unknown;
  sellerProductId?: unknown;
  images?: unknown;
};

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

/** Classifies an image URL without allowing lookalike or nested host names. */
export function productPromotionImageSource(
  rawUrl: unknown,
): ProductPromotionImageSource {
  if (typeof rawUrl !== "string" || !rawUrl.trim()) return "rejected";

  try {
    const url = new URL(rawUrl.trim());
    if (url.protocol !== "https:") return "rejected";
    if (ALLOWED_IMAGE_HOSTS.has(url.hostname)) return "firebase_storage";
    if (isCjImageUrl(url.toString())) return "verified_supplier";
  } catch (_) {
    return "rejected";
  }

  return "rejected";
}

/**
 * Authorizes an external supplier image against its server-owned projection.
 *
 * Seller product fields alone are not trusted: the commerce listing must bind
 * the same merchant and seller product, and must contain the exact selected
 * image URL.
 */
export function isAuthorizedSupplierPromotionImage({
  merchantId,
  productId,
  listingId,
  imageUrl,
  product,
  listing,
}: {
  merchantId: string;
  productId: string;
  listingId: string;
  imageUrl: string;
  product: SellerProductImagePolicyData;
  listing: CommerceListingImagePolicyData | undefined;
}): boolean {
  if (product.isDropshipListing !== true || !listing) return false;
  if (safeId(product.commerceListingId) !== listingId) return false;
  if (listing.sellerId !== merchantId) return false;
  if (listing.sellerProductId !== productId) return false;
  if (!Array.isArray(listing.images)) return false;

  return listing.images.some(
    (candidate) => typeof candidate === "string" && candidate === imageUrl,
  );
}

/**
 * Stable, public image URL used by the approved product-promotion card.
 *
 * WhatsApp requires the media template to keep a fixed host. The endpoint
 * resolves the selected merchant/product at send time. Existing Firebase
 * Storage images remain supported. A dropship supplier image is proxied only
 * after it is matched to the server-owned commerce listing for that exact
 * merchant, seller product and image URL. Missing or stale products degrade to
 * a valid placeholder so an image problem cannot crash an entire campaign.
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

      const imageUrl = rawUrl.trim();
      const imageSource = productPromotionImageSource(imageUrl);
      if (imageSource === "rejected") {
        console.warn("[PRODUCT PROMO IMAGE] rejected image URL");
        sendPlaceholder(res);
        return;
      }

      if (imageSource === "verified_supplier") {
        const commerceListingId = safeId(data?.commerceListingId);
        if (!commerceListingId) {
          sendPlaceholder(res);
          return;
        }
        const listingSnap = await db
          .collection("commerceListings")
          .doc(commerceListingId)
          .get();
        if (
          !isAuthorizedSupplierPromotionImage({
            merchantId,
            productId,
            listingId: listingSnap.id,
            imageUrl,
            product: data ?? {},
            listing: listingSnap.data(),
          })
        ) {
          console.warn(
            "[PRODUCT PROMO IMAGE] rejected unverified supplier image",
          );
          sendPlaceholder(res);
          return;
        }
      }

      const image = await axios.get<ArrayBuffer>(imageUrl, {
        responseType: "arraybuffer",
        timeout: 10000,
        maxContentLength: 5 * 1024 * 1024,
        // Do not let an approved supplier host redirect the proxy elsewhere.
        maxRedirects: imageSource === "verified_supplier" ? 0 : undefined,
      });
      const contentType = String(image.headers["content-type"] || "");
      if (!ALLOWED_IMAGE_TYPES.has(contentType.split(";")[0].toLowerCase())) {
        sendPlaceholder(res);
        return;
      }

      res.set("Content-Type", contentType);
      res.set("Cache-Control", "public, max-age=86400");
      res.status(200).send(Buffer.from(image.data));
    } catch (error: unknown) {
      console.warn(
        "[PRODUCT PROMO IMAGE] using placeholder",
        error instanceof Error ? error.message : String(error),
      );
      sendPlaceholder(res);
    }
  },
);
