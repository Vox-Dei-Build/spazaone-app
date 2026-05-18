// functions/src/merchant_hub/runMerchantPromotion.ts

import { functions, db } from "../config/main";
import twilio from "twilio";
import { FieldValue } from "firebase-admin/firestore";
import { DynamicPricingService } from "../services/dynamic_pricing_service";
import {
  formatPhoneNumber,
  isValidSAPhoneNumber,
  normalizePhoneNumber,
} from "../utils/phoneUtils";
import {
  normalizeTwilioError,
  NormalizedSendError,
} from "../utils/twilioError";

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

const {
  sid: ACCOUNT_SID,
  token: AUTH_TOKEN,
  customer_messaging_service_sid: CUSTOMER_WA_SID,
  number: SMS_NUMBER,
} = functions.config().twilio;

// initialize once
const twilioClient = twilio(ACCOUNT_SID, AUTH_TOKEN);

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
  merchantId: string,
  customerId: string,
  phone: string,
  cost: number,
  channel: "whatsapp" | "sms",
  logMsg: string,
  messageSid: string | null = null,
): Promise<void> {
  const walletRef = db
    .collection("users")
    .doc(merchantId)
    .collection("wallet")
    .doc("current");

  await db.runTransaction((tx) =>
    tx.get(walletRef).then((snap) => {
      const bal = (snap.data()?.virtualBalance || 0) - cost;
      tx.update(walletRef, { virtualBalance: bal });
    }),
  );

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
 * Pasella-normalized message (including the fallback case where the
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
export const runMerchantPromotion = functions.https.onCall(
  async (
    data: { promotionId?: string },
    context: functions.https.CallableContext,
  ): Promise<{ success: boolean }> => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be signed in",
      );
    }
    const merchantId = context.auth.uid;
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
      throw new functions.https.HttpsError("not-found", "Promotion not found");
    }
    const promo = promoSnap.data()!;
    if (promo.merchantId !== merchantId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Not your promotion",
      );
    }

    // Mark processing
    await promoRef.update({
      status: "processing",
      startedAt: FieldValue.serverTimestamp(),
    });

    // Fetch shop name
    const usrSnap = await db.collection("users").doc(merchantId).get();
    const shopName = usrSnap.data()?.shopName ?? "Pasella";

    // Pricing via Remote Config
    const pricing = await DynamicPricingService.initialize();
    const unitWA = promo.sendWhatsApp ? pricing.whatsappPromotionPrice : 0;
    const unitSMS = promo.sendSMS ? pricing.smsReminderTemplatePrice : 0;
    let totalCost = 0;

    // Load message template
    const tplSnap = await db
      .collection("messagingTemplates")
      .doc(promo.templateId)
      .get();
    const tpl = tplSnap.data() || {};
    const waSid = tpl.channels?.whatsapp?.twilioTemplateId ?? promo.templateId;
    const smsRaw = tpl.channels?.sms?.templateContent ?? "";

    // Send to each customer
    // PAS-WA-01: keep running tallies so we can write a terminal
    // status that reflects reality. Previously the promotion always
    // landed on `complete` no matter how many sends failed.
    let attempted = 0;
    let succeeded = 0;
    let failed = 0;
    let lastErrorMessage: string | null = null;

    for (const custId of promo.customerIds as string[]) {
      try {
        const cSnap = await db
          .collection("users")
          .doc(merchantId)
          .collection("customers")
          .doc(custId)
          .get();
        const cust = cSnap.data();
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

        if (promo.sendWhatsApp && (needsCheck || hasWhatsApp)) {
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
              const waResp = await twilioClient.messages.create({
                to: waTo,
                from: CUSTOMER_WA_SID,
                contentSid: waSid,
                contentVariables: JSON.stringify({
                  customerName: cust.name,
                  shopName: shopName,
                }),
              });
              sentViaWA = true;
              succeeded++;
              totalCost += unitWA;
              await storeWhatsAppCheck(num, true);
              await recordSend(
                merchantId,
                custId,
                num,
                unitWA,
                "whatsapp",
                smsRaw,
                waResp?.sid ?? null,
              );
            } catch (err) {
              await storeWhatsAppCheck(num, false);
              // PAS-WA-01: preserve Twilio detail when present, and
              // fall back to a Pasella-friendly message when it's
              // missing. Persisted under the promotion so support
              // can see why each recipient failed.
              const norm = normalizeTwilioError(err, "whatsapp");
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
          if (!promo.sendWhatsApp || (!needsCheck && !hasWhatsApp)) {
            attempted++;
          }
          const smsBody = smsRaw
            .replaceAll("{{customerName}}", cust.name)
            .replaceAll("{{shopName}}", shopName);
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
              const smsResp = await twilioClient.messages.create({
                to: smsTo,
                from: SMS_NUMBER,
                body: smsBody,
              });
              succeeded++;
              totalCost += smsCost;
              await recordSend(
                merchantId,
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
          (needsCheck || hasWhatsApp)
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
        // failures list with the Pasella fallback message.
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

    // PAS-WA-01: choose a terminal status that reflects what actually
    // happened. `complete` is reserved for "every attempted send
    // succeeded"; mixed outcomes become `partial`; total wipeout
    // becomes `failed`. Existing UI that only branches on
    // `'saved' | 'processing' | other` keeps working (everything else
    // still renders green) but the field is now diagnosable from
    // Firestore and from the promotion detail page going forward.
    let terminalStatus: "complete" | "partial" | "failed";
    if (attempted === 0 || failed === 0) {
      terminalStatus = "complete";
    } else if (succeeded === 0) {
      terminalStatus = "failed";
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
