import { db, functions } from "../config/main";

/**
 * List sales for a merchant. Optionally filter by type (e.g., "Online").
 * Returns: { sales: [{ id, status, amount, itemsCount, type, dateAdded, pickupAt, pickupLabel }] }
 */
export const getMerchantSales = functions.https.onCall(async (data) => {
  try {
    const merchantId = data.merchantId as string;
    const type = data.type as string | undefined;

    if (!merchantId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "merchantId is required",
      );
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
        paymentMethod: s.paymentMethod || "", // may be set later by actions
        paymentStatus: s.paymentStatus || "", // "approved" for BNPL approved, "paid" when settled
      };
    });

    return { sales };
  } catch (error: any) {
    console.error("Error fetching sales:", error?.message || error);
    throw new functions.https.HttpsError("internal", "Failed to fetch sales");
  }
});
