import { db, functions } from "../config/main";
import {
  authorizeCallableMerchantOrBot,
  verifyBotRequest,
} from "../security/requestAuth";
import {
  orderCreatedAtMillis,
  presentCommerceOrder,
} from "../commerce/orderPresentation";

/**
 * List orders (sales) for a customer with normalized fields for UI.
 * Returns: { orders: [{ id, status, total, itemsCount, createdAt, items?, ... }] }
 */
export const getCustomerOrders = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onCall(async (data, context) => {
    try {
      const merchantId = data.merchantId as string;
      const customerId = data.customerId as string;

      if (!merchantId || !customerId) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "merchantId and customerId are required",
        );
      }
      if (!(await authorizeCallableMerchantOrBot(context, merchantId))) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Access denied",
        );
      }

      const botRequest = verifyBotRequest(context.rawRequest);
      const qs = await db
        .collection("users")
        .doc(merchantId)
        .collection("sales")
        .where("customerId", "==", customerId)
        .orderBy("dateAdded", "desc")
        .limit(50)
        .get();

      const legacyOrders = qs.docs.map((d) => {
        const s: any = d.data() || {};

        // Normalize counts/amount
        const total = Number(s.amount ?? s.total ?? s.saleTotal ?? 0);
        const itemsCount = Number(
          s.itemsCount ??
            (s.products && typeof s.products === "object"
              ? Object.values(s.products).reduce(
                  (acc: number, q: any) => acc + Number(q || 0),
                  0,
                )
              : 0),
        );

        // --- NEW: collected signals (be generous)
        const statusStr = String(s.status || "").toLowerCase();
        const collectedAt = s.collectedAt || s.fulfilledAt || null;
        const collected =
          s.collected === true || !!collectedAt || statusStr === "collected";

        return {
          id: d.id,
          source: "legacy",
          status: s.status || "pending",
          total,
          itemsCount,
          createdAt: s.dateAdded || s.createdAt || null,
          items: Array.isArray(s.items) ? s.items : undefined,

          type: s.type || "", // "BNPL" | "Cash" | "Online"
          paymentMethod: s.paymentMethod || "",
          paymentStatus: s.paymentStatus || "",

          // --- NEW: expose to client
          collected,
          collectedAt, // Timestamp | string | null
        };
      });

      // The Flutter customer page already subscribes to commerceOrders in
      // real time. Include supplier orders here only for the authenticated
      // WhatsApp backend, otherwise the app would render each order twice.
      const commerceOrders = botRequest
        ? (
            await db
              .collection("commerceOrders")
              .where("sellerId", "==", merchantId)
              .where("customerId", "==", customerId)
              .orderBy("createdAt", "desc")
              .limit(50)
              .get()
          ).docs.map((doc) => presentCommerceOrder(doc.id, doc.data()))
        : [];

      const orders = [...legacyOrders, ...commerceOrders]
        .sort(
          (left, right) =>
            orderCreatedAtMillis(right) - orderCreatedAtMillis(left),
        )
        .slice(0, 50);

      return { orders };
    } catch (error: any) {
      console.error("Error fetching orders:", error?.message || error);
      if (error instanceof functions.https.HttpsError) throw error;
      throw new functions.https.HttpsError(
        "internal",
        "Failed to fetch orders",
      );
    }
  });
