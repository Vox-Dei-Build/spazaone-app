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

  switch (userResponse.trim()) {
    case "1": // Balance Check
      // Placeholder function to simulate fetching balance
      fetchUserBalance(From)
        .then((balance) => twiml.message(`Your current balance is: ${balance}`))
        .catch(() => twiml.message("Failed to fetch balance."));
      break;
    case "2": // Transactions History
      // Placeholder function to simulate fetching transaction history
      fetchTransactionHistory(From)
        .then((history: any) =>
          twiml.message(`Your recent transactions:\n${history}`),
        )
        .catch(() => twiml.message("Failed to fetch transactions."));
      break;
    default:
      twiml.message(
        "Welcome to Pasella!\n1. Check Balance\n2. View Transactions",
      );
      break;
  }

  res.contentType("text/xml");
  res.send(twiml.toString());
});
