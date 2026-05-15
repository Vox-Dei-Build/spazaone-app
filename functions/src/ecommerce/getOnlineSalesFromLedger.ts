// functions/src/http/getOnlineSalesFromLedger.ts
import { db, functions } from "../config/main";
import { FieldPath } from "firebase-admin/firestore";

type AnyMap = { [k: string]: any };

const tsToMillis = (v: any): number => {
  if (!v) return 0;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (typeof v.seconds === "number") return v.seconds * 1000;
  const n = new Date(v).getTime();
  return Number.isFinite(n) ? n : 0;
};

/**
 * getOnlineSalesFromLedger
 * ------------------------
 * HTTP endpoint that lists recent **online sales** using the `salesLedger` (Paystack)
 * as the source of truth for **fees** and **net amounts**, and joins basic order info
 * from `users/{merchantId}/sales/{saleId}` when available.
 *
 * @function getOnlineSalesFromLedger
 * @type {import('firebase-functions').HttpsFunction}
 * @summary List online sales from Paystack ledger (with fees & net), joined to sales.
 *
 * @param {import('firebase-functions').Request} req
 *   HTTP POST request. Accepts JSON body either as raw fields or inside `{ data: {...} }`
 *   (so it’s compatible with callable-style bodies you might send from Postman).
 *
 * @param {import('firebase-functions').Response} res
 *   HTTP response with JSON `{ sales: LedgerSale[] }`.
 *
 * @typedef LedgerSale
 * @property {string}  id                - Sale ID (or ledger doc id if sale missing)
 * @property {string}  reference         - Provider reference (Paystack)
 * @property {string}  status            - Order status (from sale; defaults to "paid")
 * @property {string}  paymentMethod     - Usually "Online"
 * @property {string}  paymentStatus     - Usually "paid"
 * @property {number}  itemsCount        - Count from sale (fallback 0)
 * @property {any}     createdAt         - Preferred sale date (Firestore Timestamp | ISO | null)
 * @property {any}     ledgerCreatedAt   - Ledger createdAt (Timestamp | ISO | null)
 * @property {number}  orderTotal        - Order value from sale (fallback to amountPaid)
 * @property {number}  amountPaid        - What customer paid (from ledger; includes fee)
 * @property {number}  feeExVat          - Provider fee excluding VAT
 * @property {number}  feeInclVat        - Provider fee including VAT
 * @property {number}  netAmount         - Credited amount after fees
 * @property {string}  currency          - Currency code, default "ZAR"
 * @property {string}  method            - Method used (e.g., "eft", "local_card")
 * @property {string}  channel           - Paystack channel (e.g., "eft", "card")
 *
 * @requestBody
 * ```json
 * {
 *   "merchantId": "USER_ID",       // required
 *   "limit": 100,                  // optional (default 100, max 200)
 *   "startDate": "2025-08-01",     // optional (ISO; inclusive)
 *   "endDate":   "2025-08-28"      // optional (ISO; inclusive; server uses end+1 day exclusive)
 * }
 * ```
 * (You can also wrap those fields under `{ "data": { ... } }`.)
 *
 * @response 200 - OK
 * ```json
 * {
 *   "sales": [
 *     {
 *       "id": "KzF6Qk0At4VGqagPkVLQ",
 *       "reference": "649nisajhv",
 *       "status": "collected",
 *       "paymentMethod": "Online",
 *       "paymentStatus": "paid",
 *       "itemsCount": 2,
 *       "createdAt": { "seconds": 1693188182, "nanoseconds": 0 },
 *       "ledgerCreatedAt": { "seconds": 1693188182, "nanoseconds": 0 },
 *       "orderTotal": 4000,
 *       "amountPaid": 4092,
 *       "feeExVat": 81.84347826086957,
 *       "feeInclVat": 94.12,
 *       "netAmount": 3997.88,
 *       "currency": "ZAR",
 *       "method": "eft",
 *       "channel": "eft"
 *     }
 *   ]
 * }
 * ```
 *
 * @response 400 - Missing merchantId
 * ```json
 * { "error": "merchantId is required" }
 * ```
 *
 * @response 500 - Server error
 * ```json
 * { "error": "Failed to fetch online sales from ledger" }
 * ```
 *
 * @example cURL
 * curl -X POST \
 *  "https://us-central1-YOUR_PROJECT.cloudfunctions.net/getOnlineSalesFromLedger" \
 *  -H "Content-Type: application/json" \
 *  -d '{ "merchantId": "USER_ID", "limit": 50 }'
 */
export const getOnlineSalesFromLedger = functions.https.onRequest(
  async (req, res) => {
    try {
      if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
      }

      const body: AnyMap = req.body || {};
      const data: AnyMap =
        body?.data && typeof body.data === "object" ? body.data : body;

      const merchantId = String(data.merchantId || "");
      const limit = Math.min(Number(data.limit ?? 100), 200);
      const startIso = data.startDate as string | undefined;
      const endIso = data.endDate as string | undefined;
      const orderId = String(data.orderId || "");
      const referenceFilter = String(data.reference || "");

      if (!merchantId) {
        res.status(400).json({ error: "merchantId is required" });
        return;
      }

      const ledgerCol = db
        .collection("users")
        .doc(merchantId)
        .collection("salesLedger");

      let ledgerDocs: FirebaseFirestore.DocumentSnapshot[] = [];
      if (referenceFilter) {
        const refSnap = await ledgerCol.doc(referenceFilter).get();
        ledgerDocs = refSnap.exists ? [refSnap] : [];
      } else if (orderId) {
        const bySale = await ledgerCol.where("saleId", "==", orderId).get();
        ledgerDocs = bySale.docs;
      } else {
        const ledSnap = await ledgerCol
          .where("provider", "==", "paystack")
          .orderBy("createdAt", "desc")
          .limit(limit)
          .get();
        ledgerDocs = ledSnap.docs;
      }

      let rows = ledgerDocs.map((d) => {
        const x: AnyMap = d.data() || {};
        return {
          _refId: d.id,
          saleId: String(x.saleId || ""),
          reference: String(x.reference || ""),
          provider: String(x.provider || "paystack"),
          amountPaid: Number(x.amount ?? 0),
          feeExVat: Number(x.feeExVat ?? 0),
          feeInclVat: Number(x.feeInclVat ?? Number(x.fee ?? 0)),
          netAmount: Number(x.netAmount ?? 0),
          method: String(x.method || x.methodUsed || ""),
          channel: String(x.channel || ""),
          createdAt: x.createdAt || x.paidAt || null,
        };
      });

      if (orderId) rows = rows.filter((r) => r.saleId === orderId);
      if (referenceFilter) {
        rows = rows.filter(
          (r) =>
            r.reference === referenceFilter || r._refId === referenceFilter,
        );
      }

      if (startIso || endIso) {
        const start = startIso ? new Date(startIso) : null;
        const end = endIso ? new Date(endIso) : null;
        const endPlus = end
          ? new Date(end.getTime() + 24 * 60 * 60 * 1000)
          : null;
        rows = rows.filter((r) => {
          const t = tsToMillis(r.createdAt);
          if (!t) return false;
          if (start && t < start.getTime()) return false;
          if (endPlus && t >= endPlus.getTime()) return false;
          return true;
        });
      }

      // Join minimal sale info
      const saleIds = Array.from(
        new Set(rows.map((r) => r.saleId).filter(Boolean)),
      );
      const joined: Record<string, AnyMap> = {};
      for (let i = 0; i < saleIds.length; i += 10) {
        const chunk = saleIds.slice(i, i + 10);
        const snap = await db
          .collection("users")
          .doc(merchantId)
          .collection("sales")
          .where(FieldPath.documentId(), "in", chunk)
          .get();
        for (const d of snap.docs) joined[d.id] = d.data() || {};
      }

      const sales = rows
        .map((r) => {
          const s = joined[r.saleId] || {};
          const orderTotal =
            Number(s.total ?? s.amount ?? s.saleTotal ?? 0) || r.amountPaid;
          const itemsCount = Number(
            s.itemsCount ??
              (s.products && typeof s.products === "object"
                ? Object.values(s.products).reduce(
                    (acc: number, q: any) => acc + Number(q || 0),
                    0,
                  )
                : 0),
          );
          return {
            id: r.saleId || r._refId,
            reference: r.reference,
            status: String(s.status || "paid"),
            paymentMethod: String(s.paymentMethod || "Online"),
            paymentStatus: String(s.paymentStatus || "paid"),
            itemsCount,
            createdAt: s.dateAdded || s.createdAt || r.createdAt || null,
            ledgerCreatedAt: r.createdAt || null,
            orderTotal,
            amountPaid: r.amountPaid,
            feeExVat: r.feeExVat,
            feeInclVat: r.feeInclVat,
            netAmount: r.netAmount,
            currency: String(s.currency || "ZAR"),
            method: r.method,
            channel: r.channel,
          };
        })
        .sort((a, b) => {
          const at = tsToMillis(a.createdAt) || tsToMillis(a.ledgerCreatedAt);
          const bt = tsToMillis(b.createdAt) || tsToMillis(b.ledgerCreatedAt);
          return bt - at;
        });

      res.status(200).json({ sales });
    } catch (err: any) {
      console.error("getOnlineSalesFromLedger error:", err?.message || err);
      res
        .status(500)
        .json({ error: "Failed to fetch online sales from ledger" });
    }
  },
);
