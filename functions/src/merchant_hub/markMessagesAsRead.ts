import { functions, db } from "../config/main";

/**
 * Cloud Function: Mar Messages as Read for Merchants
 *
 * @param {functions.https.Request} req - The HTTP request object from Twilio, containing status information.
 * @param {functions.Response} res - The HTTP response object to send back to Twilio.
 */
export const markMessagesAsRead = functions.https.onRequest(
  async (req, res) => {
    try {
      const { merchantId, customerNumber } = req.body;

      if (!merchantId || !customerNumber) {
        res
          .status(400)
          .json({ error: "Merchant ID and Customer Number are required" });
        return;
      }

      const merchantRef = db.collection("users").doc(merchantId);
      const merchantDoc = await merchantRef.get();

      if (!merchantDoc.exists) {
        res.status(404).json({ error: "Merchant not found" });
        return;
      }

      const merchantData = merchantDoc.data();
      const unreadMessages = merchantData?.unreadMessages || [];
      const unreadCount = merchantData?.unreadCount || 0;

      // V1 truth-surface (`fix/pas-wa-v1-bot-message-truth`): outbound bot
      // mirrors share the same array as legacy inbound entries. We only want
      // to "consume" inbound entries on read — outbound mirrors must remain
      // so the merchant can scroll back through what the bot replied even if
      // the live Botpress polling fails. Legacy entries (no `direction`)
      // continue to be treated as inbound for backwards compatibility.
      const isInbound = (msg: any) =>
        msg?.direction == null ||
        String(msg.direction).toLowerCase() === "inbound";

      const digitsOnly = (raw: unknown) =>
        String(raw ?? "").replace(/\D/g, "");
      const matchesCustomer = (stored: unknown, next: unknown) => {
        const a = digitsOnly(stored);
        const b = digitsOnly(next);
        if (!a || !b) return false;
        const len = Math.min(9, a.length, b.length);
        return a.slice(-len) === b.slice(-len);
      };

      let markedMessagesCount = 0;
      const readAt = new Date().toISOString();
      const updatedMessages = unreadMessages.map((msg: any) => {
        if (
          matchesCustomer(msg.customerNumber, customerNumber) &&
          isInbound(msg) &&
          msg?.isRead !== true
        ) {
          markedMessagesCount += 1;
          return {
            ...msg,
            isRead: true,
            readAt,
          };
        }
        return msg;
      });

      if (markedMessagesCount === 0) {
        res
          .status(200)
          .json({ message: "No unread messages for this customer." });
        return;
      }

      // 🔥 Decrement unreadCount based on newly read inbound messages while
      // keeping the truth-surface history visible in the merchant app.
      const newUnreadCount = Math.max(0, unreadCount - markedMessagesCount);

      await merchantRef.update({
        unreadMessages: updatedMessages,
        unreadCount: newUnreadCount,
      });

      res.status(200).json({
        message: `Marked ${markedMessagesCount} messages as read for customer ${customerNumber}.`,
      });
    } catch (error) {
      console.error("Error marking messages as read:", error);
      res.status(500).json({ error: "Internal Server Error" });
    }
  },
);
