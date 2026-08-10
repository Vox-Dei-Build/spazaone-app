import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { assertCallableStoreAccess } from "../stores/storeAccess";
import { commerceCheckoutUrl } from "./checkoutUrl";
import {
  catalogProductRef,
  enqueueProductRefresh,
} from "./cjCatalogRepository";
import {
  catalogListingState,
  catalogQuoteVersion,
  CatalogListingState,
} from "./cjCatalogCache";
import { priceCommerceOrder, requireMinorUnits } from "./domain";
import { commercePaymentsEnabled } from "./readiness";
import { deliveryEstimateFromAging } from "./prepareCommerceCheckout";

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

function optionalText(value: unknown, field: string, max: number): string {
  const text = String(value ?? "").trim();
  if (text.length > max) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `${field} must be at most ${max} characters.`,
    );
  }
  return text;
}

function throwCatalogState(
  state: Exclude<CatalogListingState, { status: "ready" }>,
): never {
  if (state.status === "quote_changed") {
    throw new functions.https.HttpsError(
      "aborted",
      "Price or delivery changed. Review the updated costs, then add the product again.",
      {
        reason: "CATALOG_QUOTE_CHANGED",
        product: state.product,
      },
    );
  }
  if (state.status === "refreshing") {
    throw new functions.https.HttpsError(
      "unavailable",
      "Updating price and delivery. Try again shortly.",
      { reason: "CATALOG_REFRESHING", retryAfterSeconds: 15 },
    );
  }
  throw new functions.https.HttpsError(
    "failed-precondition",
    "This product is no longer available.",
    { reason: "CATALOG_UNAVAILABLE" },
  );
}

/** Creates a seller product plus the immutable server-priced projection. */
export const createDropshipListing = functions
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
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
    const selectedQuoteVersion = optionalText(
      data?.catalogQuoteVersion,
      "catalogQuoteVersion",
      80,
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

    const catalogRef = catalogProductRef(supplierProductId);
    const catalogSnapshot = await catalogRef.get();
    const rawCatalog = catalogSnapshot.data();
    const listingState = catalogListingState(
      rawCatalog,
      supplierVariantId,
      selectedQuoteVersion,
    );
    if (listingState.status !== "ready") {
      if (listingState.status === "refreshing" && rawCatalog) {
        await enqueueProductRefresh({
          product: rawCatalog,
          query: "listing",
          priority: 50,
        });
      }
      throwCatalogState(listingState);
    }
    const cached = listingState.document;
    const acceptedQuoteVersion = catalogQuoteVersion(cached);
    const quote = cached.recommendedQuote;
    const product = cached.details;

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
    const title = `${product.title}${
      variantLabel ? ` · ${variantLabel}` : ""
    }`.slice(0, 160);
    const images = [quote.variant.image, ...product.images]
      .filter(Boolean)
      .filter((image, index, all) => all.indexOf(image) === index)
      .slice(0, 8);
    const description = product.description;
    const shippingNotes = [
      quote.logisticAging
        ? `Estimated delivery: ${quote.logisticAging} days.`
        : "Delivery estimate is confirmed before the order is placed.",
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
      // Bind every created listing to the exact card the merchant reviewed.
      // This closes the gap between the initial read and the writes below.
      const currentSnapshot = await tx.get(catalogRef);
      const currentState = catalogListingState(
        currentSnapshot.data(),
        supplierVariantId,
        acceptedQuoteVersion,
      );
      if (currentState.status !== "ready") throwCatalogState(currentState);
      tx.create(sellerProductRef, {
        name: title,
        description,
        image: images[0] ?? null,
        images,
        cost: baseCostMinor / 100,
        sellingPrice: sellPriceMinor / 100,
        company: "Spaza One delivery",
        group: product.category || "Dropship",
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
        deliveryEstimate: deliveryEstimateFromAging(quote.logisticAging),
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
        deliveryEstimate: deliveryEstimateFromAging(quote.logisticAging),
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
