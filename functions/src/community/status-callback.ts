import { functions, db } from "../config/main";
import { FieldValue } from "firebase-admin/firestore";

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

    if (messageStatus === "delivered") {
      const normalizedNumber = toNumber.replace("whatsapp:+27", "0"); // Normalize WhatsApp number to local format

      const successfulWhatsAppRef = db.collection("successfulWhatsAppNumbers");

      try {
        // Check if the phone number is already in Firestore
        const existingNumberSnapshot = await successfulWhatsAppRef
          .where("phoneNumber", "==", normalizedNumber)
          .limit(1)
          .get();

        // If the number doesn't exist, add it to Firestore
        if (existingNumberSnapshot.empty) {
          await successfulWhatsAppRef.add({
            phoneNumber: normalizedNumber,
            messageSid: messageSid, // Optional: Store the Twilio MessageSid
            timestamp: FieldValue.serverTimestamp(),
          });
          console.log(
            `Successfully stored delivered WhatsApp number: ${normalizedNumber}`,
          );
        } else {
          console.log(
            `WhatsApp number ${normalizedNumber} already exists, skipping.`,
          );
        }
      } catch (error) {
        console.error(
          `Failed to store WhatsApp number ${normalizedNumber}:`,
          error,
        );
      }
    } else if (
      messageStatus === "failed" ||
      messageStatus === "undelivered"
    ) {
      // PAS-WA-01: persist the failure so support has something to
      // query. We always write — even when ErrorCode/ErrorMessage
      // are absent — so a "we know it failed but Twilio gave no
      // detail" state is visible rather than silently dropped.
      const providerCode = errorCodeRaw && errorCodeRaw.trim() !== ""
        ? errorCodeRaw
        : null;
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
