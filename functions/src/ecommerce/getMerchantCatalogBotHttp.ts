/**
 * Narrow catalog endpoint for Botpress.
 *
 * `getProducts` returns full product documents. The conversational bot only
 * needs fields required for matching and cart writes, so this endpoint keeps
 * the transport contract small and avoids leaking unrelated stock metadata.
 */
import { db, functions } from "../config/main";
import { requireBotRequest } from "../security/requestAuth";
import { merchantBotCatalogVisibilityFilter } from "./botCatalogVisibility";
import { merchantBotFeatureDecision } from "./merchantBotFeatureAccess";

type CatalogProduct = {
  id: string;
  name: string;
  aliases?: string[];
  unit?: string;
  price?: number;
  description?: string;
  popularityScore?: number;
  imageUrl?: string;
  isDropshipListing?: boolean;
  commerceListingId?: string;
  fulfilmentMode?: string;
  deliveryEstimate?: { minDays: number; maxDays: number };
};

function cleanString(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function cleanAliases(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const aliases = value
    .map(cleanString)
    .filter((alias): alias is string => Boolean(alias));
  return aliases.length ? aliases : undefined;
}

function cleanPrice(value: unknown): number | undefined {
  const price = Number(value);
  return Number.isFinite(price) && price >= 0 ? price : undefined;
}

export const getMerchantCatalogBotHttp = functions
  .runWith({
    secrets: ["PASELLA_BOT_TOKEN", "WHATSAPP_CATALOG_RECIPIENT_HASH_KEY"],
  })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    if (req.method !== "POST") {
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }

    const { merchantId } = (req.body || {}) as { merchantId?: string };
    if (!merchantId) {
      res.status(400).json({ error: "merchantId is required" });
      return;
    }

    try {
      const productVisible = merchantBotCatalogVisibilityFilter();
      const [snap, supplierAccess] = await Promise.all([
        db.collection("users").doc(merchantId).collection("products").get(),
        merchantBotFeatureDecision(merchantId, "supplierOrders"),
      ]);

      const catalog: CatalogProduct[] = snap.docs
        .map((doc) => {
          const data = doc.data() || {};
          if (!productVisible(data)) return null;
          const name =
            cleanString(data.name) ||
            cleanString(data.productName) ||
            cleanString(data.title);
          if (!name) return null;

          const product: CatalogProduct = {
            id: doc.id,
            name,
          };
          const aliases = cleanAliases(data.aliases);
          const unit = cleanString(data.unit);
          const price = cleanPrice(
            data.sellingPrice ?? data.price ?? data.productPrice,
          );
          const imageUrl = cleanString(data.imageUrl ?? data.image);
          const description = cleanString(data.description);
          const popularityScore = cleanPrice(data.whatsappPopularityScore);
          if (aliases) product.aliases = aliases;
          if (unit) product.unit = unit;
          if (price !== undefined) product.price = price;
          if (description) product.description = description;
          if (popularityScore !== undefined && popularityScore > 0) {
            product.popularityScore = popularityScore;
          }
          if (imageUrl) product.imageUrl = imageUrl;
          if (data.isDropshipListing === true) {
            if (!supplierAccess.enabled) return null;
            const commerceListingId = cleanString(data.commerceListingId);
            if (!commerceListingId) return null;
            product.isDropshipListing = true;
            product.commerceListingId = commerceListingId;
            product.fulfilmentMode =
              cleanString(data.fulfilmentMode) ?? "seller_manual_cj_order";
            const deliveryEstimate = data.deliveryEstimate;
            if (
              deliveryEstimate &&
              typeof deliveryEstimate === "object" &&
              Number.isSafeInteger(Number(deliveryEstimate.minDays)) &&
              Number.isSafeInteger(Number(deliveryEstimate.maxDays))
            ) {
              product.deliveryEstimate = {
                minDays: Number(deliveryEstimate.minDays),
                maxDays: Number(deliveryEstimate.maxDays),
              };
            }
          }
          return product;
        })
        .filter((product): product is CatalogProduct => Boolean(product));

      res.status(200).json(catalog);
    } catch (error: unknown) {
      console.error(
        "Error fetching bot catalog:",
        error instanceof Error ? error.message : error,
      );
      res.status(500).json({ error: "failed_to_fetch_catalog" });
    }
  });
