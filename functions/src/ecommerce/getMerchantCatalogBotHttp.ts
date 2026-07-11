/**
 * Narrow catalog endpoint for Botpress.
 *
 * `getProducts` returns full product documents. The conversational bot only
 * needs fields required for matching and cart writes, so this endpoint keeps
 * the transport contract small and avoids leaking unrelated stock metadata.
 */
import { db, functions } from "../config/main";
import { requireBotRequest } from "../security/requestAuth";

type CatalogProduct = {
  id: string;
  name: string;
  aliases?: string[];
  unit?: string;
  price?: number;
  imageUrl?: string;
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

function isWhatsAppListed(data: Record<string, unknown>): boolean {
  return (
    data.whatsappListed === true ||
    data.whatsappEnabled === true ||
    data.availableOnWhatsApp === true
  );
}

export const getMerchantCatalogBotHttp = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
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
      const snap = await db
        .collection("users")
        .doc(merchantId)
        .collection("products")
        .get();

      const catalog: CatalogProduct[] = snap.docs
        .map((doc) => {
          const data = doc.data() || {};
          if (!isWhatsAppListed(data)) return null;
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
          if (aliases) product.aliases = aliases;
          if (unit) product.unit = unit;
          if (price !== undefined) product.price = price;
          if (imageUrl) product.imageUrl = imageUrl;
          return product;
        })
        .filter((product): product is CatalogProduct => Boolean(product));

      res.status(200).json(catalog);
    } catch (error: any) {
      console.error("Error fetching bot catalog:", error?.message || error);
      res.status(500).json({ error: "failed_to_fetch_catalog" });
    }
  });
