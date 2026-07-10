import { functions } from "../config/main"; // Assuming functions is a Firebase or GCP cloud function import
import twilio from "twilio/lib/index";

/**
 * Google Cloud Function to send a Twilio message using a template ID.
 * This function sends a WhatsApp or SMS message using a pre-approved Twilio template.
 *
 * @function sendTwilioMessage
 * @param {functions.https.Request} req - The HTTP request object from the client. Expects `to`, `templateId`, and optionally `templateParams` in the request body.
 * @param {string} req.body.to - The recipient's phone number (e.g., for WhatsApp: 'whatsapp:+123456789').
 * @param {string} req.body.templateId - The template ID (Content SID) of the pre-approved Twilio template.
 * @param {string} [req.body.templateParams] - Optional parameters to replace placeholders in the template message.
 * @param {string} [req.body.botType] - Optional parameters to replace placeholders in the template message.
 * @param {functions.Response} res - The HTTP response object sent back to the client.
 * @returns {void | Promise<void>} - Sends a JSON response indicating success or failure.
 *
 * @example
 * // Example request body to send a message
 * {
 *   "to": "+27123456789",
 *   "templateId": "your-template-id",
 *   "templateParams": "Hello, {{name}}, your order {{order_number}} has been confirmed."
 *   "botType": "Merchant"
 * }
 */
exports.sendTwilioMessage = functions.https.onRequest(async (req, res) => {
  // Extract phone number, template ID, and optional template parameters from the request
  const { to, templateId, templateParams, botType } = req.body;

  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  const messagingServiceID =
    botType === "Merchant"
      ? process.env.TWILIO_MERCHANT_MESSAGING_SERVICE_SID
      : process.env.TWILIO_CUSTOMER_MESSAGING_SERVICE_SID;
  const client = twilio(accountSid, authToken);

  console.log(to);
  console.log(templateId);
  console.log(JSON.stringify(templateParams));

  // Validate the required fields
  if (!to || !templateId) {
    res
      .status(400)
      .json({ error: "Please provide a valid phone number and template ID." });
    return;
  }

  try {
    // Sending the template-based message using Twilio API
    let messageResponse;
    if (templateParams != null) {
      messageResponse = await client.messages.create({
        to: to, // Phone number to send the message to (WhatsApp/SMS)
        messagingServiceSid: messagingServiceID,
        contentVariables: templateParams ? JSON.stringify(templateParams) : "", // Template params for dynamic placeholders
        contentSid: templateId, // The template ID (Content SID) for the pre-approved message template
      });
    } else {
      messageResponse = await client.messages.create({
        to: to, // Phone number to send the message to (WhatsApp/SMS)
        messagingServiceSid: messagingServiceID,
        contentSid: templateId, // The template ID (Content SID) for the pre-approved message template
      });
    }

    // Respond with success without returning the response object
    res.status(200).json({
      success: true,
      message: "Message sent successfully using the template!",
      sid: messageResponse.sid, // Twilio message ID
    });
  } catch (error) {
    // Handle error and respond
    console.error("Failed to send message", error);
    res.status(500).json({
      success: false,
      error: "Failed to send message",
      details: error,
    });
  }
});
