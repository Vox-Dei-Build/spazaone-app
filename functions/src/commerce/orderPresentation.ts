type UnknownRecord = Record<string, unknown>;

function record(value: unknown): UnknownRecord {
  return value && typeof value === "object" ? (value as UnknownRecord) : {};
}

function finiteNumber(value: unknown): number {
  const number = Number(value ?? 0);
  return Number.isFinite(number) ? number : 0;
}

export function orderCreatedAtMillis(value: unknown): number {
  const source = record(value);
  const createdAt = source.createdAt ?? source.dateAdded;
  if (createdAt && typeof createdAt === "object") {
    const timestamp = createdAt as { toMillis?: () => number };
    if (typeof timestamp.toMillis === "function") return timestamp.toMillis();
  }
  if (typeof createdAt === "string") {
    const parsed = Date.parse(createdAt);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}

export function isOpenCommerceOrder(value: unknown): boolean {
  return new Set([
    "pending_payment",
    "paid",
    "submitted_for_fulfilment",
    "shipped",
  ]).has(String(record(value).status ?? "").toLowerCase());
}

export type CanonicalOrderStatus =
  | "awaiting_payment"
  | "paid"
  | "preparing"
  | "on_the_way"
  | "delivered"
  | "cancelled"
  | "refunded";

/** Customer-facing lifecycle shared by stock and supplier orders. Source
 * states remain untouched so released operational paths keep working. */
export function canonicalCommerceOrderStatus(
  statusValue: unknown,
  paymentStatusValue?: unknown,
): CanonicalOrderStatus {
  const status = String(statusValue ?? "")
    .trim()
    .toLowerCase();
  const paymentStatus = String(paymentStatusValue ?? "")
    .trim()
    .toLowerCase();
  if (status === "refunded" || paymentStatus === "refunded") return "refunded";
  if (status === "cancelled") return "cancelled";
  if (status === "delivered") return "delivered";
  if (["shipped", "out_for_delivery", "on_the_way"].includes(status)) {
    return "on_the_way";
  }
  if (["submitted_for_fulfilment", "preparing"].includes(status)) {
    return "preparing";
  }
  if (status === "paid" || paymentStatus === "paid") return "paid";
  return "awaiting_payment";
}

/** Released readers may still call this helper, but partner names are no
 * longer part of the customer contract. */
export function buyerSafeTrackingCarrier(_value: unknown): string {
  void _value;
  return "";
}

/**
 * Normalizes a commerce order for the existing WhatsApp order-status reader.
 * Financial snapshots remain in minor units on the source document; only the
 * display-facing `total` is converted to Rand here.
 */
export function presentCommerceOrder(
  id: string,
  value: unknown,
): UnknownRecord {
  const order = record(value);
  const rawTracking = record(order.tracking);
  const tracking = Object.keys(rawTracking).length
    ? {
        // Kept as an empty compatibility field for released bot readers. A
        // delivery partner name is operational data and is never buyer-facing.
        carrier: "",
        number: String(rawTracking.number ?? ""),
        url: String(rawTracking.url ?? ""),
      }
    : null;
  const rawItems = Array.isArray(order.lineItems) ? order.lineItems : [];
  const items = rawItems.map((rawItem) => {
    const item = record(rawItem);
    const productId = String(
      item.sellerProductId ??
        item.supplierProductId ??
        order.sellerProductId ??
        order.listingId ??
        "",
    );
    const title = String(item.title ?? "Delivery product");
    return {
      productId,
      quantity: Math.max(1, Math.trunc(finiteNumber(item.quantity) || 1)),
      details: {
        productId,
        productName: title,
        name: title,
      },
    };
  });
  const itemsCount = items.reduce(
    (sum, item) => sum + finiteNumber(item.quantity),
    0,
  );
  const sourceStatus = String(order.status ?? "pending_payment");
  const status = canonicalCommerceOrderStatus(
    sourceStatus,
    order.paymentStatus,
  );

  return {
    id,
    orderId: id,
    source: "commerce",
    orderKind: "supplier_delivery",
    status,
    sourceStatus,
    total: finiteNumber(order.amountDueMinor) / 100,
    amount: finiteNumber(order.amountDueMinor) / 100,
    itemsCount: itemsCount || 1,
    items,
    createdAt: order.createdAt ?? null,
    type: "Delivery",
    paymentMethod: String(order.paymentMethod ?? "manual"),
    paymentStatus: String(order.paymentStatus ?? ""),
    fulfilmentStatus: String(order.fulfilmentStatus ?? ""),
    collected: status.toLowerCase() === "delivered",
    tracking,
  };
}
