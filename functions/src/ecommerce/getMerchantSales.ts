// functions/src/http/getMerchantSales.ts
import { db, functions } from "../config/main";
import {
  FieldPath,
  Query,
  QueryDocumentSnapshot,
  DocumentData,
} from "firebase-admin/firestore";
import { authorizeCallableMerchantOrBot } from "../security/requestAuth";

const tsToMillis = (v: any): number => {
  if (!v) return 0;
  if (typeof v.toMillis === "function") return v.toMillis();
  if (typeof v.seconds === "number") return v.seconds * 1000;
  const n = new Date(v).getTime();
  return Number.isFinite(n) ? n : 0;
};

/**
 * List sales with optional Online/Cash filtering and ledger fallback for Online.
 *
 * data:
 *  - merchantId: string
 *  - paymentMethod?: "Online" | "Cash"  (preferred)
 *  - type?: string                      (legacy)
 *  - limit?: number                     (default 50, max 200)
 */
export const getMerchantSales = functions.https.onCall(
  async (data, context) => {
    try {
      const merchantId = String(data.merchantId || "");
      const methodParam = (data.paymentMethod as string | undefined)?.trim();
      const typeParam = (data.type as string | undefined)?.trim();
      const pageLimit = Math.min(Number(data.limit ?? 50), 200);

      if (!merchantId) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "merchantId is required",
        );
      }
      if (!(await authorizeCallableMerchantOrBot(context, merchantId))) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "Access denied",
        );
      }

      const requested = (methodParam || typeParam || "").toLowerCase();
      const wantOnline = requested === "online";
      const wantCash = requested === "cash";

      const colRef = db.collection("users").doc(merchantId).collection("sales");
      let q: Query<DocumentData> = colRef;

      if (wantOnline) {
        q = q.where("paymentMethod", "==", "Online");
      } else if (wantCash) {
        q = q.where("paymentMethod", "==", "Cash");
      } else if (typeParam && !methodParam) {
        q = q.where("type", "==", typeParam);
      }

      // Get docs (ordered if index exists, else fallback + sort in-memory)
      let docs: QueryDocumentSnapshot<DocumentData>[];
      try {
        const s = await q.orderBy("dateAdded", "desc").limit(pageLimit).get();
        docs = s.docs;
      } catch {
        const s = await q.limit(pageLimit).get();
        docs = [...s.docs].sort((a, b) => {
          const at = tsToMillis(a.get("dateAdded") ?? a.get("createdAt"));
          const bt = tsToMillis(b.get("dateAdded") ?? b.get("createdAt"));
          return bt - at;
        });
      }

      // Map & normalize
      let sales = docs.map((d) => {
        const s: any = d.data() || {};
        const total = Number(s.total ?? s.amount ?? s.saleTotal ?? 0);
        const date =
          s.dateAdded ?? s.createdAt ?? s.paidAt ?? s.updatedAt ?? null;

        return {
          id: d.id,
          status: String(s.status ?? "pending"),
          total,
          itemsCount: Number(
            s.itemsCount ??
              (s.products && typeof s.products === "object"
                ? Object.values(s.products).reduce(
                    (acc: number, q: any) => acc + Number(q || 0),
                    0,
                  )
                : 0) ??
              0,
          ),
          paymentMethod: String(s.paymentMethod ?? s.type ?? ""),
          paymentStatus: String(s.paymentStatus ?? ""),
          dateAdded: date,
          pickupAt: s.pickupAt ?? null,
          pickupLabel: s.pickupLabel ?? null,
        };
      });

      // Paid-only filters
      sales = sales.filter((s: any) => {
        const status = s.status.toLowerCase();
        const pm = s.paymentMethod.toLowerCase();
        const ps = s.paymentStatus.toLowerCase();

        if (status === "cancelled" || status === "rejected") return false;

        if (wantOnline) {
          if (pm !== "online") return false;
          if (ps && ps !== "paid") return false;
          return true;
        }

        if (wantCash) {
          if (pm !== "cash") return false;
          if (ps && ps !== "paid") return false;
          return true;
        }

        if (s.paymentStatus && s.paymentStatus.toLowerCase() !== "paid")
          return false;
        return true;
      });

      // === Ledger fallback for Online ===
      if (wantOnline) {
        const led = await db
          .collection("users")
          .doc(merchantId)
          .collection("salesLedger")
          .where("provider", "==", "paystack")
          .orderBy("createdAt", "desc")
          .limit(pageLimit)
          .get();

        const have = new Set(sales.map((s: any) => s.id));
        const missingIds = led.docs
          .map((d) => String(d.get("saleId") ?? ""))
          .filter((id) => id && !have.has(id));

        if (missingIds.length) {
          const chunks: string[][] = [];
          for (let i = 0; i < missingIds.length; i += 10)
            chunks.push(missingIds.slice(i, i + 10));

          const joinedDocs: QueryDocumentSnapshot<DocumentData>[] = [];
          for (const chunk of chunks) {
            const bs = await db
              .collection("users")
              .doc(merchantId)
              .collection("sales")
              .where(FieldPath.documentId(), "in", chunk)
              .get();
            joinedDocs.push(...bs.docs);
          }

          const joined = joinedDocs.map((d) => {
            const s: any = d.data() || {};
            const total = Number(s.total ?? s.amount ?? s.saleTotal ?? 0);
            const date = s.dateAdded ?? s.createdAt ?? s.paidAt ?? null;
            return {
              id: d.id,
              status: String(s.status ?? "paid"),
              total,
              itemsCount: Number(s.itemsCount ?? 0),
              paymentMethod: "Online",
              paymentStatus: String(s.paymentStatus ?? "paid"),
              dateAdded: date,
              pickupAt: s.pickupAt ?? null,
              pickupLabel: s.pickupLabel ?? null,
            };
          });

          // merge & sort
          sales = [...sales, ...joined].sort((a: any, b: any) => {
            const at = tsToMillis(a?.dateAdded);
            const bt = tsToMillis(b?.dateAdded);
            return bt - at;
          });
        }
      }

      return { sales };
    } catch (error: any) {
      console.error("Error fetching sales:", error?.message || error);
      if (error instanceof functions.https.HttpsError) throw error;
      throw new functions.https.HttpsError("internal", "Failed to fetch sales");
    }
  },
);
