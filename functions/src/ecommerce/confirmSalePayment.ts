import { db, functions } from "../config/main";

export const confirmSalePayment = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const { merchantId, saleId, paymentReference } = req.body;

  if (!merchantId || !saleId) {
    res.status(400).json({ error: "merchantId and saleId are required" });
    return;
  }

  try {
    const saleRef = db
      .collection("users")
      .doc(merchantId)
      .collection("sales")
      .doc(saleId);

    await saleRef.update({ status: "paid", paymentReference });

    res.status(200).json({ success: true });
  } catch (error) {
    console.error("Error confirming payment:", error);
    res.status(500).json({ error: "Failed to confirm payment" });
  }
});
