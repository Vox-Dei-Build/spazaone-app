// functions/src/merchant_hub/runMerchantPromotion.ts

import { functions, db } from "../config/main";
import twilio from "twilio";
import { FieldValue } from "firebase-admin/firestore";
import { DynamicPricingService } from "../services/dynamic_pricing_service";

const {
  sid: ACCOUNT_SID,
  token: AUTH_TOKEN,
  customer_messaging_service_sid: CUSTOMER_WA_SID,
  number: SMS_NUMBER,
} = functions.config().twilio;

/**
 * Normalize any South African‐style phone number into the local 0XXXXXXXXX form.
 *
 * @param {string} rawNumber - The raw input, e.g. "+27 82 123 4567" or "0821234567".
 * @return {string} A local‑format number, e.g. "0821234567", or empty string if invalid.
 */
function normalizePhoneNumber(rawNumber: string): string {
  if (!rawNumber) return "";
  // Strip non‑digits
  let digits = rawNumber.replace(/\D/g, "");
  // If it starts with '27', drop that and prepend '0'
  if (digits.startsWith("27")) {
    digits = "0" + digits.slice(2);
  }
  // If it doesn't start with '0', take last 9 digits (in case someone passed e.g. '820123456')
  else if (!digits.startsWith("0")) {
    digits = "0" + digits.slice(-9);
  }
  return digits;
}

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
 * @return {Promise<void>} - Resolves when done.
 */
async function recordSend(
  merchantId: string,
  customerId: string,
  phone: string,
  cost: number,
  channel: "whatsapp" | "sms",
  logMsg: string,
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

        // Normalize
        let num = cust.number.replace(/\D/g, "");
        if (num.startsWith("0")) num = "+27" + num.slice(1);
        else if (num.startsWith("27")) num = "+" + num;
        const waTo = `whatsapp:${num}`;
        const smsTo = num;

        // WhatsApp TTL logic
        const { hasWhatsApp, lastChecked } = await fetchWhatsAppStatus(num);
        const days = lastChecked
          ? (Date.now() - lastChecked.getTime()) / 86400000
          : Infinity;
        const needsCheck = days > 30;

        let sentViaWA = false;

        if (promo.sendWhatsApp && (needsCheck || hasWhatsApp)) {
          console.log(
            `[WA] ${custId} ➡️ trying WA (needsCheck=${needsCheck}, has=${hasWhatsApp})`,
          );
          if (!promo.testMode) {
            try {
              await twilioClient.messages.create({
                to: waTo,
                from: CUSTOMER_WA_SID,
                contentSid: waSid,
                contentVariables: JSON.stringify({
                  "1": cust.name,
                  "2": shopName,
                }),
              });
              sentViaWA = true;
              totalCost += unitWA;
              await storeWhatsAppCheck(num, true);
              await recordSend(
                merchantId,
                custId,
                num,
                unitWA,
                "whatsapp",
                smsRaw,
              );
            } catch (err) {
              await storeWhatsAppCheck(num, false);
              console.warn(`[WA] ${custId} failed, fallback to SMS`);
            }
          } else {
            // Test mode
            sentViaWA = true;
            totalCost += unitWA;
            await storeWhatsAppCheck(num, true);
            console.log(`[TEST] WA ${custId} @ R${unitWA}`);
          }
        }

        // SMS fallback
        if (!sentViaWA && promo.sendSMS) {
          const smsBody = smsRaw
            .replaceAll("{{customerName}}", cust.name)
            .replaceAll("{{shopName}}", shopName);
          console.log(`[SMS] ${custId} ➡️ trying SMS @ R${unitSMS}`);
          if (!promo.testMode) {
            await twilioClient.messages.create({
              to: smsTo,
              from: SMS_NUMBER,
              body: smsBody,
            });
            totalCost += unitSMS;
            await recordSend(merchantId, custId, num, unitSMS, "sms", smsRaw);
          } else {
            totalCost += unitSMS;
            console.log(`[TEST] SMS ${custId} @ R${unitSMS}`, smsBody);
          }
        }
      } catch (e) {
        console.error(`Error sending to ${custId}:`, e);
      }
    }

    console.log(`[PROMO] ${promotionId} complete, totalCost=R${totalCost}`);
    await promoRef.update({
      status: "complete",
      completedAt: FieldValue.serverTimestamp(),
      actualCost: totalCost,
    });

    return { success: true };
  },
);
