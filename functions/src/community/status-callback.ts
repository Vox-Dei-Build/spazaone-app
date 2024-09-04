import { functions } from "../config/main";

/**
 * Cloud Function to handle incoming message status updates from Twilio.
 * This function logs the status of the message, including any error codes and messages.
 *
 * @param {functions.https.Request} req - The HTTP request object from Twilio, containing status information.
 * @param {functions.Response} res - The HTTP response object to send back to Twilio.
 */
export const messageStatusCallback = functions.https.onRequest((req, res) => {
  const messageSid = req.body.MessageSid as string;
  const messageStatus = req.body.MessageStatus as string;
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

  res.status(200).end(); // Respond with 200 status to acknowledge receipt
});
