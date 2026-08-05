import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { randomBytes, createHash } from "crypto";
import axios from "axios";
import * as dotenv from "dotenv";
import * as path from "path";
import { db, functions } from "../config/main";
import { commerceCheckoutUrl } from "./checkoutUrl";
import { notifyCommerceOrder } from "./notifications";
import { priceCommerceOrder, requireMinorUnits } from "./domain";
import { CjLandedQuote, quoteCjVariant } from "./cjClient";
import { verifyPaystackSignature } from "../payments/paystack/paystackSecurity";
import { formatPhoneNumber } from "../utils/phoneUtils";
import { commercePaymentsEnabled } from "./readiness";
import { verifyBotRequest } from "../security/requestAuth";

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
  return {
    line1: clean(input.line1, "ADDRESS_LINE1", 160),
    line2: String(input.line2 ?? "")
      .trim()
      .slice(0, 160),
    suburb: clean(input.suburb, "ADDRESS_SUBURB", 100),
    city: clean(input.city, "ADDRESS_CITY", 100),
    province: clean(input.province, "ADDRESS_PROVINCE", 100),
    postalCode: clean(input.postalCode, "ADDRESS_POSTAL_CODE", 12),
    country: "ZA",
  };
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
  if (responseStatus === 401 || responseStatus === 403)
    return "Online payments are temporarily unavailable.";
  return "Spaza One could not start payment. Please try again.";
}

function publicStatus(error: unknown): number {
  const code = error instanceof Error ? error.message : "";
  return code.startsWith("CJ_") ? 503 : 400;
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
    secrets: ["CJ_API_KEY", "PASELLA_BOT_TOKEN"],
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
      const digitalPaymentsEnabled =
        commercePaymentsEnabled() && !whatsappBotOrder;
      if (!digitalPaymentsEnabled && !whatsappBotOrder) {
        res.status(503).json({
          error: "Spaza One online checkout is not available yet.",
        });
        return;
      }
      const paymentMethod = digitalPaymentsEnabled ? "paystack" : "manual";
      const listingId = clean(req.body?.listingId, "LISTING", 128);
      const buyer = parseBuyer(req.body?.buyer, digitalPaymentsEnabled);
      const deliveryAddress = parseAddress(req.body?.deliveryAddress);
      const expectedSellerId = whatsappBotOrder
        ? clean(req.body?.merchantId, "MERCHANT", 128)
        : "";
      const attemptRef = db.doc(
        `commerceCheckoutAttempts/${checkoutAttemptId(
          listingId,
          req.body?.checkoutAttemptId,
        )}`,
      );
      const candidateOrderRef = db.collection("commerceOrders").doc();
      const checkoutToken = randomBytes(32).toString("hex");
      const listingRef = db.doc(`commerceListings/${listingId}`);

      const existingAttempt = await attemptRef.get();
      if (existingAttempt.exists) {
        const attemptData = existingAttempt.data() ?? {};
        const existingOrderId = String(attemptData.orderId ?? "");
        const existingOrder = await db
          .doc(`commerceOrders/${existingOrderId}`)
          .get();
        if (existingOrder.data()?.paymentMethod === "manual") {
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
            reused: true,
          });
          return;
        }
        const authorizationUrl = String(
          existingOrder.data()?.payment?.authorizationUrl ?? "",
        );
        if (!authorizationUrl) {
          res.status(409).json({
            error: "Payment is still being prepared. Please try again.",
          });
          return;
        }
        res.status(200).json({ authorizationUrl, reused: true });
        return;
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
      let liveCjQuote: CjLandedQuote | null = null;
      if (String(listingData.supplierId ?? "") === "cj_dropshipping") {
        liveCjQuote = await quoteCjVariant({
          productId: clean(
            listingData.supplierProductId,
            "SUPPLIER_PRODUCT",
            200,
          ),
          variantId: clean(
            listingData.supplierVariantId,
            "SUPPLIER_VARIANT",
            200,
          ),
          postalCode: deliveryAddress.postalCode,
        });
      }

      const reserved = await db.runTransaction(async (tx) => {
        const [attempt, listing] = await Promise.all([
          tx.get(attemptRef),
          tx.get(listingRef),
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
        const source = listing.data() ?? {};
        if (
          whatsappBotOrder &&
          String(source.sellerId ?? "") !== expectedSellerId
        ) {
          throw new Error("LISTING_UNAVAILABLE");
        }
        const isCj = String(source.supplierId ?? "") === "cj_dropshipping";
        const cjQuote = isCj ? liveCjQuote : null;
        if (
          isCj &&
          (!cjQuote ||
            cjQuote.product.productId !==
              String(source.supplierProductId ?? "") ||
            cjQuote.variant.variantId !==
              String(source.supplierVariantId ?? ""))
        ) {
          throw new Error("LISTING_UNAVAILABLE");
        }
        const baseCostMinor = cjQuote
          ? cjQuote.landedCostMinor
          : source.baseCostMinor;
        const sellPriceMinor = cjQuote
          ? cjQuote.landedCostMinor +
            requireMinorUnits(source.markupMinor, "markup")
          : source.sellPriceMinor;
        const pricing = priceCommerceOrder({
          baseCostMinor,
          sellPriceMinor,
          quantity: 1,
          paymentFeeMinor: digitalPaymentsEnabled ? undefined : 0,
        });
        if (pricing.amountDueMinor > 10_000_000) {
          throw new Error("AMOUNT_INVALID");
        }
        const title = clean(source.title, "LISTING_TITLE", 160);
        const sellerId = clean(source.sellerId, "SELLER", 128);
        const image = Array.isArray(source.images)
          ? String(source.images[0] ?? "")
          : "";
        const supplierSnapshot = liveCjQuote
          ? {
              supplierVariantId: liveCjQuote.variant.variantId,
              supplierSku: liveCjQuote.variant.sku,
              supplierProductCostMinor: liveCjQuote.productCostMinor,
              supplierShippingCostMinor: liveCjQuote.shippingCostMinor,
              supplierProductCostUsdMinor: liveCjQuote.productCostUsdMinor,
              supplierShippingCostUsdMinor: liveCjQuote.shippingCostUsdMinor,
              supplierCurrency: "USD",
              fxRateMicros: liveCjQuote.fx.rateMicros,
              fxRateDate: liveCjQuote.fx.date,
              fxBufferBps: liveCjQuote.fx.bufferBps,
              sourceCountryCode: liveCjQuote.originCountryCode,
              logisticName: liveCjQuote.logisticName,
              logisticAging: liveCjQuote.logisticAging,
              supplierPricingVerifiedAt: liveCjQuote.verifiedAt,
            }
          : {};
        const now = FieldValue.serverTimestamp();
        const order = {
          sellerId,
          listingId,
          sellerProductId: String(source.sellerProductId ?? ""),
          supplierId: String(source.supplierId ?? ""),
          buyer,
          deliveryAddress,
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
          ...supplierSnapshot,
          fulfilmentMode: String(
            source.fulfilmentMode ?? "manual_supplier_order",
          ),
          paymentMethod,
          orderChannel: whatsappBotOrder ? "whatsapp" : "web",
          customerId: whatsappBotOrder
            ? String(req.body?.customerId ?? "")
                .trim()
                .slice(0, 128)
            : null,
          buyerPaymentPreference: whatsappBotOrder
            ? String(req.body?.paymentPreference ?? "manual")
                .trim()
                .slice(0, 40)
            : null,
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
          schemaVersion: liveCjQuote ? 2 : 1,
        };
        tx.create(candidateOrderRef, order);
        tx.create(attemptRef, {
          listingId,
          orderId: candidateOrderRef.id,
          checkoutToken,
          createdAt: now,
          expiresAt: Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000),
        });
        return {
          orderId: candidateOrderRef.id,
          created: true,
          checkoutToken,
        };
      });

      const orderRef = db.doc(`commerceOrders/${reserved.orderId}`);
      if (!reserved.created) {
        const existing = await orderRef.get();
        if (existing.data()?.paymentMethod === "manual") {
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
            reused: true,
          });
          return;
        }
        const authorizationUrl = String(
          existing.data()?.payment?.authorizationUrl ?? "",
        );
        if (!authorizationUrl) {
          res.status(409).json({
            error: "Payment is still being prepared. Please try again.",
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
        await notifyCommerceOrder({
          orderId: orderRef.id,
          sellerId: String(orderData.sellerId ?? ""),
          customerId: String(orderData.customerId ?? ""),
          buyerName: buyer.name,
          buyerPhone: buyer.phone,
          status: "pending_payment",
          paymentMethod: "manual",
          amountDueMinor: Number(orderData.amountDueMinor ?? 0),
          notifyBuyer: !whatsappBotOrder,
        }).catch((error) => {
          console.error("[commerce] order request notification failed", error);
        });
        res.status(200).json({
          orderId: orderRef.id,
          paymentMethod: "manual",
          confirmationUrl: returnUrl,
          amountDueMinor: Number(orderData.amountDueMinor ?? 0),
          reference: orderRef.id.slice(0, 8).toUpperCase(),
        });
        return;
      }
      const reference = `SPAZA-COM-${orderRef.id}-${randomBytes(4).toString("hex")}`;
      const secret = paystackSecret();
      const initialize = await axios.post(
        "https://api.paystack.co/transaction/initialize",
        {
          email: buyer.email,
          amount: orderData.amountDueMinor,
          currency: "ZAR",
          channels: ["card", "eft", "qr"],
          reference,
          callback_url: returnUrl,
          metadata: {
            purpose: "commerce_order",
            orderId: orderRef.id,
            sellerId: orderData.sellerId,
            listingId,
            schemaVersion: 1,
          },
        },
        {
          headers: { Authorization: `Bearer ${secret}` },
          timeout: 15000,
        },
      );
      const authorizationUrl = String(
        initialize.data?.data?.authorization_url ?? "",
      );
      const providerReference = String(
        initialize.data?.data?.reference ?? reference,
      );
      if (!authorizationUrl) throw new Error("PAYSTACK_INIT_INVALID");
      await orderRef.set(
        {
          payment: {
            provider: "paystack",
            reference: providerReference,
            authorizationUrl,
            initializedAt: FieldValue.serverTimestamp(),
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      res.status(200).json({ authorizationUrl });
    } catch (error) {
      logCommerceError("createCommerceOrder failed", error);
      res.status(publicStatus(error)).json({ error: publicMessage(error) });
    }
  });

export async function applyVerifiedCommercePayment(
  transaction: VerifiedPaystackTransaction,
): Promise<{ deduped: boolean; orderId: string }> {
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
    if (processed.exists) {
      deduped = true;
      return;
    }
    if (!order.exists) throw new Error("ORDER_NOT_FOUND");
    const data = order.data() ?? {};
    if (Number(data.amountDueMinor) !== amountMinor) {
      throw new Error("AMOUNT_MISMATCH");
    }
    if (
      String(data.sellerId) !== String(metadata.sellerId) ||
      String(data.listingId) !== String(metadata.listingId)
    ) {
      throw new Error("METADATA_MISMATCH");
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
