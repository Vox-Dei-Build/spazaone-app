import { db, functions } from "../config/main";
import { presentCommerceOrder } from "../commerce/orderPresentation";
import { requireBotRequest } from "../security/requestAuth";
/**
 * HTTP endpoint to retrieve the status of a sale.
 *
 * @param {functions.https.Request} req Express request containing `merchantId` and `saleId` in query or body.
 * @param {functions.Response} res Express response with sale details.
 * @returns {Promise<void>}
 */

export const getSaleStatus = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    const merchantId = (req.query.merchantId || req.body?.merchantId) as string;
    const saleId = (req.query.saleId || req.body?.saleId) as string;

    if (!merchantId || !saleId) {
      res.status(400).json({ error: "merchantId and saleId are required" });
      return;
    }

    try {
      const saleDoc = await db
        .collection("users")
        .doc(merchantId)
        .collection("sales")
        .doc(saleId)
        .get();

      if (saleDoc.exists) {
        res.status(200).json({
          sale: { ...saleDoc.data(), id: saleDoc.id, source: "legacy" },
        });
        return;
      }

      const commerceDoc = await db.doc(`commerceOrders/${saleId}`).get();
      if (
        commerceDoc.exists &&
        String(commerceDoc.data()?.sellerId ?? "") === merchantId
      ) {
        res.status(200).json({
          sale: presentCommerceOrder(commerceDoc.id, commerceDoc.data()),
        });
        return;
      }

      res.status(404).json({ error: "Sale not found" });
    } catch (error) {
      console.error("Error fetching sale status:", error);
      res.status(500).json({ error: "Failed to fetch sale status" });
    }
  });
