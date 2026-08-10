import { randomBytes } from "node:crypto";
import axios from "axios";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { verifyBotRequest } from "../security/requestAuth";
import { CjLandedQuote, quoteCjVariant } from "./cjClient";
import { priceCommerceOrder, requireMinorUnits } from "./domain";
import { merchantManualPaymentOptions } from "./manualPaymentInstructions";

const PREPARATION_TTL_MS = 15 * 60 * 1000;

type PreparedAddress = {
  line1: string;
  line2: string;
  suburb: string;
  city: string;
  province: string;
  postalCode: string;
  country: "ZA";
  plusCode?: string;
  location?: { latitude: number; longitude: number };
  source?: "geocoded" | "manual_review";
  originalText?: string;
  landmark?: string;
};

export type CheckoutQuoteReservation = {
  supplierId: "cj_dropshipping";
  productId: string;
  variantId: string;
  variantSku: string;
  postalCode: string;
  productCostMinor: number;
  shippingCostMinor: number;
  landedCostMinor: number;
  productCostUsdMinor: number;
  shippingCostUsdMinor: number;
  originCountryCode: string;
  logisticName: string;
  logisticAging: string;
  verifiedAt: string;
  fx: {
    rateMicros: number;
    date: string;
    bufferBps: number;
  };
  reservedAtMs: number;
  expiresAtMs: number;
};

function text(value: unknown, max = 200): string {
  return String(value ?? "")
    .trim()
    .replace(/\s+/g, " ")
    .slice(0, max);
}

function safeId(value: unknown, field: string): string {
  const valueText = text(value, 200);
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(valueText)) {
    throw new Error(`${field}_INVALID`);
  }
  return valueText;
}

export function deliveryEstimateFromAging(value: unknown): {
  minDays: number;
  maxDays: number;
} {
  const days = String(value ?? "")
    .match(/\d+/g)
    ?.map(Number)
    .filter((day) => Number.isSafeInteger(day) && day > 0)
    .slice(0, 2);
  // A live quote should normally include aging. Keep the review contract
  // useful for a legacy/manual listing with a conservative, non-zero window.
  if (!days?.length) return { minDays: 10, maxDays: 20 };
  return {
    minDays: days[0],
    maxDays: Math.max(days[0], days[1] ?? days[0]),
  };
}

export function reserveCheckoutQuote(
  quote: CjLandedQuote,
  postalCode: string,
  expiresAtMs: number,
  nowMs = Date.now(),
): CheckoutQuoteReservation {
  if (
    !Number.isSafeInteger(expiresAtMs) ||
    expiresAtMs <= nowMs ||
    expiresAtMs - nowMs > PREPARATION_TTL_MS
  ) {
    throw new Error("CHECKOUT_QUOTE_EXPIRY_INVALID");
  }
  return {
    supplierId: "cj_dropshipping",
    productId: safeId(quote.product.productId, "PRODUCT"),
    variantId: safeId(quote.variant.variantId, "VARIANT"),
    variantSku: text(quote.variant.sku, 200),
    postalCode: text(postalCode, 12),
    productCostMinor: requireMinorUnits(quote.productCostMinor, "productCost"),
    shippingCostMinor: requireMinorUnits(
      quote.shippingCostMinor,
      "shippingCost",
    ),
    landedCostMinor: requireMinorUnits(quote.landedCostMinor, "landedCost"),
    productCostUsdMinor: requireMinorUnits(
      quote.productCostUsdMinor,
      "productCostUsd",
    ),
    shippingCostUsdMinor: requireMinorUnits(
      quote.shippingCostUsdMinor,
      "shippingCostUsd",
    ),
    originCountryCode: text(quote.originCountryCode, 8),
    logisticName: text(quote.logisticName, 160),
    logisticAging: text(quote.logisticAging, 80),
    verifiedAt: text(quote.verifiedAt, 80),
    fx: {
      rateMicros: requireMinorUnits(quote.fx.rateMicros, "fxRate"),
      date: text(quote.fx.date, 40),
      bufferBps: requireMinorUnits(quote.fx.bufferBps, "fxBuffer"),
    },
    reservedAtMs: nowMs,
    expiresAtMs,
  };
}

function geocodingKey(): string {
  return text(
    process.env.GEOCODING_API_KEY ??
      functions.config().maps?.geocoding_key ??
      "",
    500,
  );
}

function component(
  components: Array<{ long_name?: string; types?: string[] }>,
  ...types: string[]
): string {
  for (const wanted of types) {
    const match = components.find((item) => item.types?.includes(wanted));
    if (match?.long_name) return text(match.long_name, 160);
  }
  return "";
}

function canonicalProvince(value: string): string {
  const key = value.toLowerCase().replace(/[^a-z]/g, "");
  return (
    new Map<string, string>([
      ["easterncape", "Eastern Cape"],
      ["ec", "Eastern Cape"],
      ["freestate", "Free State"],
      ["fs", "Free State"],
      ["gauteng", "Gauteng"],
      ["gp", "Gauteng"],
      ["kwazulunatal", "KwaZulu-Natal"],
      ["kzn", "KwaZulu-Natal"],
      ["limpopo", "Limpopo"],
      ["lp", "Limpopo"],
      ["mpumalanga", "Mpumalanga"],
      ["mp", "Mpumalanga"],
      ["northerncape", "Northern Cape"],
      ["nc", "Northern Cape"],
      ["northwest", "North West"],
      ["nw", "North West"],
      ["westerncape", "Western Cape"],
      ["wc", "Western Cape"],
    ]).get(key) ?? ""
  );
}

const PROVINCE_PATTERNS: Array<[RegExp, string]> = [
  [/\beastern\s+cape\b/i, "Eastern Cape"],
  [/\bfree\s+state\b/i, "Free State"],
  [/\bgauteng\b/i, "Gauteng"],
  [/\bkwa[\s-]*zulu[\s-]*natal\b/i, "KwaZulu-Natal"],
  [/\blimpopo\b/i, "Limpopo"],
  [/\bmpumalanga\b/i, "Mpumalanga"],
  [/\bnorthern\s+cape\b/i, "Northern Cape"],
  [/\bnorth\s+west\b/i, "North West"],
  [/\bwestern\s+cape\b/i, "Western Cape"],
  [/\b(?:ec|fs|gp|kzn|lp|mp|nc|nw|wc)\b/i, ""],
];

function provinceFromText(value: string): string {
  for (const [pattern, province] of PROVINCE_PATTERNS) {
    const match = value.match(pattern);
    if (!match) continue;
    return province || canonicalProvince(match[0]);
  }
  return "";
}

function plusCodeFromText(value: string): string {
  return text(
    value.match(
      /\b[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3}\b/i,
    )?.[0],
    32,
  ).toUpperCase();
}

function nearestTownFromClarification(
  clarification: string,
  province: string,
  postalCode: string,
): string {
  const plausibleTown = (value: string): string => {
    const candidate = text(value, 100)
      .replace(/^the\s+/i, "")
      .trim();
    if (
      !/[A-Za-z]{2}/.test(candidate) ||
      /^(?:clinic|school|church|shop|store|spaza|garage|bridge|river|road|street|stand|house|landmark)\b/i.test(
        candidate,
      )
    ) {
      return "";
    }
    return candidate;
  };
  const explicit = clarification.match(
    /\b(?:nearest\s+town|town)\s*[:=-]\s*([A-Za-z][A-Za-z .'-]{1,80})(?=\s*[,;|]|\s+\d{4}\b|$)/i,
  )?.[1];
  if (explicit) return plausibleTown(explicit);
  const near = clarification.match(
    /\bnear\s+([A-Za-z][A-Za-z .'-]{1,80})(?=\s*[,;|]|\s+\d{4}\b|$)/i,
  )?.[1];
  if (near) {
    const candidate = plausibleTown(near);
    if (candidate) return candidate;
  }

  const parts = clarification
    .split(/[,;|\n]/)
    .map((part) => text(part, 100))
    .filter(Boolean);
  const provinceIndex = parts.findIndex(
    (part) => provinceFromText(part) === province,
  );
  if (provinceIndex > 0) {
    const candidate = parts[provinceIndex - 1]
      .replace(/\b(?:nearest\s+town|town)\s*[:=-]?\s*/i, "")
      .replace(/\bnear\s+/i, "");
    const town = plausibleTown(candidate);
    if (town) return town;
  }

  let withoutLocationCodes = clarification;
  for (const [pattern] of PROVINCE_PATTERNS) {
    withoutLocationCodes = withoutLocationCodes.replace(
      new RegExp(pattern.source, "gi"),
      " ",
    );
  }
  withoutLocationCodes = withoutLocationCodes
    .replace(postalCode, " ")
    .replace(/\b(?:ec|fs|gp|kzn|lp|mp|nc|nw|wc)\b/gi, " ")
    .replace(
      /\b[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3}\b/gi,
      " ",
    )
    .replace(/\b(?:nearest\s+town|town|near)\s*[:=-]?\s*/gi, " ");
  const candidate = text(withoutLocationCodes, 100).replace(
    /^[,;| -]+|[,;| -]+$/g,
    "",
  );
  return plausibleTown(candidate);
}

function manualDeliveryFallback(
  delivery: Record<string, unknown>,
  clarification: string,
): {
  address: PreparedAddress;
  deliveryLabel: string;
  plusCode?: string;
} | null {
  if (!clarification) return null;
  const originalText = text(delivery.text, 500);
  const combined = [originalText, clarification].filter(Boolean).join(", ");
  const province = provinceFromText(combined);
  const postalCode = combined.match(/\b\d{4}\b/)?.[0] ?? "";
  const nearestTown = nearestTownFromClarification(
    clarification,
    province,
    postalCode,
  );
  if (!province || !postalCode || !nearestTown) return null;

  const latitude = Number(delivery.latitude);
  const longitude = Number(delivery.longitude);
  const location =
    Number.isFinite(latitude) &&
    Number.isFinite(longitude) &&
    latitude >= -35 &&
    latitude <= -22 &&
    longitude >= 16 &&
    longitude <= 33
      ? { latitude, longitude }
      : undefined;
  const plusCode =
    text(delivery.plusCode, 32).toUpperCase() || plusCodeFromText(combined);
  if (!originalText && !location && !plusCode) return null;
  const line1 = originalText || plusCode || "Shared location pin";
  const deliveryLabel = [line1, clarification].filter(Boolean).join(" · ");
  return {
    address: {
      line1,
      line2: clarification,
      suburb: nearestTown,
      city: nearestTown,
      province,
      postalCode,
      country: "ZA",
      source: "manual_review",
      ...(originalText ? { originalText } : {}),
      landmark: clarification,
      ...(plusCode ? { plusCode } : {}),
      ...(location ? { location } : {}),
    },
    deliveryLabel,
    ...(plusCode ? { plusCode } : {}),
  };
}

async function resolveDelivery(input: Record<string, unknown>): Promise<{
  address?: PreparedAddress;
  deliveryLabel?: string;
  plusCode?: string;
  clarification?: "landmark" | "postal_code" | "address";
  clarificationExhausted?: boolean;
}> {
  const delivery =
    input.delivery && typeof input.delivery === "object"
      ? (input.delivery as Record<string, unknown>)
      : {};
  const kind = text(delivery.kind, 20);
  const clarification = text(input.clarificationAnswer, 200);
  const fallback = () => manualDeliveryFallback(delivery, clarification);
  let location: { latitude: number; longitude: number } | undefined;
  let originalText = "";
  if (kind === "location") {
    const latitude = Number(delivery.latitude);
    const longitude = Number(delivery.longitude);
    if (
      !Number.isFinite(latitude) ||
      !Number.isFinite(longitude) ||
      latitude < -35 ||
      latitude > -22 ||
      longitude < 16 ||
      longitude > 33
    ) {
      return {
        clarification: "address",
        clarificationExhausted: Boolean(clarification),
      };
    }
    location = { latitude, longitude };
  } else if (kind === "text") {
    originalText = text(delivery.text, 500);
    if (!originalText) {
      return {
        clarification: "address",
        clarificationExhausted: Boolean(clarification),
      };
    }
  } else {
    return {
      clarification: "address",
      clarificationExhausted: Boolean(clarification),
    };
  }

  const key = geocodingKey();
  if (!key) {
    const manual = fallback();
    return (
      manual ?? {
        clarification: "address",
        clarificationExhausted: Boolean(clarification),
      }
    );
  }
  const params: Record<string, string> = { key, region: "za" };
  if (location) {
    params.latlng = `${location.latitude},${location.longitude}`;
  } else {
    params.address = `${originalText}, South Africa`;
  }

  let response;
  try {
    response = await axios.get(
      "https://maps.googleapis.com/maps/api/geocode/json",
      { params, timeout: 8000 },
    );
  } catch {
    const manual = fallback();
    return (
      manual ?? {
        clarification: "address",
        clarificationExhausted: Boolean(clarification),
      }
    );
  }
  const result = response.data?.results?.[0];
  if (!result) {
    const manual = fallback();
    return (
      manual ?? {
        clarification: "address",
        clarificationExhausted: Boolean(clarification),
      }
    );
  }
  const components = Array.isArray(result.address_components)
    ? result.address_components
    : [];
  const province = canonicalProvince(
    component(components, "administrative_area_level_1"),
  );
  const postalFromAnswer = clarification.match(/\b\d{4}\b/)?.[0] ?? "";
  const postalCode = component(components, "postal_code") || postalFromAnswer;
  const street = [
    component(components, "street_number"),
    component(components, "route", "premise"),
  ]
    .filter(Boolean)
    .join(" ");
  const plusCode = text(
    response.data?.plus_code?.global_code ?? result.plus_code?.global_code,
    32,
  );
  const locality = component(
    components,
    "sublocality_level_1",
    "sublocality",
    "locality",
  );
  const city = component(components, "locality", "administrative_area_level_2");
  if (!province) {
    const manual = fallback();
    return (
      manual ?? {
        clarification: "address",
        clarificationExhausted: Boolean(clarification),
      }
    );
  }
  if (!postalCode) {
    const manual = fallback();
    return (
      manual ?? {
        clarification: "postal_code",
        clarificationExhausted: Boolean(clarification),
      }
    );
  }
  if (!street && !plusCode && !clarification) {
    return { clarification: "landmark" };
  }
  // Rural reverse-geocodes can omit locality/admin-level-2 even when the
  // province and postal code are valid. Keep the server-prepared structure
  // compatible with final validation; the full formatted label remains the
  // customer-facing description.
  const resolvedSuburb = locality || city || province;
  const resolvedCity = city || locality || province;
  const deliveryLabel = text(result.formatted_address, 300);
  return {
    address: {
      line1: street || plusCode || clarification,
      line2: clarification && clarification !== postalCode ? clarification : "",
      suburb: resolvedSuburb,
      city: resolvedCity,
      province,
      postalCode,
      country: "ZA",
      source: "geocoded",
      ...(originalText ? { originalText } : {}),
      ...(clarification ? { landmark: clarification } : {}),
      ...(plusCode ? { plusCode } : {}),
      ...(location ? { location } : {}),
    },
    deliveryLabel,
    ...(plusCode ? { plusCode } : {}),
  };
}

async function quoteListing(listing: FirebaseFirestore.DocumentData): Promise<{
  amountDueMinor: number;
  quote: CjLandedQuote | null;
  deliveryEstimate: { minDays: number; maxDays: number };
}> {
  let quote: CjLandedQuote | null = null;
  if (String(listing.supplierId ?? "") === "cj_dropshipping") {
    quote = await quoteCjVariant({
      productId: safeId(listing.supplierProductId, "PRODUCT"),
      variantId: safeId(listing.supplierVariantId, "VARIANT"),
      postalCode: text(listing.preparedPostalCode, 12),
    });
  }
  const baseCostMinor = quote
    ? quote.landedCostMinor
    : requireMinorUnits(listing.baseCostMinor, "baseCost");
  const sellPriceMinor = quote
    ? quote.landedCostMinor + requireMinorUnits(listing.markupMinor, "markup")
    : requireMinorUnits(listing.sellPriceMinor, "sellPrice");
  const priced = priceCommerceOrder({
    baseCostMinor,
    sellPriceMinor,
    quantity: 1,
    paymentFeeMinor: 0,
  });
  return {
    amountDueMinor: priced.amountDueMinor,
    quote,
    deliveryEstimate: deliveryEstimateFromAging(
      quote?.logisticAging ?? listing.logisticAging,
    ),
  };
}

/** Bot-authenticated delivery resolution and exact review-price preparation. */
export const prepareCommerceCheckout = functions
  .runWith({
    secrets: ["CJ_API_KEY", "PASELLA_BOT_TOKEN", "GEOCODING_API_KEY"],
    timeoutSeconds: 120,
    memory: "512MB",
  })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ status: "unavailable", reason: "method" });
      return;
    }
    if (!verifyBotRequest(req)) {
      res.status(401).json({ status: "unavailable", reason: "auth" });
      return;
    }
    try {
      const input = (req.body ?? {}) as Record<string, unknown>;
      const merchantId = safeId(input.merchantId, "MERCHANT");
      const customerId = safeId(input.customerId, "CUSTOMER");
      const listingId = safeId(input.listingId, "LISTING");
      const [customer, listing, payment] = await Promise.all([
        db.doc(`users/${merchantId}/customers/${customerId}`).get(),
        db.doc(`commerceListings/${listingId}`).get(),
        merchantManualPaymentOptions(merchantId),
      ]);
      if (
        !customer.exists ||
        !listing.exists ||
        listing.data()?.active !== true ||
        String(listing.data()?.sellerId ?? "") !== merchantId
      ) {
        res
          .status(200)
          .json({ status: "unavailable", reason: "product_unavailable" });
        return;
      }
      if (payment.paymentOptions.length === 0) {
        res.status(200).json({
          status: "unavailable",
          reason: "payment_setup_required",
        });
        return;
      }
      const resolved = await resolveDelivery(input);
      if (!resolved.address) {
        if (resolved.clarificationExhausted) {
          res.status(200).json({
            status: "unavailable",
            reason: "address_details_invalid",
          });
          return;
        }
        const field = resolved.clarification ?? "address";
        const prompt =
          field === "postal_code"
            ? "What is the four-digit postal code?"
            : field === "landmark"
              ? "Send one nearby landmark or stand description."
              : "Reply with the nearest town, province and four-digit postal code in one message.";
        res.status(200).json({
          status: "needs_clarification",
          prompt,
          field,
        });
        return;
      }
      const source = {
        ...(listing.data() ?? {}),
        preparedPostalCode: resolved.address.postalCode,
      };
      const quoted = await quoteListing(source);
      const preparationRef = db
        .collection("commerceCheckoutPreparations")
        .doc(randomBytes(18).toString("hex"));
      const expiresAtMs = Date.now() + PREPARATION_TTL_MS;
      const quoteReservation = quoted.quote
        ? reserveCheckoutQuote(
            quoted.quote,
            resolved.address.postalCode,
            expiresAtMs,
          )
        : null;
      await preparationRef.create({
        merchantId,
        customerId,
        listingId,
        deliveryAddress: resolved.address,
        deliveryLabel: resolved.deliveryLabel ?? "",
        plusCode: resolved.plusCode ?? null,
        amountDueMinor: quoted.amountDueMinor,
        deliveryEstimate: quoted.deliveryEstimate,
        paymentOptions: payment.paymentOptions,
        quoteVerifiedAt: quoted.quote?.verifiedAt ?? null,
        quoteReservation,
        status: "ready",
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromMillis(expiresAtMs),
      });
      res.status(200).json({
        status: "ready",
        preparationId: preparationRef.id,
        expiresAt: new Date(expiresAtMs).toISOString(),
        deliveryAddress: resolved.address,
        deliveryLabel: resolved.deliveryLabel ?? "",
        ...(resolved.plusCode ? { plusCode: resolved.plusCode } : {}),
        amountDueMinor: quoted.amountDueMinor,
        deliveryEstimate: quoted.deliveryEstimate,
        paymentOptions: payment.paymentOptions,
      });
    } catch (error) {
      console.error("prepareCommerceCheckout failed", {
        message: error instanceof Error ? error.message.slice(0, 160) : "error",
      });
      res.status(200).json({
        status: "unavailable",
        reason: "delivery_check_failed",
      });
    }
  });
