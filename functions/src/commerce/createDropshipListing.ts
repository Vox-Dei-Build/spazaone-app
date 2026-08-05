import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { assertCallableStoreAccess } from "../stores/storeAccess";
import { commerceCheckoutUrl } from "./checkoutUrl";
import { priceCommerceOrder, requireMinorUnits } from "./domain";
import { quoteCjVariant } from "./cjClient";
import { publicCjError } from "./cjCatalog";
import { commercePaymentsEnabled } from "./readiness";

function cleanText(value: unknown, field: string, max: number): string {
  const text = String(value ?? "").trim();
  if (!text || text.length > max) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `${field} is required and must be at most ${max} characters.`,
    );
  }
  return text;
}

/** Creates a seller product plus the immutable server-priced projection. */
export const createDropshipListing = functions
  .runWith({ secrets: ["CJ_API_KEY"] })
  .https.onCall(async (data, context) => {
    const storeId = cleanText(data?.storeId, "storeId", 128);
    const supplierProductId = cleanText(
      data?.supplierProductId,
      "supplierProductId",
      200,
    );
    const supplierVariantId = cleanText(
      data?.supplierVariantId,
      "supplierVariantId",
      200,
    );
    await assertCallableStoreAccess(context, storeId);

    let markupMinor: number;
    try {
      markupMinor = requireMinorUnits(data?.markupMinor, "markup");
    } catch (_) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Enter a valid markup.",
      );
    }
    if (markupMinor <= 0 || markupMinor > 10_000_000) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Markup must be greater than zero and within the listing limit.",
      );
    }

    let quote;
    try {
      quote = await quoteCjVariant({
        productId: supplierProductId,
        variantId: supplierVariantId,
      });
    } catch (error) {
      console.error("createDropshipListing CJ quote failed", error);
      throw publicCjError(error);
    }

    const baseCostMinor = quote.landedCostMinor;
    const sellPriceMinor = baseCostMinor + markupMinor;
    try {
      priceCommerceOrder({
        baseCostMinor,
        sellPriceMinor,
        paymentFeeMinor: commercePaymentsEnabled() ? undefined : 0,
      });
    } catch (_) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Increase the markup so it covers the estimated payment fee.",
      );
    }
    const variantLabel = quote.variant.option || quote.variant.name;
    const title = `${quote.product.title}${
      variantLabel ? ` · ${variantLabel}` : ""
    }`.slice(0, 160);
    const images = [quote.variant.image, ...quote.product.images]
      .filter(Boolean)
      .filter((image, index, all) => all.indexOf(image) === index)
      .slice(0, 8);
    const description = quote.product.description;
    const shippingNotes = [
      quote.logisticAging
        ? `Estimated ${quote.logisticAging} days via ${quote.logisticName}.`
        : `Delivery via ${quote.logisticName}.`,
      "Final delivery cost is verified from the buyer's address at checkout.",
    ].join(" ");
    const sellerProductRef = db
      .collection("users")
      .doc(storeId)
      .collection("products")
      .doc();
    const listingRef = db.collection("commerceListings").doc();
    const checkoutUrl = commerceCheckoutUrl(listingRef.id);
    const now = FieldValue.serverTimestamp();

    await db.runTransaction(async (tx) => {
      tx.create(sellerProductRef, {
        name: title,
        description,
        image: images[0] ?? null,
        images,
        cost: baseCostMinor / 100,
        sellingPrice: sellPriceMinor / 100,
        company: "Spaza One supplier",
        group: quote.product.category || "Dropship",
        whatsappListed: true,
        supplierId: "cj_dropshipping",
        sourceProductId: supplierProductId,
        sourceVariantId: supplierVariantId,
        supplierSku: quote.variant.sku,
        baseCost: baseCostMinor / 100,
        baseCostMinor,
        supplierProductCostMinor: quote.productCostMinor,
        supplierShippingCostMinor: quote.shippingCostMinor,
        markupMinor,
        sellPriceMinor,
        fulfilmentMode: "seller_manual_cj_order",
        shippingNotes,
        isDropshipListing: true,
        commerceListingId: listingRef.id,
        checkoutUrl,
        createdAt: now,
        updatedAt: now,
        schemaVersion: 1,
      });
      tx.create(listingRef, {
        sellerId: storeId,
        sellerProductId: sellerProductRef.id,
        supplierId: "cj_dropshipping",
        supplierProductId,
        supplierVariantId,
        supplierSku: quote.variant.sku,
        title,
        description,
        images,
        baseCostMinor,
        supplierProductCostMinor: quote.productCostMinor,
        supplierShippingCostMinor: quote.shippingCostMinor,
        supplierProductCostUsdMinor: quote.productCostUsdMinor,
        supplierShippingCostUsdMinor: quote.shippingCostUsdMinor,
        markupMinor,
        sellPriceMinor,
        currency: "ZAR",
        supplierCurrency: "USD",
        fxRateMicros: quote.fx.rateMicros,
        fxRateDate: quote.fx.date,
        fxBufferBps: quote.fx.bufferBps,
        sourceCountryCode: quote.originCountryCode,
        logisticName: quote.logisticName,
        logisticAging: quote.logisticAging,
        availability: "available",
        fulfilmentMode: "seller_manual_cj_order",
        shippingNotes,
        active: true,
        checkoutUrl,
        createdBy: context.auth?.uid ?? null,
        createdAt: now,
        updatedAt: now,
        supplierPricingVerifiedAt: quote.verifiedAt,
        schemaVersion: 2,
      });
    });

    return {
      listingId: listingRef.id,
      sellerProductId: sellerProductRef.id,
      checkoutUrl,
      digitalPaymentsEnabled: commercePaymentsEnabled(),
    };
  });
