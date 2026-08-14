// functions/src/merchant_hub/runMerchantPromotion.ts

import { functions, db } from "../config/main";
import { assertCallableStoreAccess } from "../stores/storeAccess";
import {
  CampaignReservation,
  CampaignWalletContext,
  mutateCampaignCredits,
  recordCampaignReservationSpend,
  reserveCampaignCredits,
  resolveCampaignWallet,
  settleCampaignReservation,
} from "../wallet/campaignCredits";
import twilio from "twilio";
import { FieldValue } from "firebase-admin/firestore";
import {
  DynamicPricingService,
  MessagingPricingUnavailableError,
} from "../services/dynamic_pricing_service";
import {
  formatPhoneNumber,
  isValidSAPhoneNumber,
  normalizePhoneNumber,
} from "../utils/phoneUtils";
import {
  normalizeTwilioError,
  NormalizedSendError,
} from "../utils/twilioError";
import { ensureMerchantOrderingLink } from "../ecommerce/getMerchantOrderingLink";
import { PRODUCT_PROMOTION_TEMPLATE_KIND } from "./ensureProductPromotionTemplate";

function formatProductPrice(value: unknown): string {
  const amount = Number(value);
  if (!Number.isFinite(amount)) return "a price available in WhatsApp";
  return `R${amount.toFixed(2)}`;
}

function buildProductPromotionSms(
  shopName: string,
  productName: string,
  productPrice: string,
  merchantMobileNumber: unknown,
): string {
  const contact = normalizePhoneNumber(String(merchantMobileNumber ?? ""));
  const orderInstruction = contact
    ? `Call ${contact} to order.`
    : "Contact the shop to order.";
  return `${shopName}: ${productName} is ${productPrice}. ${orderInstruction} Reply STOP to opt out.`;
}

function calculateSmsSegments(text: string): number {
  const content = (text || "").trim();
  if (!content) return 1;

  const isUnicode = [...content].some((char) => char.charCodeAt(0) > 127);
  const singleSegmentLength = isUnicode ? 70 : 160;
  const multipartSegmentLength = isUnicode ? 67 : 153;

  if (content.length <= singleSegmentLength) {
    return 1;
  }

  return Math.ceil(content.length / multipartSegmentLength);
}

type TwilioClient = ReturnType<typeof twilio>;

interface TwilioRuntime {
  client: TwilioClient;
  customerMessagingServiceSid: string;
  smsNumber: string;
  statusCallbackUrl: string;
}

let cachedTwilioRuntime: TwilioRuntime | undefined;

/**
 * Resolve provider credentials only when a real send is attempted. Reading
 * functions.config() at module load prevents the Functions emulator (and any
 * isolated staging project without production secrets) from discovering the
 * function bundle at all.
 */
function getTwilioRuntime(): TwilioRuntime {
  if (cachedTwilioRuntime) return cachedTwilioRuntime;

  const config = (functions.config().twilio ?? {}) as Record<string, unknown>;
  const accountSid = String(
    process.env.TWILIO_ACCOUNT_SID ?? config.sid ?? "",
  ).trim();
  const authToken = String(
    process.env.TWILIO_AUTH_TOKEN ?? config.token ?? "",
  ).trim();
  const customerMessagingServiceSid = String(
    process.env.TWILIO_CUSTOMER_MESSAGING_SERVICE_SID ??
      config.customer_messaging_service_sid ??
      "",
  ).trim();
  const smsNumber = String(
    process.env.TWILIO_SMS_NUMBER ?? config.number ?? "",
  ).trim();

  if (!accountSid || !authToken || !customerMessagingServiceSid || !smsNumber) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Messaging provider credentials are not configured for this environment.",
    );
  }

  const projectId = process.env.GCLOUD_PROJECT || "pasella-ledger";
  cachedTwilioRuntime = {
    client: twilio(accountSid, authToken),
    customerMessagingServiceSid,
    smsNumber,
    statusCallbackUrl:
      process.env.MESSAGE_STATUS_CALLBACK_URL ||
      `https://us-central1-${projectId}.cloudfunctions.net/messageStatusCallback`,
  };
  return cachedTwilioRuntime;
}

const DELIVERY_POLL_INTERVAL_MS = 1000;
const DELIVERY_CONFIRMATION_TIMEOUT_MS = 20000;
const FAILED_DELIVERY_STATUSES = new Set(["failed", "undelivered", "canceled"]);

const wait = (milliseconds: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

/**
 * Waits until Twilio confirms that a message was actually delivered.
 * A successful Messages.create response only means the provider accepted the
 * request; Meta can still reject it asynchronously a few seconds later.
 *
 * WhatsApp is only charged after `delivered`. SMS is charged after `sent` when
 * the carrier does not provide delivery receipts; a later terminal failure is
 * refunded idempotently by messageStatusCallback.
 */
async function waitForMessageDelivery(
  twilioClient: TwilioClient,
  messageSid: string,
  channel: "WhatsApp" | "SMS",
): Promise<void> {
  const deadline = Date.now() + DELIVERY_CONFIRMATION_TIMEOUT_MS;
  let lastStatus = "unknown";

  while (Date.now() < deadline) {
    const message = await twilioClient.messages(messageSid).fetch();
    const status = String(message.status ?? "unknown").toLowerCase();
    lastStatus = status;
    // Many SMS carriers do not return a delivery receipt. `sent` means Twilio
    // successfully handed the message to the mobile network and is the final
    // successful state available for those routes. WhatsApp must still reach
    // the stricter `delivered` state because Meta does provide receipts.
    if (status === "delivered" || (channel === "SMS" && status === "sent")) {
      return;
    }

    if (FAILED_DELIVERY_STATUSES.has(status)) {
      const errorCode = message.errorCode ?? null;
      let detail = message.errorMessage?.trim() || `Delivery ${status}.`;
      if (channel === "WhatsApp" && errorCode === 63032) {
        detail =
          "Meta temporarily limited marketing messages to this customer. " +
          "Try another customer or try again later. You were not charged.";
      }
      const deliveryError = new Error(detail) as Error & {
        code?: number | string;
      };
      deliveryError.code = errorCode ?? `delivery-${status}`;
      throw deliveryError;
    }

    await wait(DELIVERY_POLL_INTERVAL_MS);
  }

  const timeoutError = new Error(
    `${channel} delivery was not confirmed (last status: ${lastStatus}). ` +
      "You were not charged.",
  ) as Error & { code?: string };
  timeoutError.code = "delivery-unconfirmed";
  throw timeoutError;
}

/**
 * Reads WhatsApp availability and last‑check timestamp from Firestore.
 *
 * @param {string} phone - E.164 phone number (e.g. "+27123456789").
 * @return {Promise<any>} - Whether this number can receive WhatsApp.
 */
async function fetchWhatsAppStatus(
  phone: string,
): Promise<{ hasWhatsApp: boolean; lastChecked: Date | null }> {
  const local = normalizePhoneNumber(phone);
  if (!local) return { hasWhatsApp: false, lastChecked: null };

  const snap = await db
    .collection("successfulWhatsAppNumbers")
    .where("phoneNumber", "==", local)
    .limit(1)
    .get();
  if (snap.empty) return { hasWhatsApp: false, lastChecked: null };

  const data = snap.docs[0].data();
  return {
    hasWhatsApp: data.hasWhatsApp ?? false,
    lastChecked:
      (data.lastChecked as FirebaseFirestore.Timestamp)?.toDate() ?? null,
  };
}

/**
 * Persists the result of a WhatsApp availability check to Firestore.
 *
 * @param {string} phone - E.164 phone number.
 * @param {boolean} hasWhatsApp - Whether WhatsApp is available.
 * @return {Promise<void>} - Resolves once stored.
 */
async function storeWhatsAppCheck(
  phone: string,
  hasWhatsApp: boolean,
): Promise<void> {
  const local = normalizePhoneNumber(phone);
  if (!local) return;

  const col = db.collection("successfulWhatsAppNumbers");
  const snap = await col.where("phoneNumber", "==", local).limit(1).get();
  const payload = { hasWhatsApp, lastChecked: FieldValue.serverTimestamp() };

  if (snap.empty) {
    await col.add({ phoneNumber: local, ...payload });
  } else {
    await snap.docs[0].ref.set(payload, { merge: true });
  }
}

/**
 * Deducts cost from merchant wallet and records a notification.
 *
 * @param {string} merchantId - UID of the merchant.
 * @param {string} customerId - UID of the customer.
 * @param {string} phone - E.164 formatted phone number.
 * @param {number} cost - Amount in ZAR to deduct.
 * @param {'whatsapp'|'sms'} channel - Channel used.
 * @param {string} logMsg - Text to store in notification.
 * @param {string|null} [messageSid] - Twilio MessageSid returned by
 *   the SDK on a successful send. Persisted so the status-callback
 *   webhook can correlate delayed delivery failures back to this
 *   recipient (PAS-WA-01).
 * @return {Promise<void>} - Resolves when done.
 */
async function recordSend(
  walletContext: CampaignWalletContext,
  reservation: CampaignReservation | null,
  customerId: string,
  phone: string,
  cost: number,
  channel: "whatsapp" | "sms",
  logMsg: string,
  messageSid: string | null = null,
): Promise<void> {
  const merchantId = walletContext.storeId;

  const deliveryChargeRef = messageSid
    ? db.collection("messageDeliveryCharges").doc(messageSid)
    : null;

  await db.runTransaction(async (tx) => {
    if (reservation) {
      await recordCampaignReservationSpend(tx, reservation, cost);
    } else {
      await mutateCampaignCredits(tx, walletContext, -cost, {
        id: `message:${messageSid ?? db.collection("_ids").doc().id}`,
        kind: "promotion-send",
        metadata: { customerId, channel, messageSid },
      });
    }
    if (deliveryChargeRef) {
      tx.set(deliveryChargeRef, {
        merchantId,
        walletStoreId: walletContext.walletStoreId,
        sharedCampaignCredits: walletContext.shared,
        customerId,
        phone,
        channel,
        cost,
        refunded: false,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
  });

  await db
    .collection("notifications")
    .doc(merchantId)
    .collection("customer_notifications")
    .add({
      timestamp: FieldValue.serverTimestamp(),
      message: logMsg,
      messageCost: cost,
      merchant: merchantId,
      customer_id: customerId,
      customer_phone: phone,
      templateKey: null,
      templateType: channel,
      dateSent: FieldValue.serverTimestamp(),
      messageSid,
    });
}

/**
 * Persists a per-recipient send failure under the promotion so that
 * support and the merchant UI can diagnose what went wrong without
 * having to scrape Cloud Function logs. We always record the
 * SpazaOne-normalized message (including the fallback case where the
 * provider gave us nothing), the channel attempted, and the raw
 * provider fields where present.
 *
 * @param {string} promotionId - The promotion this failure belongs to.
 * @param {string} customerId - The customer the send was for.
 * @param {string} phone - E.164 number we attempted to send to.
 * @param {NormalizedSendError} norm - Normalized error record.
 * @return {Promise<void>} - Resolves once the failure is persisted.
 */
async function recordFailure(
  promotionId: string,
  customerId: string,
  phone: string,
  norm: NormalizedSendError,
): Promise<void> {
  await db
    .collection("promotions")
    .doc(promotionId)
    .collection("failures")
    .add({
      customerId,
      customerPhone: phone,
      channel: norm.channel,
      providerCode: norm.providerCode,
      providerMessage: norm.providerMessage,
      providerMoreInfo: norm.providerMoreInfo,
      providerStatus: norm.providerStatus,
      pasellaMessage: norm.pasellaMessage,
      fallbackUsed: norm.fallbackUsed,
      rawSnippet: norm.rawSnippet,
      timestamp: FieldValue.serverTimestamp(),
    });
}

/**
 * Processes and sends a saved promotion:
 * 1. Loads promotion & shop data.
 * 2. Computes per‑unit costs via Remote Config.
 * 3. For each customer:
 *    a. Normalizes number.
 *    b. Checks/updates WhatsApp status (30‑day TTL).
 *    c. Attempts WhatsApp template send (only charges on success).
 *    d. Falls back to SMS plain‑text send (only charges on success).
 * 4. Records only successful sends and deducts actual cost.
 *
 * @param {{promotionId?: string}} data - Payload with `promotionId`.
 * @param {functions.https.CallableContext} context - Callable context (auth info).
 * @returns {Promise<{success: boolean}>} - Resolves when complete.
 */
export const runMerchantPromotion = functions
  .runWith({ timeoutSeconds: 540 })
  .https.onCall(
    async (
      data: { promotionId?: string; storeId?: string },
      context: functions.https.CallableContext,
    ): Promise<{ success: boolean }> => {
      if (!context.auth) {
        throw new functions.https.HttpsError(
          "unauthenticated",
          "Must be signed in",
        );
      }
      const merchantId = String(data.storeId ?? context.auth.uid).trim();
      await assertCallableStoreAccess(context, merchantId);
      const campaignWallet = await resolveCampaignWallet(merchantId);
      const promotionId = data.promotionId;
      if (!promotionId) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "promotionId is required",
        );
      }

      // Load promotion
      const promoRef = db.collection("promotions").doc(promotionId);
      const promoSnap = await promoRef.get();
      if (!promoSnap.exists) {
        throw new functions.https.HttpsError(
          "not-found",
          "Promotion not found",
        );
      }
      const promo = promoSnap.data();
      if (!promo) {
        throw new functions.https.HttpsError(
          "not-found",
          "Promotion not found",
        );
      }
      if (promo.merchantId !== merchantId) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Not your promotion",
        );
      }

      const templateId =
        typeof promo.templateId === "string" ? promo.templateId.trim() : "";
      if (!templateId) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Promotion is missing a template",
        );
      }

      // Load and validate the message template before marking the promotion as
      // processing. A bad or cross-merchant template ID must fail without
      // leaving the promotion stuck in an in-flight state.
      const tplSnap = await db
        .collection("messagingTemplates")
        .doc(templateId)
        .get();
      if (!tplSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Template not found");
      }
      const tpl = tplSnap.data();
      if (!tpl) {
        throw new functions.https.HttpsError("not-found", "Template not found");
      }
      if (tpl.userId !== merchantId) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Template does not belong to this merchant",
        );
      }

      // Resolve every runtime field before marking the promotion as processing.
      // A missing/deleted product or ordering link should fail cleanly instead of
      // leaving the campaign stuck in an in-flight state.
      const usrSnap = await db.collection("users").doc(merchantId).get();
      const user = usrSnap.data();
      const shopName =
        String(user?.shopName ?? "Spaza One").trim() || "Spaza One";
      const isProductPromotion =
        tpl.systemManaged === true &&
        tpl.templateKind === PRODUCT_PROMOTION_TEMPLATE_KIND;
      let productVariables: Record<string, string> = {};

      if (isProductPromotion) {
        const linkedProduct = promo.linkedProduct;
        const productId =
          typeof linkedProduct?.id === "string" ? linkedProduct.id.trim() : "";
        if (!productId) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Choose a product before sending this promotion.",
          );
        }
        const productSnap = await db
          .collection("users")
          .doc(merchantId)
          .collection("products")
          .doc(productId)
          .get();
        const product = productSnap.data();
        if (!productSnap.exists || !product) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "This product no longer exists. Choose another product.",
          );
        }
        const isWhatsAppListed =
          product.whatsappListed === true ||
          product.whatsappEnabled === true ||
          product.availableOnWhatsApp === true;
        if (!isWhatsAppListed) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "List this product for WhatsApp orders before promoting it.",
          );
        }

        const productName = String(product.name || "").trim();
        if (!productName) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Add a product name before promoting it.",
          );
        }

        const ordering = await ensureMerchantOrderingLink(merchantId);
        productVariables = {
          productName,
          productPrice: formatProductPrice(
            product.sellingPrice ?? product.price ?? product.productPrice,
          ),
          productImagePath: `${merchantId}/${productId}.png`,
          orderCode: ordering.code,
        };
      }

      // Pricing via Remote Config
      let pricing: DynamicPricingService;
      try {
        pricing = await DynamicPricingService.initialize();
      } catch (error) {
        if (error instanceof MessagingPricingUnavailableError) {
          throw new functions.https.HttpsError(
            "failed-precondition",
            "Campaign pricing is unavailable. Try again later.",
          );
        }
        throw error;
      }
      const unitWA = promo.sendWhatsApp ? pricing.whatsappPromotionPrice : 0;
      const unitSMS = promo.sendSMS ? pricing.smsReminderTemplatePrice : 0;
      let totalCost = 0;

      const waSid = tpl.channels?.whatsapp?.twilioTemplateId ?? templateId;
      const smsRaw = isProductPromotion
        ? buildProductPromotionSms(
            shopName,
            productVariables.productName,
            productVariables.productPrice,
            user?.mobileNumber ?? context.auth.token.phone_number,
          )
        : (tpl.channels?.sms?.templateContent ?? "");
      const customerIds = Array.isArray(promo.customerIds)
        ? promo.customerIds.map((value) => String(value))
        : [];
      const customerSnapshots = customerIds.length
        ? await db.getAll(
            ...customerIds.map((customerId) =>
              db.doc(`users/${merchantId}/customers/${customerId}`),
            ),
          )
        : [];
      const customersById = new Map(
        customerSnapshots.map((customer) => [
          customer.id,
          customer.data() ?? {},
        ]),
      );
      let reservationCeiling = 0;
      let eligibleRecipientCount = 0;
      for (const customerId of customerIds) {
        const customer = customersById.get(customerId);
        if (!customer?.number || !isValidSAPhoneNumber(customer.number)) {
          continue;
        }
        eligibleRecipientCount++;
        const smsBody = smsRaw
          .replaceAll("{{customerName}}", String(customer.name ?? "Customer"))
          .replaceAll("{{shopName}}", shopName)
          .replaceAll(
            "{{productName}}",
            productVariables.productName || "this product",
          )
          .replaceAll(
            "{{productPrice}}",
            productVariables.productPrice || "the advertised price",
          );
        const smsCost =
          Math.round(unitSMS * calculateSmsSegments(smsBody) * 100) / 100;
        const maximumRecipientCost = Math.max(
          promo.sendWhatsApp ? unitWA : 0,
          promo.sendSMS ? smsCost : 0,
        );
        reservationCeiling += maximumRecipientCost;
      }
      reservationCeiling = Math.round(reservationCeiling * 100) / 100;
      if (
        !promo.testMode &&
        eligibleRecipientCount > 0 &&
        reservationCeiling <= 0
      ) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Campaign pricing is unavailable. Try again later.",
        );
      }
      const reservation = promo.testMode
        ? null
        : await reserveCampaignCredits(
            campaignWallet,
            promotionId,
            reservationCeiling,
            context.auth.uid,
          );

      // Mark processing only after the full worst-case cost has been reserved.
      // Insufficient shared funds therefore fail before the first provider call.
      await promoRef.update({
        status: "processing",
        startedAt: FieldValue.serverTimestamp(),
        reservedCampaignCredits: reservationCeiling,
        campaignWalletStoreId: campaignWallet.walletStoreId,
      });

      // Send to each customer
      // PAS-WA-01: keep running tallies so we can write a terminal
      // status that reflects reality. Previously the promotion always
      // landed on `complete` no matter how many sends failed.
      let attempted = 0;
      let succeeded = 0;
      let failed = 0;
      let lastErrorMessage: string | null = null;

      for (const custId of customerIds) {
        try {
          const cust = customersById.get(custId);
          if (!cust?.number) {
            console.log(`Skipping ${custId}: no number`);
            continue;
          }

          // Validate & normalize. Reject anything not a valid SA mobile so
          // we never hand junk to Twilio (which silently fails per-customer).
          if (!isValidSAPhoneNumber(cust.number)) {
            console.warn(
              `Skipping ${custId}: invalid SA phone number "${cust.number}"`,
            );
            continue;
          }
          const num = formatPhoneNumber(cust.number); // E.164 "+27..."
          const waTo = `whatsapp:${num}`;
          const smsTo = num;

          // WhatsApp TTL logic
          const { hasWhatsApp, lastChecked } = await fetchWhatsAppStatus(num);
          const days = lastChecked
            ? (Date.now() - lastChecked.getTime()) / 86400000
            : Infinity;
          const needsCheck = days > 30;

          let sentViaWA = false;
          let waErrorWasFallback = false;

          // A fresh negative capability record means this recipient should go
          // directly to SMS. Unknown/stale numbers get a live WhatsApp attempt
          // first and automatically fall back to SMS on any delivery failure.
          const shouldAttemptWhatsApp =
            promo.sendWhatsApp && (needsCheck || hasWhatsApp);

          if (shouldAttemptWhatsApp) {
            attempted++;
            console.log(
              `[WA] ${custId} ➡️ trying WA (needsCheck=${needsCheck}, has=${hasWhatsApp})`,
            );
            if (!promo.testMode) {
              try {
                // PAS-WA-01: capture the SDK response so we can persist
                // the MessageSid. Without the sid, the status-callback
                // webhook has no way to correlate a later
                // failed/undelivered status back to this promotion
                // and recipient.
                // PAS-WA-02: contentVariables must be keyed by the
                // *named* placeholders used when the template was
                // registered with Twilio (see submitWhatsAppTemplate.ts
                // -> parseNamedVariables, which submits `customerName`
                // and `shopName` as the named variables and "Test Shop"
                // / "Tsepo" as approval samples). The previous payload
                // used positional keys "1" and "2", which Twilio could
                // not match against the named template, so it silently
                // fell back to the registered sample values — that's
                // why every WhatsApp promotion arrived as
                // "...The Test Shop team" regardless of the merchant's
                // actual shop name. Keys here must match the names in
                // the template body exactly. If a new named placeholder
                // is added to the boilerplate it must also be added
                // here. SMS interpolation in the fallback branch below
                // already does this correctly via local replaceAll.
                const twilioRuntime = getTwilioRuntime();
                const waResp = await twilioRuntime.client.messages.create({
                  to: waTo,
                  from: twilioRuntime.customerMessagingServiceSid,
                  contentSid: waSid,
                  statusCallback: twilioRuntime.statusCallbackUrl,
                  contentVariables: JSON.stringify({
                    customerName: cust.name,
                    shopName: shopName,
                    ...productVariables,
                  }),
                });
                if (!waResp?.sid) {
                  throw new Error(
                    "Twilio accepted the request without returning a message ID. " +
                      "You were not charged.",
                  );
                }
                await waitForMessageDelivery(
                  twilioRuntime.client,
                  waResp.sid,
                  "WhatsApp",
                );
                sentViaWA = true;
                succeeded++;
                totalCost += unitWA;
                await storeWhatsAppCheck(num, true);
                await recordSend(
                  campaignWallet,
                  reservation,
                  custId,
                  num,
                  unitWA,
                  "whatsapp",
                  isProductPromotion
                    ? `${productVariables.productName} — ${productVariables.productPrice}`
                    : smsRaw,
                  waResp?.sid ?? null,
                );
              } catch (err) {
                // PAS-WA-01: preserve Twilio detail when present, and
                // fall back to a SpazaOne-friendly message when it's
                // missing. Persisted under the promotion so support
                // can see why each recipient failed.
                const norm = normalizeTwilioError(err, "whatsapp");
                // A synchronous Twilio failure can mean bad credentials,
                // template configuration, rate limiting, or networking. None
                // proves that the recipient lacks WhatsApp, so do not poison
                // the 30-day capability cache here. Delivery callbacks are the
                // appropriate source for recipient-level capability failures.
                waErrorWasFallback = norm.fallbackUsed;
                lastErrorMessage = norm.pasellaMessage;
                await recordFailure(promotionId, custId, num, norm);
                console.warn(
                  `[WA] ${custId} failed: ${norm.pasellaMessage}` +
                    (norm.providerMoreInfo
                      ? ` (more: ${norm.providerMoreInfo})`
                      : ""),
                );
              }
            } else {
              // Test mode
              sentViaWA = true;
              succeeded++;
              totalCost += unitWA;
              await storeWhatsAppCheck(num, true);
              console.log(`[TEST] WA ${custId} @ R${unitWA}`);
            }
          }

          // SMS fallback
          if (!sentViaWA && promo.sendSMS) {
            // Only count an SMS attempt when WA was not already counted
            // — otherwise a single recipient with both channels enabled
            // would inflate `attempted`. The WA branch above only
            // increments `attempted` when it actually called the SDK.
            if (!promo.sendWhatsApp || !shouldAttemptWhatsApp) {
              attempted++;
            }
            const smsBody = smsRaw
              .replaceAll("{{customerName}}", cust.name)
              .replaceAll("{{shopName}}", shopName)
              .replaceAll(
                "{{productName}}",
                productVariables.productName || "this product",
              )
              .replaceAll(
                "{{productPrice}}",
                productVariables.productPrice || "the advertised price",
              );
            const smsSegments = calculateSmsSegments(smsBody);
            const smsCost = Math.round(unitSMS * smsSegments * 100) / 100;
            console.log(
              `[SMS] ${custId} ➡️ trying SMS @ R${unitSMS} × ${smsSegments} = R${smsCost}`,
            );
            if (!promo.testMode) {
              // PAS-WA-01: wrap the SMS send in its own try/catch so a
              // provider failure here doesn't fall through to the
              // outer per-customer catch (which used to swallow it
              // with a generic console.error and no persistence).
              try {
                const twilioRuntime = getTwilioRuntime();
                const smsResp = await twilioRuntime.client.messages.create({
                  to: smsTo,
                  from: twilioRuntime.smsNumber,
                  body: smsBody,
                  statusCallback: twilioRuntime.statusCallbackUrl,
                });
                if (!smsResp?.sid) {
                  throw new Error(
                    "Twilio accepted the SMS without returning a message ID. " +
                      "You were not charged.",
                  );
                }
                await waitForMessageDelivery(
                  twilioRuntime.client,
                  smsResp.sid,
                  "SMS",
                );
                succeeded++;
                totalCost += smsCost;
                await recordSend(
                  campaignWallet,
                  reservation,
                  custId,
                  num,
                  smsCost,
                  "sms",
                  smsBody,
                  smsResp?.sid ?? null,
                );
              } catch (smsErr) {
                failed++;
                const norm = normalizeTwilioError(smsErr, "sms");
                lastErrorMessage = norm.pasellaMessage;
                await recordFailure(promotionId, custId, num, norm);
                console.warn(
                  `[SMS] ${custId} failed: ${norm.pasellaMessage}` +
                    (norm.providerMoreInfo
                      ? ` (more: ${norm.providerMoreInfo})`
                      : ""),
                );
              }
            } else {
              totalCost += smsCost;
              console.log(
                `[TEST] SMS ${custId} @ R${unitSMS} × ${smsSegments} = R${smsCost}`,
                smsBody,
              );
            }
          } else if (
            !sentViaWA &&
            promo.sendWhatsApp &&
            shouldAttemptWhatsApp
          ) {
            // WhatsApp was the only channel and it failed (no SMS
            // fallback configured). Count it as a failed recipient so
            // the terminal status reflects the truth.
            failed++;
            // The failure record itself was already written in the
            // WA catch above. `waErrorWasFallback` is read only to
            // document why we don't double-write here.
            void waErrorWasFallback;
          }
        } catch (e) {
          // PAS-WA-01: outer catch used to log-and-forget. Persist a
          // generic failure so the recipient at least shows up in the
          // failures list with the SpazaOne fallback message.
          failed++;
          const norm = normalizeTwilioError(e, "whatsapp");
          lastErrorMessage = norm.pasellaMessage;
          try {
            await recordFailure(promotionId, custId, "", norm);
          } catch (persistErr) {
            console.error(
              `Failed to persist failure record for ${custId}:`,
              persistErr,
            );
          }
          console.error(`Error sending to ${custId}:`, e);
        }
      }

      if (reservation) {
        await settleCampaignReservation(reservation);
      }

      // PAS-WA-01: choose a terminal status that reflects what actually
      // happened. `complete` is reserved for "every attempted send
      // succeeded"; mixed outcomes become `partial`; total wipeout
      // becomes `failed`. Existing UI that only branches on
      // `'saved' | 'processing' | other` keeps working (everything else
      // still renders green) but the field is now diagnosable from
      // Firestore and from the promotion detail page going forward.
      let terminalStatus: "complete" | "partial" | "failed";
      if (attempted === 0 || succeeded === 0) {
        terminalStatus = "failed";
      } else if (failed === 0) {
        terminalStatus = "complete";
      } else {
        terminalStatus = "partial";
      }

      console.log(
        `[PROMO] ${promotionId} ${terminalStatus}, totalCost=R${totalCost}, attempted=${attempted}, succeeded=${succeeded}, failed=${failed}`,
      );
      await promoRef.update({
        status: terminalStatus,
        completedAt: FieldValue.serverTimestamp(),
        actualCost: totalCost,
        attemptedCount: attempted,
        succeededCount: succeeded,
        failedCount: failed,
        lastErrorMessage: lastErrorMessage,
      });

      return { success: true };
    },
  );
