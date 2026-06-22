// functions/src/http/fetchMerchantCandidates.ts
import { functions, db } from "../config/main";
import { normalizePhoneNumber } from "..";

interface MerchantCandidate {
  merchantId: string;
  customerId: string;
  merchantName: string;
  shopName: string;
  merchantNumber: string;
  // optional metadata for ranking and display
  lastUpdated?: Date | null;
  lastTransactionDate?: Date | null;
  // optional routing info if you map Twilio numbers per merchant
  businessWhatsAppNumber?: string | null;
}

/**
 * GET fetchMerchantCandidates?number=whatsapp:+27xxxx&activeTo=+27YY... (optional)
 * Returns a ranked list of merchant candidates for a given customer phone number.
 * If activeTo (Twilio/WhatsApp business number the user messaged) matches a merchant,
 * that merchant is boosted to the top.
 */
export const fetchMerchantCandidates = functions.https.onRequest(
  async (req, res) => {
    try {
      const raw = (req.query.number as string) || "";
      const activeTo = (req.query.activeTo as string) || ""; // optional
      if (!raw) {
        res.status(400).send("Query param 'number' is required.");
        return;
      }

      const normalized = normalizePhoneNumber(raw.replace("whatsapp:", ""));
      const customersRef = db.collectionGroup("customers");
      const snap = await customersRef.where("number", "==", normalized).get();

      if (snap.empty) {
        res.status(404).send("No customers found with this number.");
        return;
      }

      const candidates: MerchantCandidate[] = [];
      // track max dates for ranking heuristics
      const pushCandidate = (c: MerchantCandidate) => {
        // avoid dupes if customer appears under multiple merchants
        if (!candidates.some((x) => x.merchantId === c.merchantId)) {
          candidates.push(c);
        }
      };

      // Walk each customer doc to collect its parent merchant (user)
      await Promise.all(
        snap.docs.map(async (customerDoc: any) => {
          const customer = customerDoc.data();
          const lastTx = customer?.lastTransaction?.date?.toDate?.() ?? null;

          const pathSegments = customerDoc.ref.path.split("/");
          // pattern users/{userId}/customers/{customerId}
          const userId = pathSegments[1];
          const userRef = db.collection("users").doc(userId);
          const userDoc = await userRef.get();
          if (!userDoc.exists) return;

          const u = userDoc.data() || {};
          const lastUpdated = u?.balanceData?.lastUpdated?.toDate?.() ?? null;

          pushCandidate({
            merchantId: userId,
            customerId: customerDoc.id,
            merchantName: u?.name || "Unknown Merchant",
            shopName: u?.shopName || "Unknown Shop",
            merchantNumber: u?.mobileNumber || "",
            lastUpdated,
            lastTransactionDate: lastTx,
            businessWhatsAppNumber: u?.whatsappBusinessNumber || null, // optional field you set per merchant
          });
        }),
      );

      if (candidates.length === 0) {
        res.status(404).send("No merchant candidates found.");
        return;
      }

      // Ranking: 1) hard match on activeTo, 2) lastTransactionDate desc, 3) lastUpdated desc, 4) shopName asc
      candidates.sort((a, b) => {
        const hardA =
          a.businessWhatsAppNumber &&
          activeTo &&
          a.businessWhatsAppNumber === activeTo
            ? 1
            : 0;
        const hardB =
          b.businessWhatsAppNumber &&
          activeTo &&
          b.businessWhatsAppNumber === activeTo
            ? 1
            : 0;
        if (hardA !== hardB) return hardB - hardA;

        const lta = a.lastTransactionDate?.getTime?.() ?? 0;
        const ltb = b.lastTransactionDate?.getTime?.() ?? 0;
        if (lta !== ltb) return ltb - lta;

        const lua = a.lastUpdated?.getTime?.() ?? 0;
        const lub = b.lastUpdated?.getTime?.() ?? 0;
        if (lua !== lub) return lub - lua;

        return (a.shopName || "").localeCompare(b.shopName || "");
      });

      res.status(200).json({
        number: normalized,
        activeTo: activeTo || null,
        candidates,
      });
    } catch (e) {
      console.error(e);
      res.status(500).send("Failed to fetch merchant candidates.");
    }
  },
);
