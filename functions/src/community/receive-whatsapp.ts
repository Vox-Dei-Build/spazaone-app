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

  console.log(From);
  console.log(userResponse);

  const handleResponse = (message: string) => {
    twiml.message(message);
    res.contentType("text/xml");
    res.send(twiml.toString());
  };

  switch (userResponse?.trim()) {
    case "1": // Balance Check
      fetchUserBalance(From)
        .then((balance) => handleResponse(`${balance}`))
        .catch(() => handleResponse("Failed to fetch balance."));
      break;
    case "2": // Transactions History
      fetchTransactionHistory(From)
        .then((history) => handleResponse(`${history}`))
        .catch(() => handleResponse("Failed to fetch transactions."));
      break;
    default:
      handleResponse(
        "Hello 👋🏾\n\n1. Check Your Balance\n2. View Your Recent Transactions",
      );
      break;
  }
});
