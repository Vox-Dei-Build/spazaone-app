import { functions, db } from "../config/main";
import { normalizePhoneNumber } from "../contact/fetchUserBalance";

type StatementKind = "purchase" | "payment" | "adjustment";

interface StatementProduct {
  id?: string;
  name: string;
  quantity?: number;
  price?: number;
}

interface StatementTransaction {
  id: string;
  kind: StatementKind;
  type: string;
  amount: number;
  date: string | null;
  status?: string;
  orderId?: string;
  description: string;
  products: StatementProduct[];
}

function hasToDate(value: unknown): value is { toDate: () => Date } {
  return (
    typeof value === "object" &&
    value !== null &&
    "toDate" in value &&
    typeof value.toDate === "function"
  );
}

function recordValue(record: Record<string, unknown>, key: string): unknown {
  return record[key];
}

function toIsoDate(value: unknown): string | null {
  const date = hasToDate(value)
    ? value.toDate()
    : value instanceof Date
      ? value
      : typeof value === "string" || typeof value === "number"
        ? new Date(value)
        : null;
  if (!date || Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

function asMoney(value: unknown): number {
  const n = Number(value ?? 0);
  return Number.isFinite(n) ? n : 0;
}

function kindFor(type: string): StatementKind {
  const t = type.toLowerCase();
  if (t === "credit") return "purchase";
  if (t === "debit" || t === "payment") return "payment";
  return "adjustment";
}

function descriptionFor(kind: StatementKind): string {
  if (kind === "purchase") return "Bought on account";
  if (kind === "payment") return "Payment received";
  return "Account adjustment";
}

async function productsFor(
  merchantId: string,
  rawProducts: unknown,
): Promise<StatementProduct[]> {
  if (!rawProducts) return [];

  if (Array.isArray(rawProducts)) {
    return rawProducts
      .map((rawItem) => {
        const item =
          typeof rawItem === "object" && rawItem !== null
            ? (rawItem as Record<string, unknown>)
            : {};
        return {
          id: String(
            recordValue(item, "productId") ?? recordValue(item, "id") ?? "",
          ),
          name: String(
            recordValue(item, "name") ??
              recordValue(item, "productName") ??
              recordValue(item, "title") ??
              "Item",
          ),
          quantity:
            Number(
              recordValue(item, "quantity") ?? recordValue(item, "qty") ?? 0,
            ) || undefined,
          price:
            Number(
              recordValue(item, "price") ??
                recordValue(item, "sellingPrice") ??
                0,
            ) || undefined,
        };
      })
      .slice(0, 5);
  }

  if (typeof rawProducts !== "object") return [];

  const entries = Object.entries(rawProducts as Record<string, unknown>).slice(
    0,
    5,
  );
  const products = await Promise.all(
    entries.map(async ([productId, quantity]) => {
      const productDoc = await db
        .collection("users")
        .doc(merchantId)
        .collection("products")
        .doc(productId)
        .get();
      const p = productDoc.data() ?? {};
      return {
        id: productId,
        name: String(p.name ?? p.productName ?? p.title ?? "Item"),
        quantity: Number(quantity) || undefined,
        price: Number(p.sellingPrice ?? p.price ?? 0) || undefined,
      };
    }),
  );

  return products;
}

export const getCustomerStatementBotHttp = functions.https.onRequest(
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const {
      customerPhone,
      merchantId: requestedMerchantId,
      limit = 5,
      days = 30,
    } = req.body ?? {};

    if (!customerPhone) {
      res.status(400).json({ error: "customerPhone is required" });
      return;
    }

    const normalizedNumber = normalizePhoneNumber(
      String(customerPhone).replace("whatsapp:", ""),
    );
    const since = new Date();
    since.setDate(since.getDate() - Number(days || 30));
    const perAccountLimit = Math.min(Math.max(Number(limit || 5), 1), 10);

    try {
      const customersSnap = await db
        .collectionGroup("customers")
        .where("number", "==", normalizedNumber)
        .get();

      const accounts = [];

      for (const customerDoc of customersSnap.docs) {
        const pathSegments = customerDoc.ref.path.split("/");
        const merchantId = pathSegments[1];
        if (requestedMerchantId && merchantId !== requestedMerchantId) continue;

        const customer = customerDoc.data() ?? {};
        const merchantDoc = await db.collection("users").doc(merchantId).get();
        const merchant = merchantDoc.data() ?? {};

        const txSnap = await customerDoc.ref
          .collection("transactions")
          .orderBy("date", "desc")
          .where("date", ">=", since)
          .limit(perAccountLimit)
          .get();

        const transactions: StatementTransaction[] = [];
        for (const txDoc of txSnap.docs) {
          const tx = txDoc.data() ?? {};
          const type = String(tx.type ?? "");
          const kind = kindFor(type);
          transactions.push({
            id: txDoc.id,
            kind,
            type,
            amount: asMoney(tx.amount),
            date: toIsoDate(tx.date),
            status: tx.status ? String(tx.status) : undefined,
            orderId: tx.orderId ? String(tx.orderId) : undefined,
            description: descriptionFor(kind),
            products: await productsFor(merchantId, tx.products),
          });
        }

        accounts.push({
          merchantId,
          customerId: customerDoc.id,
          merchantName: String(merchant.name ?? ""),
          shopName: String(merchant.shopName ?? merchant.name ?? "the shop"),
          balance: asMoney(customer.balance),
          transactions,
        });
      }

      res.status(200).json({
        customerPhone: normalizedNumber,
        generatedAt: new Date().toISOString(),
        accounts,
      });
    } catch (error) {
      console.error("Failed to fetch bot statement:", error);
      res.status(500).json({ error: "Failed to fetch statement" });
    }
  },
);
