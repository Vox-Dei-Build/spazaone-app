import { functions, db } from "../config/main";
import { normalizePhoneNumber } from "../contact/fetchUserBalance";

function asMoney(value: unknown): number {
  const n = Number(value ?? 0);
  return Number.isFinite(n) ? n : 0;
}

export const getAccountSummaryBotHttp = functions.https.onRequest(
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const { customerPhone, merchantId: requestedMerchantId } = req.body ?? {};
    if (!customerPhone) {
      res.status(400).json({ error: "customerPhone is required" });
      return;
    }

    const normalizedNumber = normalizePhoneNumber(
      String(customerPhone).replace("whatsapp:", ""),
    );

    try {
      const customersSnap = await db
        .collectionGroup("customers")
        .where("number", "==", normalizedNumber)
        .get();

      const accounts = [];
      let totalBalance = 0;

      for (const customerDoc of customersSnap.docs) {
        const pathSegments = customerDoc.ref.path.split("/");
        const merchantId = pathSegments[1];
        if (requestedMerchantId && merchantId !== requestedMerchantId) continue;

        const customer = customerDoc.data() ?? {};
        const merchantDoc = await db.collection("users").doc(merchantId).get();
        const merchant = merchantDoc.data() ?? {};
        const balance = asMoney(customer.balance);
        totalBalance += balance;

        accounts.push({
          merchantId,
          customerId: customerDoc.id,
          merchantName: String(merchant.name ?? ""),
          shopName: String(merchant.shopName ?? merchant.name ?? "the shop"),
          balance,
        });
      }

      res.status(200).json({
        customerPhone: normalizedNumber,
        generatedAt: new Date().toISOString(),
        totalBalance,
        accounts,
      });
    } catch (error) {
      console.error("Failed to fetch bot account summary:", error);
      res.status(500).json({ error: "Failed to fetch account summary" });
    }
  },
);
