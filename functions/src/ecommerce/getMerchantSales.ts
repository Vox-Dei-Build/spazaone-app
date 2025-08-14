import { db, functions } from "../config/main";

/**
 * List sales for a merchant. Optionally filter by type (e.g., "Online").
 * Returns: { sales: [{ id, status, amount, itemsCount, type, dateAdded, pickupAt, pickupLabel }] }
 */
export const getMerchantSales = functions.https.onRequest(async (req, res) => {
  try {
    const merchantId = (req.query.merchantId || req.body?.merchantId) as string;
    const type = (req.query.type || req.body?.type) as string | undefined;

    if (!merchantId) {
      res.status(400).json({ error: "merchantId is required" });
      return;
    }

    let query = db
      .collection("users")
      .doc(merchantId)
      .collection("sales")
      .orderBy("dateAdded", "desc")
      .limit(50);

    if (type) {
      query = query.where("type", "==", type);
    }

    const qs = await query.get();

    const sales = qs.docs.map((d) => {
      const s: any = d.data() || {};
      return {
        id: d.id,
        status: s.status || "pending",
        amount: Number(s.amount ?? 0),
        itemsCount: Number(s.itemsCount ?? 0),
        type: s.type || "",
        dateAdded: s.dateAdded || s.createdAt || null,
        pickupAt: s.pickupAt || null,
        pickupLabel: s.pickupLabel || null,
      };
    });

    res.status(200).json({ sales });
  } catch (error: any) {
    console.error("Error fetching sales:", error?.message || error);
    res.status(500).json({ error: "Failed to fetch sales" });
  }
});
