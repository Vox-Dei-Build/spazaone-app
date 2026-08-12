import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { randomBytes, createHash } from "crypto";
import axios from "axios";
import * as dotenv from "dotenv";
import * as path from "path";
import { db, functions } from "../config/main";
import { commerceCheckoutUrl } from "./checkoutUrl";
import { notifyCommerceOrder } from "./notifications";
import { priceCommerceOrder, requireMinorUnits } from "./domain";
import { quoteCjVariant } from "./cjClient";
import { verifyPaystackSignature } from "../payments/paystack/paystackSecurity";
import { formatPhoneNumber, normalizePhoneNumber } from "../utils/phoneUtils";
import { commercePaymentsEnabled } from "./readiness";
import { verifyBotRequest } from "../security/requestAuth";
import {
  ManualPaymentOption,
  merchantManualPaymentOptions,
} from "./manualPaymentInstructions";
import {
  deliverOrderCreatedOutbox,
  orderCreatedOutboxRef,
} from "./orderCreatedNotificationOutbox";
import {
  CheckoutQuoteReservation,
  deliveryEstimateFromAging,
  reserveCheckoutQuote,
} from "./prepareCommerceCheckout";
import {
  initializeSupplierOrderPaymentV2,
  supplierPaymentEconomics,
} from "../payments/v2/supplierOrders";
import { paymentReadiness } from "../payments/v2/readiness";

type VerifiedPaystackTransaction = {
  reference?: unknown;
  status?: unknown;
  amount?: unknown;
  fees?: unknown;
  currency?: unknown;
  channel?: unknown;
  paid_at?: unknown;
  metadata?: Record<string, unknown>;
};

type BuyerInput = {
  name: string;
  email: string;
  phone: string;
};

type AddressInput = {
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

function cors(res: functions.Response): void {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  res.set("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
}

function clean(value: unknown, field: string, max: number): string {
  const result = String(value ?? "")
    .trim()
    .replace(/\s+/g, " ");
  if (!result || result.length > max) throw new Error(`${field}_INVALID`);
  return result;
}

function parseBuyer(value: unknown, emailRequired: boolean): BuyerInput {
  const input =
    value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : {};
  const name = clean(input.name, "BUYER_NAME", 100);
  const email = String(input.email ?? "")
    .trim()
    .toLowerCase();
  if (email.length > 160 || (emailRequired && !email)) {
    throw new Error("BUYER_EMAIL_INVALID");
  }
  const phone = formatPhoneNumber(clean(input.phone, "BUYER_PHONE", 32));
  if (email && !/^\S+@\S+\.\S+$/.test(email)) {
    throw new Error("BUYER_EMAIL_INVALID");
  }
  if (!phone) {
    throw new Error("BUYER_PHONE_INVALID");
  }
  return { name, email, phone };
}

function parseAddress(value: unknown): AddressInput {
  const input =
    value && typeof value === "object"
      ? (value as Record<string, unknown>)
      : {};
  const rawProvince = clean(input.province, "ADDRESS_PROVINCE", 100);
  const provinceKey = rawProvince.toLowerCase().replace(/[^a-z]/g, "");
  const province = new Map<string, string>([
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
  ]).get(provinceKey);
  const postalCode = clean(input.postalCode, "ADDRESS_POSTAL_CODE", 12);
  if (!province) throw new Error("ADDRESS_PROVINCE_INVALID");
  if (!/^\d{4}$/.test(postalCode)) {
    throw new Error("ADDRESS_POSTAL_CODE_INVALID");
  }
  const locationInput =
    input.location && typeof input.location === "object"
      ? (input.location as Record<string, unknown>)
      : null;
  const latitude = Number(locationInput?.latitude);
  const longitude = Number(locationInput?.longitude);
  const location =
    Number.isFinite(latitude) && Number.isFinite(longitude)
      ? { latitude, longitude }
      : undefined;
  const plusCode = String(input.plusCode ?? "")
    .trim()
    .slice(0, 32);
  const source =
    input.source === "manual_review" || input.source === "geocoded"
      ? input.source
      : undefined;
  const originalText = String(input.originalText ?? "")
    .trim()
    .slice(0, 500);
  const landmark = String(input.landmark ?? "")
    .trim()
    .slice(0, 200);
  return {
    line1: clean(input.line1, "ADDRESS_LINE1", 160),
    line2: String(input.line2 ?? "")
      .trim()
      .slice(0, 160),
    suburb: clean(input.suburb, "ADDRESS_SUBURB", 100),
    city: clean(input.city, "ADDRESS_CITY", 100),
    province,
    postalCode,
    country: "ZA",
    ...(plusCode ? { plusCode } : {}),
    ...(location ? { location } : {}),
    ...(source ? { source } : {}),
    ...(originalText ? { originalText } : {}),
    ...(landmark ? { landmark } : {}),
  };
}

function requireSingleItemQuantity(value: unknown): void {
  if (value === undefined || value === null || value === "") return;
  const quantity = Number(value);
  if (!Number.isInteger(quantity) || quantity !== 1) {
    throw new Error("QUANTITY_INVALID");
  }
}

async function requireBoundBotCustomer(args: {
  sellerId: string;
  customerId: string;
  buyerPhone: string;
}): Promise<void> {
  const customer = await db
    .doc(`users/${args.sellerId}/customers/${args.customerId}`)
    .get();
  const storedPhone = normalizePhoneNumber(
    String(customer.data()?.number ?? ""),
  );
  const buyerPhone = normalizePhoneNumber(args.buyerPhone);
  if (!customer.exists || !storedPhone || storedPhone !== buyerPhone) {
    throw new Error("CUSTOMER_BINDING_INVALID");
  }
}

function paystackSecret(): string {
  dotenv.config({ path: path.join(process.cwd(), ".env.local") });
  dotenv.config({ path: path.join(process.cwd(), ".env") });
  const secret = String(
    process.env.PAYSTACK_SECRET_KEY ??
      process.env.PAYSTACK_TEST_SECRET_KEY ??
      functions.config().paystack?.secret ??
      "",
  ).trim();
  if (!secret) throw new Error("PAYSTACK_NOT_CONFIGURED");
  return secret;
}

function publicMessage(error: unknown): string {
  const code = error instanceof Error ? error.message : "";
  const responseStatus = Number(
    (error as { response?: { status?: unknown } } | null)?.response?.status,
  );
  if (code.includes("INVALID"))
    return "Check the highlighted checkout details.";
  if (code === "LISTING_UNAVAILABLE")
    return "This product is no longer available.";
  if (code === "CJ_OUT_OF_STOCK")
    return "This product has just gone out of stock.";
  if (code === "CJ_NO_SHIPPING_TO_ZA")
    return "This product cannot currently be delivered to that address.";
  if (
    code.startsWith("CJ_FX") ||
    [
      "CJ_UNAVAILABLE",
      "CJ_RATE_LIMITED",
      "CJ_COORDINATION_UNAVAILABLE",
      "CJ_AUTH_FAILED",
    ].includes(code)
  )
    return "Live supplier pricing is temporarily unavailable. Please try again.";
  if (code === "PAYSTACK_NOT_CONFIGURED")
    return "Online payments are unavailable.";
  if (code === "CHECKOUT_PREPARATION_CHANGED") {
    return "The delivery price changed. Review the updated total before placing the order.";
  }
  if (code === "CHECKOUT_PREPARATION_EXPIRED") {
    return "That delivery check expired. Send the location again to continue.";
  }
  if (
    code === "CHECKOUT_PREPARATION_INVALID" ||
    code === "PAYMENT_OPTION_UNAVAILABLE" ||
    code === "PAYMENT_OPTION_REQUIRED"
  ) {
    return "That checkout option is no longer available. Review the order again.";
  }
  if (responseStatus === 401 || responseStatus === 403)
    return "Online payments are temporarily unavailable.";
  return "Spaza One could not start payment. Please try again.";
}

function publicStatus(error: unknown): number {
  const code = error instanceof Error ? error.message : "";
  if (code === "CHECKOUT_PREPARATION_CHANGED") return 409;
  if (
    code.includes("PREPARATION") ||
    code === "PAYMENT_OPTION_UNAVAILABLE" ||
    code === "PAYMENT_OPTION_REQUIRED"
  ) {
    return 409;
  }
  return code.startsWith("CJ_") ? 503 : 400;
}

function publicCode(error: unknown): string {
  const code = error instanceof Error ? error.message : "";
  return [
    "CHECKOUT_PREPARATION_CHANGED",
    "CHECKOUT_PREPARATION_EXPIRED",
    "CHECKOUT_PREPARATION_INVALID",
    "PAYMENT_OPTION_UNAVAILABLE",
    "PAYMENT_OPTION_REQUIRED",
  ].includes(code)
    ? code
    : "CHECKOUT_FAILED";
}

/** Log provider failures without serializing request headers or credentials. */
function logCommerceError(context: string, error: unknown): void {
  const providerError = error as {
    message?: unknown;
    code?: unknown;
    response?: {
      status?: unknown;
      data?: { code?: unknown; type?: unknown; message?: unknown };
    };
  };
  console.error(context, {
    message: String(providerError?.message ?? "Unknown error").slice(0, 200),
    code: String(providerError?.code ?? "").slice(0, 80) || null,
    responseStatus: Number(providerError?.response?.status) || null,
    providerCode:
      String(providerError?.response?.data?.code ?? "").slice(0, 80) || null,
    providerType:
      String(providerError?.response?.data?.type ?? "").slice(0, 80) || null,
    providerMessage:
      String(providerError?.response?.data?.message ?? "").slice(0, 200) ||
      null,
  });
}

function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function checkoutAttemptId(listingId: string, value: unknown): string {
  const attempt = clean(value, "CHECKOUT_ATTEMPT", 128);
  return createHash("sha256").update(`${listingId}:${attempt}`).digest("hex");
}

const CHECKOUT_QUOTE_MAX_AGE_MS = 15 * 60 * 1000;

function validatedCheckoutQuote(
  value: unknown,
  expected: {
    productId: string;
    variantId: string;
    postalCode: string;
    nowMs: number;
  },
): CheckoutQuoteReservation {
  const quote =
    value && typeof value === "object"
      ? (value as Partial<CheckoutQuoteReservation>)
      : {};
  const productId = String(quote.productId ?? "");
  const variantId = String(quote.variantId ?? "");
  const postalCode = String(quote.postalCode ?? "");
  const reservedAtMs = Number(quote.reservedAtMs);
  const expiresAtMs = Number(quote.expiresAtMs);
  const productCostMinor = requireMinorUnits(
    quote.productCostMinor,
    "productCost",
  );
  const shippingCostMinor = requireMinorUnits(
    quote.shippingCostMinor,
    "shippingCost",
  );
  const landedCostMinor = requireMinorUnits(
    quote.landedCostMinor,
    "landedCost",
  );
  const productCostUsdMinor = requireMinorUnits(
    quote.productCostUsdMinor,
    "productCostUsd",
  );
  const shippingCostUsdMinor = requireMinorUnits(
    quote.shippingCostUsdMinor,
    "shippingCostUsd",
  );
  const fx = quote.fx ?? ({} as CheckoutQuoteReservation["fx"]);
  const rateMicros = requireMinorUnits(fx.rateMicros, "fxRate");
  const bufferBps = requireMinorUnits(fx.bufferBps, "fxBuffer");
  if (
    quote.supplierId !== "cj_dropshipping" ||
    productId !== expected.productId ||
    variantId !== expected.variantId ||
    postalCode !== expected.postalCode ||
    landedCostMinor !== productCostMinor + shippingCostMinor ||
    !Number.isSafeInteger(reservedAtMs) ||
    !Number.isSafeInteger(expiresAtMs) ||
    reservedAtMs > expected.nowMs ||
    expiresAtMs <= expected.nowMs ||
    expiresAtMs - reservedAtMs > CHECKOUT_QUOTE_MAX_AGE_MS ||
    !String(quote.verifiedAt ?? "").trim() ||
    !Number.isSafeInteger(rateMicros) ||
    rateMicros <= 0
  ) {
    throw new Error("CHECKOUT_PREPARATION_INVALID");
  }
  return {
    supplierId: "cj_dropshipping",
    productId,
    variantId,
    variantSku: String(quote.variantSku ?? "").slice(0, 200),
    postalCode,
    productCostMinor,
    shippingCostMinor,
    landedCostMinor,
    productCostUsdMinor,
    shippingCostUsdMinor,
    originCountryCode: String(quote.originCountryCode ?? "").slice(0, 8),
    logisticName: String(quote.logisticName ?? "").slice(0, 160),
    logisticAging: String(quote.logisticAging ?? "").slice(0, 80),
    verifiedAt: String(quote.verifiedAt),
    fx: {
      rateMicros,
      date: String(fx.date ?? "").slice(0, 40),
      bufferBps,
    },
    reservedAtMs,
    expiresAtMs,
  };
}

function selectedManualPaymentOption(
  value: unknown,
  available: readonly ManualPaymentOption[],
): ManualPaymentOption {
  const requested = String(value ?? "")
    .trim()
    .toLowerCase();
  if (!requested) {
    if (available.length === 1) return available[0];
    throw new Error("PAYMENT_OPTION_REQUIRED");
  }
  let option: ManualPaymentOption;
  if (requested === "cash" || requested === "pay_at_shop") {
    option = "pay_at_shop";
  } else if (requested === "transfer" || requested === "eft") {
    option = "eft";
  } else {
    throw new Error("PAYMENT_OPTION_UNAVAILABLE");
  }
  if (!available.includes(option)) {
    throw new Error("PAYMENT_OPTION_UNAVAILABLE");
  }
  return option;
}

function assertReusableOrderIdentity(
  value: FirebaseFirestore.DocumentData | undefined,
  expected: {
    listingId: string;
    paymentMethod: "manual" | "paystack";
    buyer: BuyerInput;
    whatsappBotOrder: boolean;
    sellerId: string;
    customerId: string;
  },
): void {
  if (!value) throw new Error("CHECKOUT_ATTEMPT_IDENTITY_INVALID");
  const buyer =
    value.buyer && typeof value.buyer === "object" ? value.buyer : {};
  const storedPhone = normalizePhoneNumber(String(buyer.phone ?? ""));
  const expectedPhone = normalizePhoneNumber(expected.buyer.phone);
  const expectedChannel = expected.whatsappBotOrder ? "whatsapp" : "web";
  if (
    String(value.listingId ?? "") !== expected.listingId ||
    String(value.paymentMethod ?? "") !== expected.paymentMethod ||
    String(value.orderChannel ?? "") !== expectedChannel ||
    !storedPhone ||
    storedPhone !== expectedPhone
  ) {
    throw new Error("CHECKOUT_ATTEMPT_IDENTITY_INVALID");
  }
  if (expected.whatsappBotOrder) {
    if (
      String(value.sellerId ?? "") !== expected.sellerId ||
      String(value.customerId ?? "") !== expected.customerId
    ) {
      throw new Error("CUSTOMER_BINDING_INVALID");
    }
    return;
  }
  if (
    String(buyer.email ?? "")
      .trim()
      .toLowerCase() !== expected.buyer.email
  ) {
    throw new Error("CHECKOUT_ATTEMPT_IDENTITY_INVALID");
  }
}

function commerceFunctionUrl(functionName: string): string {
  const projectId = String(
    process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "",
  ).trim();
  return process.env.FUNCTIONS_EMULATOR === "true"
    ? `http://127.0.0.1:5001/${projectId || "demo-spazaone"}/us-central1/${functionName}`
    : projectId
      ? `https://us-central1-${projectId}.cloudfunctions.net/${functionName}`
      : `http://127.0.0.1:5001/demo-spazaone/us-central1/${functionName}`;
}

function commerceOrderReturnUrl(
  listingId: string,
  orderId: string,
  token: string,
): string {
  const callback = new URL(commerceCheckoutUrl(listingId));
  callback.searchParams.set("order", orderId);
  callback.searchParams.set("token", token);
  return callback.toString();
}

/** Public endpoint that creates an order and initializes its own payment. */
export const createCommerceOrder = functions
  .runWith({
    secrets: ["CJ_API_KEY", "PASELLA_BOT_TOKEN", "PAYSTACK_SECRET_KEY"],
    timeoutSeconds: 120,
    memory: "512MB",
  })
  .https.onRequest(async (req, res) => {
    cors(res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const whatsappBotOrder =
        req.body?.orderChannel === "whatsapp" && verifyBotRequest(req);
      // Public supplier checkout is governed by Payments V2 readiness below.
      // WhatsApp keeps the existing seller-arranged manual payment path.
      const digitalPaymentsEnabled = !whatsappBotOrder;
      const paymentMethod: "paystack" | "manual" = digitalPaymentsEnabled
        ? "paystack"
        : "manual";
      requireSingleItemQuantity(req.body?.quantity);
      const listingId = clean(req.body?.listingId, "LISTING", 128);
      const buyer = parseBuyer(req.body?.buyer, digitalPaymentsEnabled);
      const expectedSellerId = whatsappBotOrder
        ? clean(req.body?.merchantId, "MERCHANT", 128)
        : "";
      const botCustomerId = whatsappBotOrder
        ? clean(req.body?.customerId, "CUSTOMER", 128)
        : "";
      if (whatsappBotOrder) {
        await requireBoundBotCustomer({
          sellerId: expectedSellerId,
          customerId: botCustomerId,
          buyerPhone: buyer.phone,
        });
      }
      const preparationId =
        whatsappBotOrder && req.body?.preparationId
          ? clean(req.body.preparationId, "PREPARATION", 128)
          : "";
      const preparationRef = preparationId
        ? db.doc(`commerceCheckoutPreparations/${preparationId}`)
        : null;
      const preparation = preparationRef ? await preparationRef.get() : null;
      const preparationData = preparation?.data() ?? null;
      if (preparationRef) {
        if (!preparation?.exists) {
          throw new Error("CHECKOUT_PREPARATION_INVALID");
        }
        if (
          String(preparationData?.merchantId ?? "") !== expectedSellerId ||
          String(preparationData?.customerId ?? "") !== botCustomerId ||
          String(preparationData?.listingId ?? "") !== listingId
        ) {
          throw new Error("CHECKOUT_PREPARATION_INVALID");
        }
      }
      const deliveryAddress = parseAddress(
        preparationData?.deliveryAddress ?? req.body?.deliveryAddress,
      );
      const manualPayment = whatsappBotOrder
        ? await merchantManualPaymentOptions(expectedSellerId)
        : null;
      const attemptRef = db.doc(
        `commerceCheckoutAttempts/${checkoutAttemptId(
          listingId,
          req.body?.checkoutAttemptId,
        )}`,
      );
      const listingRef = db.doc(`commerceListings/${listingId}`);
      const reuseIdentity = {
        listingId,
        paymentMethod,
        buyer,
        whatsappBotOrder,
        sellerId: expectedSellerId,
        customerId: botCustomerId,
      };

      const existingAttempt = await attemptRef.get();
      if (existingAttempt.exists) {
        const attemptData = existingAttempt.data() ?? {};
        const existingOrderId = String(attemptData.orderId ?? "");
        const existingOrder = await db
          .doc(`commerceOrders/${existingOrderId}`)
          .get();
        assertReusableOrderIdentity(existingOrder.data(), reuseIdentity);
        if (existingOrder.data()?.paymentMethod === "manual") {
          await deliverOrderCreatedOutbox(existingOrderId).catch((error) => {
            console.error("[commerce] order outbox retry failed", error);
          });
          const existingToken = String(attemptData.checkoutToken ?? "");
          if (!existingToken) {
            res.status(409).json({
              error: "Order request is still being prepared. Please try again.",
            });
            return;
          }
          res.status(200).json({
            orderId: existingOrderId,
            paymentMethod: "manual",
            confirmationUrl: commerceOrderReturnUrl(
              listingId,
              existingOrderId,
              existingToken,
            ),
            amountDueMinor: Number(existingOrder.data()?.amountDueMinor ?? 0),
            reference: existingOrderId.slice(0, 8).toUpperCase(),
            paymentInstructions:
              existingOrder.data()?.paymentInstructions ?? null,
            reused: true,
          });
          return;
        }
        const authorizationUrl = String(
          existingOrder.data()?.payment?.authorizationUrl ?? "",
        );
        if (!authorizationUrl) {
          const existingToken = String(attemptData.checkoutToken ?? "");
          if (!existingToken)
            throw new Error("CHECKOUT_ATTEMPT_IDENTITY_INVALID");
          const initialized = await initializeSupplierOrderPaymentV2({
            orderId: existingOrderId,
            email: buyer.email,
            callbackUrl: commerceOrderReturnUrl(
              listingId,
              existingOrderId,
              existingToken,
            ),
          });
          res.status(200).json({
            authorizationUrl: initialized.authorizationUrl,
            reused: true,
          });
          return;
        }
        res.status(200).json({ authorizationUrl, reused: true });
        return;
      }

      const manualPaymentOption: ManualPaymentOption = manualPayment
        ? selectedManualPaymentOption(
            req.body?.paymentPreference,
            manualPayment.paymentOptions,
          )
        : "eft";
      const candidateOrderRef = db.collection("commerceOrders").doc();
      const checkoutToken = randomBytes(32).toString("hex");
      const orderReference = candidateOrderRef.id.slice(0, 8).toUpperCase();
      const paymentInstructions = manualPayment
        ? {
            method: manualPaymentOption,
            reference: orderReference,
            ...(manualPaymentOption === "eft" && manualPayment.banking
              ? { banking: manualPayment.banking }
              : {}),
          }
        : null;

      if (preparationRef) {
        const expiresAt = preparationData?.expiresAt as
          | { toMillis?: () => number }
          | undefined;
        if (preparationData?.status !== "ready") {
          throw new Error("CHECKOUT_PREPARATION_INVALID");
        }
        if (
          typeof expiresAt?.toMillis !== "function" ||
          expiresAt.toMillis() <= Date.now()
        ) {
          throw new Error("CHECKOUT_PREPARATION_EXPIRED");
        }
      }

      const listingForQuote = await listingRef.get();
      if (!listingForQuote.exists || listingForQuote.data()?.active !== true) {
        throw new Error("LISTING_UNAVAILABLE");
      }
      const listingData = listingForQuote.data() ?? {};
      if (
        whatsappBotOrder &&
        String(listingData.sellerId ?? "") !== expectedSellerId
      ) {
        throw new Error("LISTING_UNAVAILABLE");
      }
      if (digitalPaymentsEnabled) {
        if (String(listingData.supplierId ?? "") !== "cj_dropshipping") {
          throw new Error("LISTING_UNAVAILABLE");
        }
        const readiness = await paymentReadiness({
          merchantId: clean(listingData.sellerId, "SELLER", 128),
          purpose: "supplier_order",
        });
        if (!readiness.enabled) throw new Error("PAYMENT_CAPABILITY_DISABLED");
      }
      let externalQuoteReservation: CheckoutQuoteReservation | null = null;
      if (String(listingData.supplierId ?? "") === "cj_dropshipping") {
        const productId = clean(
          listingData.supplierProductId,
          "SUPPLIER_PRODUCT",
          200,
        );
        const variantId = clean(
          listingData.supplierVariantId,
          "SUPPLIER_VARIANT",
          200,
        );
        if (preparationRef) {
          externalQuoteReservation = validatedCheckoutQuote(
            preparationData?.quoteReservation,
            {
              productId,
              variantId,
              postalCode: deliveryAddress.postalCode,
              nowMs: Date.now(),
            },
          );
        } else {
          const liveQuote = await quoteCjVariant({
            productId,
            variantId,
            postalCode: deliveryAddress.postalCode,
          });
          externalQuoteReservation = reserveCheckoutQuote(
            liveQuote,
            deliveryAddress.postalCode,
            Date.now() + CHECKOUT_QUOTE_MAX_AGE_MS,
          );
        }
      }

      const reserved = await db.runTransaction(async (tx) => {
        const [attempt, listing, prepared] = await Promise.all([
          tx.get(attemptRef),
          tx.get(listingRef),
          preparationRef ? tx.get(preparationRef) : Promise.resolve(null),
        ]);
        if (attempt.exists) {
          return {
            orderId: String(attempt.data()?.orderId ?? ""),
            created: false,
            checkoutToken: String(attempt.data()?.checkoutToken ?? ""),
          };
        }
        if (!listing.exists || listing.data()?.active !== true) {
          throw new Error("LISTING_UNAVAILABLE");
        }
        const transactionNowMs = Date.now();
        const preparedData = prepared?.data() ?? {};
        let finalDeliveryAddress = deliveryAddress;
        let preparationExpiresAtMs = 0;
        if (preparationRef) {
          const expiresAt = preparedData?.expiresAt as
            | { toMillis?: () => number }
            | undefined;
          if (
            !prepared?.exists ||
            preparedData.status !== "ready" ||
            preparedData.consumedOrderId
          ) {
            throw new Error("CHECKOUT_PREPARATION_INVALID");
          }
          if (
            String(preparedData.merchantId ?? "") !== expectedSellerId ||
            String(preparedData.customerId ?? "") !== botCustomerId ||
            String(preparedData.listingId ?? "") !== listingId
          ) {
            throw new Error("CHECKOUT_PREPARATION_INVALID");
          }
          if (
            typeof expiresAt?.toMillis !== "function" ||
            expiresAt.toMillis() <= transactionNowMs
          ) {
            throw new Error("CHECKOUT_PREPARATION_EXPIRED");
          }
          preparationExpiresAtMs = expiresAt.toMillis();
          if (
            !Array.isArray(preparedData.paymentOptions) ||
            !preparedData.paymentOptions.includes(manualPaymentOption)
          ) {
            throw new Error("PAYMENT_OPTION_UNAVAILABLE");
          }
          finalDeliveryAddress = parseAddress(preparedData.deliveryAddress);
        }
        const source = listing.data() ?? {};
        if (
          whatsappBotOrder &&
          String(source.sellerId ?? "") !== expectedSellerId
        ) {
          throw new Error("LISTING_UNAVAILABLE");
        }
        const isCj = String(source.supplierId ?? "") === "cj_dropshipping";
        const cjQuote = isCj
          ? validatedCheckoutQuote(
              preparationRef
                ? preparedData?.quoteReservation
                : externalQuoteReservation,
              {
                productId: String(source.supplierProductId ?? ""),
                variantId: String(source.supplierVariantId ?? ""),
                postalCode: finalDeliveryAddress.postalCode,
                nowMs: transactionNowMs,
              },
            )
          : null;
        if (
          preparationRef &&
          cjQuote &&
          cjQuote.expiresAtMs > preparationExpiresAtMs
        ) {
          throw new Error("CHECKOUT_PREPARATION_INVALID");
        }
        const baseCostMinor = cjQuote
          ? cjQuote.landedCostMinor
          : source.baseCostMinor;
        const sellPriceMinor = cjQuote
          ? cjQuote.landedCostMinor +
            requireMinorUnits(source.markupMinor, "markup")
          : source.sellPriceMinor;
        const supplierEconomics =
          digitalPaymentsEnabled && cjQuote
            ? supplierPaymentEconomics({
                landedCostMinor: cjQuote.landedCostMinor,
                markupMinor: requireMinorUnits(source.markupMinor, "markup"),
              })
            : null;
        const pricing = supplierEconomics
          ? {
              currency: "ZAR" as const,
              quantity: 1,
              baseCostMinor: supplierEconomics.landedCostMinor,
              sellPriceMinor:
                supplierEconomics.landedCostMinor +
                supplierEconomics.markupMinor,
              feeMinor: supplierEconomics.collectionFeeMinor,
              marginMinor: supplierEconomics.markupMinor,
              amountDueMinor: supplierEconomics.customerTotalMinor,
            }
          : priceCommerceOrder({
              baseCostMinor,
              sellPriceMinor,
              quantity: 1,
              paymentFeeMinor: 0,
            });
        if (pricing.amountDueMinor > 10_000_000) {
          throw new Error("AMOUNT_INVALID");
        }
        if (
          preparationRef &&
          pricing.amountDueMinor !== Number(preparedData.amountDueMinor)
        ) {
          throw new Error("CHECKOUT_PREPARATION_CHANGED");
        }
        const title = clean(source.title, "LISTING_TITLE", 160);
        const sellerId = clean(source.sellerId, "SELLER", 128);
        const image = Array.isArray(source.images)
          ? String(source.images[0] ?? "")
          : "";
        const supplierSnapshot = cjQuote
          ? {
              supplierVariantId: cjQuote.variantId,
              supplierSku: cjQuote.variantSku,
              supplierProductCostMinor: cjQuote.productCostMinor,
              supplierShippingCostMinor: cjQuote.shippingCostMinor,
              supplierProductCostUsdMinor: cjQuote.productCostUsdMinor,
              supplierShippingCostUsdMinor: cjQuote.shippingCostUsdMinor,
              supplierCurrency: "USD",
              fxRateMicros: cjQuote.fx.rateMicros,
              fxRateDate: cjQuote.fx.date,
              fxBufferBps: cjQuote.fx.bufferBps,
              sourceCountryCode: cjQuote.originCountryCode,
              logisticName: cjQuote.logisticName,
              logisticAging: cjQuote.logisticAging,
              supplierPricingVerifiedAt: cjQuote.verifiedAt,
            }
          : {};
        const now = FieldValue.serverTimestamp();
        const order = {
          sellerId,
          listingId,
          sellerProductId: String(source.sellerProductId ?? ""),
          supplierId: String(source.supplierId ?? ""),
          buyer,
          deliveryAddress: finalDeliveryAddress,
          deliveryLabel: String(preparedData?.deliveryLabel ?? ""),
          plusCode: String(preparedData?.plusCode ?? "") || null,
          deliveryEstimate: deliveryEstimateFromAging(
            cjQuote?.logisticAging ?? source.logisticAging,
          ),
          lineItems: [
            {
              listingId,
              sellerProductId: String(source.sellerProductId ?? ""),
              supplierProductId: String(source.supplierProductId ?? ""),
              ...supplierSnapshot,
              title,
              image,
              quantity: 1,
              baseCostMinor: pricing.baseCostMinor,
              sellPriceMinor: pricing.sellPriceMinor,
              feeMinor: pricing.feeMinor,
              marginMinor: pricing.marginMinor,
            },
          ],
          totals: pricing,
          currency: "ZAR",
          amountDueMinor: pricing.amountDueMinor,
          baseCostMinor: pricing.baseCostMinor,
          sellPriceMinor: pricing.sellPriceMinor,
          feeMinor: pricing.feeMinor,
          marginMinor: pricing.marginMinor,
          markupMinor: cjQuote
            ? requireMinorUnits(source.markupMinor, "markup")
            : pricing.marginMinor,
          collectionFeeMinor: supplierEconomics?.collectionFeeMinor ?? 0,
          safetyMarginMinor: supplierEconomics?.safetyMarginMinor ?? 0,
          ...(supplierEconomics ? { money: supplierEconomics.money } : {}),
          ...supplierSnapshot,
          fulfilmentMode: String(
            source.fulfilmentMode ?? "manual_supplier_order",
          ),
          paymentMethod,
          orderChannel: whatsappBotOrder ? "whatsapp" : "web",
          customerId: whatsappBotOrder ? botCustomerId : null,
          buyerPaymentPreference: whatsappBotOrder ? manualPaymentOption : null,
          shippingNotes: String(source.shippingNotes ?? ""),
          status: "pending_payment",
          paymentStatus: digitalPaymentsEnabled
            ? "pending"
            : "awaiting_manual_confirmation",
          fulfilmentStatus: "pending",
          payment: digitalPaymentsEnabled
            ? { provider: "paystack" }
            : {
                provider: "manual",
                collectionMode: "seller_arranged",
              },
          paymentInstructions,
          checkoutTokenHash: hashToken(checkoutToken),
          statusHistory: [
            {
              from: null,
              to: "pending_payment",
              actor: "buyer_checkout",
              at: new Date().toISOString(),
            },
          ],
          createdAt: now,
          updatedAt: now,
          schemaVersion: cjQuote ? 2 : 1,
        };
        tx.create(candidateOrderRef, order);
        tx.create(attemptRef, {
          listingId,
          orderId: candidateOrderRef.id,
          checkoutToken,
          createdAt: now,
          expiresAt: Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000),
        });
        if (!digitalPaymentsEnabled) {
          tx.create(orderCreatedOutboxRef(candidateOrderRef.id), {
            orderId: candidateOrderRef.id,
            event: "order_created",
            status: "pending",
            attempts: 0,
            leaseUntilMs: 0,
            createdAt: now,
            updatedAt: now,
          });
        }
        if (preparationRef) {
          tx.update(preparationRef, {
            status: "consumed",
            consumedOrderId: candidateOrderRef.id,
            consumedAt: now,
          });
        }
        return {
          orderId: candidateOrderRef.id,
          created: true,
          checkoutToken,
        };
      });

      const orderRef = db.doc(`commerceOrders/${reserved.orderId}`);
      if (!reserved.created) {
        const existing = await orderRef.get();
        assertReusableOrderIdentity(existing.data(), reuseIdentity);
        if (existing.data()?.paymentMethod === "manual") {
          await deliverOrderCreatedOutbox(orderRef.id).catch((error) => {
            console.error("[commerce] order outbox retry failed", error);
          });
          if (!reserved.checkoutToken) {
            res.status(409).json({
              error: "Order request is still being prepared. Please try again.",
            });
            return;
          }
          res.status(200).json({
            orderId: orderRef.id,
            paymentMethod: "manual",
            confirmationUrl: commerceOrderReturnUrl(
              listingId,
              orderRef.id,
              reserved.checkoutToken,
            ),
            amountDueMinor: Number(existing.data()?.amountDueMinor ?? 0),
            reference: orderRef.id.slice(0, 8).toUpperCase(),
            paymentInstructions: existing.data()?.paymentInstructions ?? null,
            reused: true,
          });
          return;
        }
        const authorizationUrl = String(
          existing.data()?.payment?.authorizationUrl ?? "",
        );
        if (!authorizationUrl) {
          const initialized = await initializeSupplierOrderPaymentV2({
            orderId: orderRef.id,
            email: buyer.email,
            callbackUrl: commerceOrderReturnUrl(
              listingId,
              orderRef.id,
              reserved.checkoutToken,
            ),
          });
          res.status(200).json({
            authorizationUrl: initialized.authorizationUrl,
            reused: true,
          });
          return;
        }
        res.status(200).json({ authorizationUrl, reused: true });
        return;
      }

      const order = await orderRef.get();
      const orderData = order.data() ?? {};
      const returnUrl = commerceOrderReturnUrl(
        listingId,
        orderRef.id,
        reserved.checkoutToken,
      );
      if (!digitalPaymentsEnabled) {
        await deliverOrderCreatedOutbox(orderRef.id).catch((error) => {
          console.error("[commerce] order request outbox failed", error);
        });
        res.status(200).json({
          orderId: orderRef.id,
          paymentMethod: "manual",
          confirmationUrl: returnUrl,
          amountDueMinor: Number(orderData.amountDueMinor ?? 0),
          reference: orderRef.id.slice(0, 8).toUpperCase(),
          paymentInstructions: orderData.paymentInstructions ?? null,
        });
        return;
      }
      const initialized = await initializeSupplierOrderPaymentV2({
        orderId: orderRef.id,
        email: buyer.email,
        callbackUrl: returnUrl,
      });
      res.status(200).json({ authorizationUrl: initialized.authorizationUrl });
    } catch (error) {
      logCommerceError("createCommerceOrder failed", error);
      res.status(publicStatus(error)).json({
        error: publicMessage(error),
        code: publicCode(error),
      });
    }
  });

export async function applyVerifiedCommercePayment(
  transaction: VerifiedPaystackTransaction,
): Promise<{ deduped: boolean; orderId: string }> {
  if (!commercePaymentsEnabled()) {
    throw new Error("COMMERCE_PAYMENTS_DISABLED");
  }
  const metadata = transaction.metadata ?? {};
  if (String(metadata.purpose ?? "") !== "commerce_order") {
    throw new Error("PURPOSE_MISMATCH");
  }
  const reference = clean(transaction.reference, "REFERENCE", 200);
  const orderId = clean(metadata.orderId, "ORDER", 128);
  const amountMinor = Number(transaction.amount);
  if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0) {
    throw new Error("AMOUNT_INVALID");
  }
  if (String(transaction.currency ?? "").toUpperCase() !== "ZAR") {
    throw new Error("CURRENCY_INVALID");
  }
  const orderRef = db.doc(`commerceOrders/${orderId}`);
  const processedRef = db.doc(
    `payments/paystackCommerce/processed/${reference}`,
  );
  let deduped = false;
  let notice: Parameters<typeof notifyCommerceOrder>[0] | null = null;
  await db.runTransaction(async (tx) => {
    const [processed, order] = await Promise.all([
      tx.get(processedRef),
      tx.get(orderRef),
    ]);
    if (!order.exists) throw new Error("ORDER_NOT_FOUND");
    const data = order.data() ?? {};
    if (
      String(data.paymentMethod ?? "") !== "paystack" ||
      String(data.payment?.provider ?? "") !== "paystack" ||
      String(data.payment?.reference ?? "") !== reference
    ) {
      throw new Error("PAYMENT_BINDING_MISMATCH");
    }
    if (Number(data.amountDueMinor) !== amountMinor) {
      throw new Error("AMOUNT_MISMATCH");
    }
    if (
      String(data.sellerId) !== String(metadata.sellerId) ||
      String(data.listingId) !== String(metadata.listingId)
    ) {
      throw new Error("METADATA_MISMATCH");
    }
    if (processed.exists) {
      const processedData = processed.data() ?? {};
      if (
        String(processedData.orderId ?? "") !== orderId ||
        Number(processedData.amountMinor) !== amountMinor ||
        String(processedData.currency ?? "").toUpperCase() !== "ZAR"
      ) {
        throw new Error("PROCESSED_PAYMENT_MISMATCH");
      }
      deduped = true;
      return;
    }
    if (data.paymentStatus === "paid") {
      if (String(data.payment?.reference ?? "") !== reference) {
        throw new Error("ORDER_ALREADY_PAID");
      }
      deduped = true;
    } else {
      if (data.status !== "pending_payment") {
        throw new Error("ORDER_NOT_PAYABLE");
      }
      const now = FieldValue.serverTimestamp();
      const actualFeeMinor = Number(transaction.fees);
      tx.update(orderRef, {
        status: "paid",
        paymentStatus: "paid",
        fulfilmentStatus: "paid",
        "payment.provider": "paystack",
        "payment.reference": reference,
        "payment.channel": String(transaction.channel ?? ""),
        "payment.actualFeeMinor": Number.isSafeInteger(actualFeeMinor)
          ? actualFeeMinor
          : null,
        "payment.paidAtProvider": String(transaction.paid_at ?? ""),
        paidAt: now,
        updatedAt: now,
        statusHistory: FieldValue.arrayUnion({
          from: "pending_payment",
          to: "paid",
          actor: "paystack_webhook",
          at: new Date().toISOString(),
          reference,
        }),
      });
      notice = {
        orderId,
        sellerId: String(data.sellerId),
        customerId: String(data.customerId ?? ""),
        buyerName: String(data.buyer?.name ?? "Customer"),
        buyerPhone: String(data.buyer?.phone ?? ""),
        status: "paid",
        amountDueMinor: Number(data.amountDueMinor),
      };
    }
    tx.create(processedRef, {
      reference,
      orderId,
      amountMinor,
      currency: "ZAR",
      processedAt: FieldValue.serverTimestamp(),
      schemaVersion: 1,
    });
  });
  if (notice) {
    await notifyCommerceOrder(notice).catch((error) => {
      console.error("[commerce] paid notification failed", error);
    });
  }
  return { deduped, orderId };
}

/** Dedicated commerce webhook; it never mutates wallets or manual sales. */
export const verifyCommercePaystackTransaction = functions.https.onRequest(
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    if (!commercePaymentsEnabled()) {
      res.status(503).json({ error: "Commerce payments are not enabled" });
      return;
    }
    try {
      const secret = paystackSecret();
      const rawBody =
        req.rawBody ?? Buffer.from(JSON.stringify(req.body ?? {}));
      if (
        !verifyPaystackSignature(
          rawBody,
          req.get("x-paystack-signature"),
          secret,
        )
      ) {
        res.status(401).json({ error: "Invalid webhook signature" });
        return;
      }
      if (req.body?.event !== "charge.success") {
        res.status(200).json({ ignored: true });
        return;
      }
      const reference = clean(req.body?.data?.reference, "REFERENCE", 200);
      const verify = await axios.get(
        `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
        {
          headers: { Authorization: `Bearer ${secret}` },
          timeout: 15000,
        },
      );
      const transaction = verify.data?.data as VerifiedPaystackTransaction;
      if (
        verify.data?.status !== true ||
        transaction?.status !== "success" ||
        String(transaction.reference ?? "") !== reference
      ) {
        res.status(400).json({ error: "Transaction not successful" });
        return;
      }
      const result = await applyVerifiedCommercePayment(transaction);
      res.status(200).json({ ok: true, deduped: result.deduped });
    } catch (error) {
      logCommerceError("verifyCommercePaystackTransaction failed", error);
      res.status(400).json({ error: "Commerce payment verification failed" });
    }
  },
);

/** Token-scoped public status used after the provider redirects the buyer. */
export const getCommerceOrderStatus = functions.https.onRequest(
  async (req, res) => {
    cors(res);
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "GET") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const orderId = clean(req.query.order, "ORDER", 128);
      const token = clean(req.query.token, "TOKEN", 128);
      const order = await db.doc(`commerceOrders/${orderId}`).get();
      if (
        !order.exists ||
        order.data()?.checkoutTokenHash !== hashToken(token)
      ) {
        res.status(404).json({ error: "Order not found" });
        return;
      }
      const data = order.data() ?? {};
      res.status(200).json({
        orderId,
        status: String(data.status ?? "pending_payment"),
        paymentStatus: String(data.paymentStatus ?? "pending"),
        paymentMethod: String(data.paymentMethod ?? "paystack"),
        reference: orderId.slice(0, 8).toUpperCase(),
      });
    } catch (_) {
      res.status(404).json({ error: "Order not found" });
    }
  },
);

export const commerceApiUrls = {
  createOrder: commerceFunctionUrl("createCommerceOrder"),
  orderStatus: commerceFunctionUrl("getCommerceOrderStatus"),
};
