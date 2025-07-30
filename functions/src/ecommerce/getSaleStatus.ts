import { db, functions } from "../config/main";
/**
 * HTTP endpoint to retrieve the status of a sale.
 *
 * @param {functions.https.Request} req Express request containing `merchantId` and `saleId` in query or body.
 * @param {functions.Response} res Express response with sale details.
 * @returns {Promise<void>}
 */

export const getSaleStatus = functions.https.onRequest(async (req, res) => {
  const merchantId = (req.query.merchantId || req.body.merchantId) as string;
  const saleId = (req.query.saleId || req.body.saleId) as string;

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

    if (!saleDoc.exists) {
      res.status(404).json({ error: "Sale not found" });
      return;
    }

    res.status(200).json({ sale: { id: saleDoc.id, ...saleDoc.data() } });
  } catch (error) {
    console.error("Error fetching sale status:", error);
    res.status(500).json({ error: "Failed to fetch sale status" });
  }
});
