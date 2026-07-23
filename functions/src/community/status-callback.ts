import { functions, db } from "../config/main";
import { FieldValue } from "firebase-admin/firestore";
import {
  campaignWalletContextFromCharge,
  mutateCampaignCredits,
} from "../wallet/campaignCredits";

/**
 * Cloud Function to handle incoming message status updates from Twilio.
 *
 * On `delivered` we record the recipient number in the WA-routing
 * cache (existing behaviour).
 *
 * PAS-WA-01: on `failed`/`undelivered` we now persist the provider's
 * `ErrorCode`/`ErrorMessage` keyed on `MessageSid` so support can
 * correlate them back to the originating promotion/customer (the
 * `messageSid` is stored on each successful `customer_notifications`
 * row by `runMerchantPromotion.recordSend`). Previously the error
 * code/message were only `console.log`'d and lost.
 *
 * @param {functions.https.Request} req - The HTTP request object from Twilio, containing status information.
 * @param {functions.Response} res - The HTTP response object to send back to Twilio.
 */
export const messageStatusCallback = functions.https.onRequest(
  async (req, res) => {
    const messageSid = req.body.MessageSid as string;
    const messageStatus = req.body.MessageStatus as string;
    const toNumber = (req.body.To as string) ?? "";
    const errorCodeRaw = req.body.ErrorCode as string | undefined;
    const errorMessageRaw = req.body.ErrorMessage as string | undefined;

    console.log(`Message SID: ${messageSid}`);
    console.log(`Message Status: ${messageStatus}`);
    console.log(`Error Code: ${errorCodeRaw ?? "None"}`);
    console.log(`Error Message: ${errorMessageRaw ?? "None"}`);

    const isWhatsApp = toNumber.startsWith("whatsapp:");

    if (messageStatus === "delivered" && isWhatsApp) {
      const normalizedNumber = toNumber.replace("whatsapp:+27", "0"); // Normalize WhatsApp number to local format

      const successfulWhatsAppRef = db.collection("successfulWhatsAppNumbers");

      try {
        // Check if the phone number is already in Firestore
        const existingNumberSnapshot = await successfulWhatsAppRef
          .where("phoneNumber", "==", normalizedNumber)
          .limit(1)
          .get();

        const capabilityData = {
          phoneNumber: normalizedNumber,
          hasWhatsApp: true,
          messageSid,
          lastChecked: FieldValue.serverTimestamp(),
          timestamp: FieldValue.serverTimestamp(),
        };

        // If the number doesn't exist, add it to Firestore
        if (existingNumberSnapshot.empty) {
          await successfulWhatsAppRef.add(capabilityData);
          console.log(
            `Successfully stored delivered WhatsApp number: ${normalizedNumber}`,
          );
        } else {
          await existingNumberSnapshot.docs[0].ref.set(capabilityData, {
            merge: true,
          });
          console.log(
            `Refreshed delivered WhatsApp number: ${normalizedNumber}.`,
          );
        }
      } catch (error) {
        console.error(
          `Failed to store WhatsApp number ${normalizedNumber}:`,
          error,
        );
      }
    } else if (messageStatus === "failed" || messageStatus === "undelivered") {
      // PAS-WA-01: persist the failure so support has something to
      // query. We always write — even when ErrorCode/ErrorMessage
      // are absent — so a "we know it failed but Twilio gave no
      // detail" state is visible rather than silently dropped.
      const providerCode =
        errorCodeRaw && errorCodeRaw.trim() !== "" ? errorCodeRaw : null;
      const providerMessage =
        errorMessageRaw && errorMessageRaw.trim() !== ""
          ? errorMessageRaw
          : null;

      let pasellaMessage: string;
      let fallbackUsed = false;
      if (providerMessage && providerCode) {
        pasellaMessage = `Delivery ${messageStatus} (Twilio ${providerCode}): ${providerMessage}`;
      } else if (providerMessage) {
        pasellaMessage = `Delivery ${messageStatus}: ${providerMessage}`;
      } else if (providerCode) {
        pasellaMessage = `Delivery ${messageStatus} (Twilio ${providerCode}). No further detail returned by provider.`;
      } else {
        fallbackUsed = true;
        pasellaMessage = `Delivery ${messageStatus} — no provider error detail returned. Treat as transient; retry if needed, then contact support if it persists.`;
      }

      try {
        await db.collection("messageDeliveryFailures").add({
          messageSid,
          to: toNumber,
          status: messageStatus,
          providerCode,
          providerMessage,
          pasellaMessage,
          fallbackUsed,
          timestamp: FieldValue.serverTimestamp(),
        });
        console.log(
          `Recorded delivery failure for ${messageSid}: ${pasellaMessage}`,
        );

        // Some SMS carriers stop at Twilio's `sent` state because they do not
        // provide delivery receipts. If a late terminal failure later arrives,
        // refund the charge exactly once. The wallet and tracking document are
        // updated together so duplicate callbacks cannot double-refund.
        const chargeRef = db
          .collection("messageDeliveryCharges")
          .doc(messageSid);
        await db.runTransaction(async (tx) => {
          const chargeSnap = await tx.get(chargeRef);
          const charge = chargeSnap.data();
          if (!chargeSnap.exists || charge?.refunded === true) return;

          const merchantId = String(charge?.merchantId ?? "");
          const walletStoreId = String(charge?.walletStoreId ?? merchantId);
          const cost = Number(charge?.cost ?? 0);
          if (
            !merchantId ||
            !walletStoreId ||
            !Number.isFinite(cost) ||
            cost <= 0
          ) {
            return;
          }

          const walletContext = campaignWalletContextFromCharge(
            merchantId,
            walletStoreId,
            charge?.sharedCampaignCredits === true,
          );
          await mutateCampaignCredits(tx, walletContext, cost, {
            id: `refund:${messageSid}`,
            kind: "promotion-refund",
            metadata: {
              messageSid,
              status: messageStatus,
              providerCode,
            },
          });
          tx.set(
            chargeRef,
            {
              refunded: true,
              refundedAt: FieldValue.serverTimestamp(),
              refundStatus: messageStatus,
              refundProviderCode: providerCode,
            },
            { merge: true },
          );
        });
      } catch (error) {
        console.error(
          `Failed to persist delivery failure for ${messageSid}:`,
          error,
        );
      }
    }

    res.status(200).end(); // Respond with 200 status to acknowledge receipt
  },
);
