import { functions } from "../config/main";
import { configuredPasellaWhatsappNumber } from "../ecommerce/getMerchantOrderingLink";

function safeOrderingCode(path: string): string | null {
  const parts = path.split("/").filter(Boolean);
  if (parts.length !== 1) return null;
  const code = parts[0].trim().toUpperCase();
  return /^[A-Z0-9]{3,20}$/.test(code) ? code : null;
}

/**
 * Public, stable URL used by the approved card button. WhatsApp requires a
 * dynamic URL variable to be the final path segment. This endpoint translates
 * that compliant URL into Pasella's existing prefilled wa.me ordering link.
 */
export const productPromotionOrder = functions.https.onRequest((req, res) => {
  if (req.method !== "GET") {
    res.status(405).send("Method not allowed");
    return;
  }

  const code = safeOrderingCode(req.path);
  const digits = configuredPasellaWhatsappNumber().replace(/\D/g, "");
  if (!code || !digits) {
    res.status(404).send("Ordering link not found");
    return;
  }

  const text = encodeURIComponent(`shop ${code}`);
  res.set("Cache-Control", "no-store");
  res.redirect(302, `https://wa.me/${digits}?text=${text}`);
});
