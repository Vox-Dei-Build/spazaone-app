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

  const menuTemplate =
    "Hello! 👋🏾 Welcome to Pasella! I'm here to help you manage your account, check your balance, view your recent transactions, and more.\n\n🔍 Main Menu:\n1️⃣ Check Balance\n2️⃣ View Transaction History\n\n🚀 Exciting features coming soon, like ordering via WhatsApp, discounts, and promotions!\n\nPlease reply with the number of the option you want to explore.";
  const shortMenuTemplate =
    "🔍 Main Menu:\n1️⃣ Check Balance\n2️⃣ View Transaction History\n\nPlease reply with the number of the option you want to explore.";

  const handleResponse = (message: string) => {
    twiml.message(message);
    res.contentType("text/xml");
    res.send(twiml.toString());
  };

  switch (userResponse?.trim()) {
    case "1": // Balance Check
      fetchUserBalance(From)
        .then((balance) => handleResponse(`${balance}\n\n${shortMenuTemplate}`))
        .catch(() => handleResponse("⚠️ Failed to fetch balance."));
      break;
    case "2": // Transactions History
      fetchTransactionHistory(From)
        .then((history) => handleResponse(`${history}\n\n${shortMenuTemplate}`))
        .catch(() => handleResponse("⚠️ Failed to fetch transactions."));
      break;
    default:
      handleResponse(menuTemplate);
      break;
  }
});
