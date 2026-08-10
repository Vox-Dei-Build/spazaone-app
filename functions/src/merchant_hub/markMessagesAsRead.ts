import { functions, db } from "../config/main";
import { markCustomerMessagesRead } from "../notifications/unreadCounts";
import { authenticateFirebaseRequest } from "../security/requestAuth";
import { assertStoreAccess } from "../stores/storeAccess";
import { formatPhoneNumber, normalizePhoneNumber } from "../utils/phoneUtils";

/**
 * Cloud Function: Mar Messages as Read for Merchants
 *
 * @param {functions.https.Request} req - The HTTP request object from Twilio, containing status information.
 * @param {functions.Response} res - The HTTP response object to send back to Twilio.
 */
export const markMessagesAsRead = functions.https.onRequest(
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
      }
      const { merchantId, customerNumber, limit = 200 } = req.body || {};

      if (!merchantId || !customerNumber) {
        res
          .status(400)
          .json({ error: "Merchant ID and Customer Number are required" });
        return;
      }
      const uid = await authenticateFirebaseRequest(req, res, {
        requireAppCheck: true,
      });
      if (!uid) return;
      try {
        await assertStoreAccess(uid, merchantId);
      } catch (error) {
        res.status(403).json({ error: "Access denied." });
        return;
      }

      const merchantRef = db.collection("users").doc(merchantId);
      const merchantDoc = await merchantRef.get();

      if (!merchantDoc.exists) {
        res.status(404).json({ error: "Merchant not found" });
        return;
      }

      const normalized = normalizePhoneNumber(customerNumber);
      const e164 = formatPhoneNumber(customerNumber);
      const numberVariants = [...new Set([normalized, e164].filter(Boolean))];
      const customer = numberVariants.length
        ? await merchantRef
            .collection("customers")
            .where("number", "in", numberVariants)
            .limit(1)
            .get()
        : null;
      const result = await markCustomerMessagesRead({
        merchantId,
        customerId:
          customer && !customer.empty ? customer.docs[0].id : undefined,
        customerNumber,
        limit: Math.max(1, Math.min(Number(limit) || 200, 500)),
      });

      res.status(200).json({
        message:
          result.cleared === 0
            ? "No unread messages for this customer."
            : `Marked ${result.cleared} messages as read for customer ${customerNumber}.`,
        cleared: result.cleared,
        unreadMessagesCount: result.counts.messages,
        unreadTotalCount: result.counts.total,
      });
    } catch (error) {
      console.error("Error marking messages as read:", error);
      res.status(500).json({ error: "Internal Server Error" });
    }
  },
);
