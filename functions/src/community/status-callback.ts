import { functions, db } from "../config/main";
import { FieldValue } from "firebase-admin/firestore";

/**
 * Cloud Function to handle incoming message status updates from Twilio.
 * This function logs the status of the message, including any error codes and messages,
 * and stores the phone number in Firestore if the message was successfully delivered.
 *
 * @param {functions.https.Request} req - The HTTP request object from Twilio, containing status information.
 * @param {functions.Response} res - The HTTP response object to send back to Twilio.
 */
export const messageStatusCallback = functions.https.onRequest(
  async (req, res) => {
    const messageSid = req.body.MessageSid as string;
    const messageStatus = req.body.MessageStatus as string;
    const toNumber = req.body.To as string; // The recipient's phone number (WhatsApp format)
    const errorCode = req.body.ErrorCode
      ? (req.body.ErrorCode as string)
      : "None";
    const errorMessage = req.body.ErrorMessage
      ? (req.body.ErrorMessage as string)
      : "None";

    console.log(`Message SID: ${messageSid}`);
    console.log(`Message Status: ${messageStatus}`);
    console.log(`Error Code: ${errorCode}`);
    console.log(`Error Message: ${errorMessage}`);

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
    }

    res.status(200).end(); // Respond with 200 status to acknowledge receipt
  },
);
