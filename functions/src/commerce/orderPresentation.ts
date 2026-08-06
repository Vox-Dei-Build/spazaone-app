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

/**
 * Supplier logistics names are operational data, not buyer-facing branding.
 * Keep the tracking number useful while preventing raw CJ provider names from
 * leaking through proactive WhatsApp/SMS status updates.
 */
export function buyerSafeTrackingCarrier(value: unknown): string {
  const carrier = String(value ?? "").trim();
  if (!carrier) return "";
  if (/(?:^|[^a-z0-9])cj(?:\s*packet|\s*dropshipping|\b)/i.test(carrier)) {
    return "Spaza One delivery";
  }
  return carrier;
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
        carrier: buyerSafeTrackingCarrier(rawTracking.carrier),
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
    const title = String(item.title ?? "Supplier product");
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
  const status = String(order.status ?? "pending_payment");

  return {
    id,
    orderId: id,
    source: "commerce",
    orderKind: "supplier_delivery",
    status,
    total: finiteNumber(order.amountDueMinor) / 100,
    amount: finiteNumber(order.amountDueMinor) / 100,
    itemsCount: itemsCount || 1,
    items,
    createdAt: order.createdAt ?? null,
    type: "Dropship",
    paymentMethod: String(order.paymentMethod ?? "manual"),
    paymentStatus: String(order.paymentStatus ?? ""),
    fulfilmentStatus: String(order.fulfilmentStatus ?? ""),
    collected: status.toLowerCase() === "delivered",
    tracking,
  };
}
