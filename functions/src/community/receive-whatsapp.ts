import { functions } from "../config/main";
import MessagingResponse = require("twilio/lib/twiml/MessagingResponse");
import {
  fetchTransactionHistory,
  fetchUserBalance,
} from "../contact/fetchUserBalance";

/**
 * Handles incoming WhatsApp messages via Twilio and responds with a confirmation message.
 *
 * @param {functions.https.Request} req - The HTTP request object.
 * @param {functions.Response} res - The HTTP response object.
 */
export const receiveWhatsappWebhook = functions.https.onRequest((req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const twiml = new MessagingResponse();
  const { Body: userResponse, From } = req.body;

  console.log(`Received from ${From}: ${userResponse}`);

  const menuQuickReplies = ["Check Balance", "View Transaction History"];

  const menuTemplate = {
    body: "Hello! 👋🏾 Welcome to Pasella! I'm here to help you manage your account. What would you like to do?",
    quickReplies: menuQuickReplies,
  };

  const shortMenuTemplate = {
    body: "What would you like to do next?",
    quickReplies: menuQuickReplies,
  };

  const handleResponse = (message: any) => {
    twiml.message(message);
    res.contentType("text/xml");
    res.send(twiml.toString());
  };

  switch (userResponse?.trim().toLowerCase()) {
    case "check balance": // Balance Check
      fetchUserBalance(From)
        .then((balance) =>
          handleResponse({
            body: `${balance}\n\nWhat would you like to do next?`,
            quickReplies: menuQuickReplies,
          }),
        )
        .catch(() =>
          handleResponse({
            body: `${history}\n\nWhat would you like to do next?`,
            quickReplies: menuQuickReplies,
          }),
        );
      break;
    case "view transaction history": // Transactions History
      fetchTransactionHistory(From)
        .then((history) => handleResponse(`${history}\n\n${shortMenuTemplate}`))
        .catch(() => handleResponse("⚠️ Failed to fetch transactions."));
      break;
    default:
      handleResponse(menuTemplate);
      break;
  }
});
