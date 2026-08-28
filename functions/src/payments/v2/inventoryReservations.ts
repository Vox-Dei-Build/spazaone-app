import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import { requirePositiveMinorUnits, stableDocumentId } from "./domain";
import { merchantProductSellPriceMinor } from "../../whatsapp/catalogProjection";

type ReservedItem = {
  productId: string;
  quantity: number;
  unitAmountMinor: number;
  availableBefore: number;
  availableAfter: number;
};

function requireId(value: unknown, field: string): string {
  const id = String(value ?? "").trim();
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(id)) throw new Error(`${field}_INVALID`);
  return id;
}

function quantity(value: unknown): number {
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0 || parsed > 100_000) {
    throw new Error("INVENTORY_QUANTITY_INVALID");
  }
  return parsed;
}

function unitMinor(product: Record<string, unknown>): number {
  const rands = Number(
    product.sellingPrice ?? product.price ?? product.productPrice ?? 0,
  );
  const minor = Math.round(rands * 100);
  return requirePositiveMinorUnits(minor, "unit_amount");
}

export function inventoryReservationDocumentId(input: {
  merchantId: string;
  orderId: string;
}): string {
  return stableDocumentId("ir", [
    requireId(input.merchantId, "MERCHANT_ID"),
    requireId(input.orderId, "ORDER_ID"),
  ]);
}

/**
 * Atomically removes owned stock from availability and binds it to one sale.
 * Final fulfilment consumes this reservation instead of decrementing stock a
 * second time; cancellation/expiry restores it exactly once.
 */
export async function reserveOwnedInventoryForSale(input: {
  merchantId: string;
  orderId: string;
  expiresInMs?: number;
}): Promise<{ reservationId: string; deduped: boolean }> {
  const merchantId = requireId(input.merchantId, "MERCHANT_ID");
  const orderId = requireId(input.orderId, "ORDER_ID");
  const expiresInMs = Number(input.expiresInMs ?? 15 * 60 * 1000);
  if (
    !Number.isSafeInteger(expiresInMs) ||
    expiresInMs < 60_000 ||
    expiresInMs > 60 * 60 * 1000
  ) {
    throw new Error("RESERVATION_EXPIRY_INVALID");
  }
  const reservationId = inventoryReservationDocumentId({ merchantId, orderId });
  const saleRef = db.doc(`users/${merchantId}/sales/${orderId}`);
  const reservationRef = db.doc(`inventoryReservations/${reservationId}`);
  let deduped = false;
  await db.runTransaction(async (tx) => {
    const [sale, existing] = await Promise.all([
      tx.get(saleRef),
      tx.get(reservationRef),
    ]);
    if (!sale.exists) throw new Error("SALE_NOT_FOUND");
    const saleData = sale.data() ?? {};
    if (existing.exists) {
      const data = existing.data() ?? {};
      if (
        String(data.merchantId ?? "") !== merchantId ||
        String(data.orderId ?? "") !== orderId ||
        !["active", "consumed"].includes(String(data.status ?? ""))
      ) {
        throw new Error("INVENTORY_RESERVATION_COLLISION");
      }
      deduped = true;
      return;
    }
    if (
      String(saleData.paymentRail ?? "") !== "paystack_v2" ||
      String(saleData.paymentStatus ?? "") !== "pending" ||
      String(saleData.status ?? "") !== "pending_payment"
    ) {
      throw new Error("SALE_NOT_RESERVABLE");
    }
    const saleProducts = (saleData.products ?? {}) as Record<string, unknown>;
    const saleItems = Array.isArray(saleData.items) ? saleData.items : [];
    const productIds = Object.keys(saleProducts).sort();
    if (!productIds.length) throw new Error("SALE_ITEMS_INVALID");
    const productRefs = productIds.map((productId) =>
      db.doc(
        `users/${merchantId}/products/${requireId(productId, "PRODUCT_ID")}`,
      ),
    );
    const productSnapshots = [];
    for (const productRef of productRefs) {
      productSnapshots.push(await tx.get(productRef));
    }
    const items: ReservedItem[] = [];
    let totalAmountMinor = 0;
    for (let index = 0; index < productIds.length; index += 1) {
      const productId = productIds[index];
      const requested = quantity(saleProducts[productId]);
      const product = productSnapshots[index];
      if (!product.exists) throw new Error("INVENTORY_PRODUCT_UNAVAILABLE");
      const productData = product.data() ?? {};
      const available = Number(productData.quantity);
      if (!Number.isSafeInteger(available) || available < requested) {
        throw new Error("INVENTORY_UNAVAILABLE");
      }
      const nativeCatalogSale =
        String(saleData.cartSource ?? "") === "whatsapp_native_catalog";
      const nativeUnitMinor = nativeCatalogSale
        ? merchantProductSellPriceMinor(productData)
        : null;
      if (nativeCatalogSale && nativeUnitMinor === null) {
        throw new Error("INVENTORY_PRICE_CHANGED");
      }
      const currentUnitMinor = nativeCatalogSale
        ? (nativeUnitMinor ?? unitMinor(productData))
        : unitMinor(productData);
      const saleItem = saleItems.find(
        (item: any) => String(item?.productId ?? "") === productId,
      );
      const quotedUnitMinor = nativeCatalogSale
        ? Number(saleItem?.priceMinor ?? 0)
        : Math.round(
            Number(
              saleItem?.details?.sellingPrice ?? saleItem?.details?.price ?? 0,
            ) * 100,
          );
      if (quotedUnitMinor !== currentUnitMinor) {
        throw new Error("INVENTORY_PRICE_CHANGED");
      }
      totalAmountMinor += currentUnitMinor * requested;
      items.push({
        productId,
        quantity: requested,
        unitAmountMinor: currentUnitMinor,
        availableBefore: available,
        availableAfter: available - requested,
      });
    }
    const saleAmountMinor =
      String(saleData.cartSource ?? "") === "whatsapp_native_catalog"
        ? Number(saleData.subtotalMinor ?? 0)
        : Math.round(Number(saleData.amount ?? saleData.total ?? 0) * 100);
    if (totalAmountMinor !== saleAmountMinor) {
      throw new Error("SALE_TOTAL_CHANGED");
    }
    const now = FieldValue.serverTimestamp();
    for (let index = 0; index < productRefs.length; index += 1) {
      tx.update(productRefs[index], {
        quantity: FieldValue.increment(-items[index].quantity),
        updatedAt: now,
      });
    }
    tx.create(reservationRef, {
      reservationId,
      merchantId,
      orderId,
      status: "active",
      items,
      totalAmountMinor,
      currency: "ZAR",
      inventorySnapshotVersion: 1,
      expiresAt: Timestamp.fromMillis(Date.now() + expiresInMs),
      schemaVersion: 2,
      createdAt: now,
      updatedAt: now,
    });
    tx.update(saleRef, {
      inventoryReservationId: reservationId,
      inventoryReserved: true,
      inventoryReservedAt: now,
      amountMinor: totalAmountMinor,
      source: "paystack_v2",
      updatedAt: now,
    });
  });
  return { reservationId, deduped };
}

export async function releaseOwnedInventoryReservation(input: {
  reservationId: string;
  reason: string;
}): Promise<{ deduped: boolean }> {
  const reservationId = requireId(input.reservationId, "RESERVATION_ID");
  const reason = String(input.reason ?? "")
    .trim()
    .slice(0, 120);
  if (!reason) throw new Error("RESERVATION_RELEASE_REASON_INVALID");
  const reservationRef = db.doc(`inventoryReservations/${reservationId}`);
  let deduped = false;
  await db.runTransaction(async (tx) => {
    const reservation = await tx.get(reservationRef);
    if (!reservation.exists) throw new Error("INVENTORY_RESERVATION_NOT_FOUND");
    const data = reservation.data() ?? {};
    if (data.status === "released" || data.status === "expired") {
      deduped = true;
      return;
    }
    if (data.status !== "active") throw new Error("RESERVATION_NOT_RELEASABLE");
    const merchantId = requireId(data.merchantId, "MERCHANT_ID");
    const orderId = requireId(data.orderId, "ORDER_ID");
    const items = Array.isArray(data.items) ? data.items : [];
    const productRefs = items.map((item: any) =>
      db.doc(
        `users/${merchantId}/products/${requireId(item?.productId, "PRODUCT_ID")}`,
      ),
    );
    for (const productRef of productRefs) await tx.get(productRef);
    const now = FieldValue.serverTimestamp();
    items.forEach((item: any, index: number) => {
      tx.update(productRefs[index], {
        quantity: FieldValue.increment(quantity(item?.quantity)),
        updatedAt: now,
      });
    });
    tx.update(reservationRef, {
      status: reason === "expired" ? "expired" : "released",
      releaseReason: reason,
      releasedAt: now,
      updatedAt: now,
    });
    tx.set(
      db.doc(`users/${merchantId}/sales/${orderId}`),
      {
        inventoryReserved: false,
        inventoryReservationReleasedAt: now,
        inventoryReservationReleaseReason: reason,
        updatedAt: now,
      },
      { merge: true },
    );
  });
  return { deduped };
}

export async function consumeOwnedInventoryReservation(input: {
  reservationId: unknown;
  merchantId: unknown;
  orderId: unknown;
}): Promise<{ deduped: boolean }> {
  const reservationId = requireId(input.reservationId, "RESERVATION_ID");
  const merchantId = requireId(input.merchantId, "MERCHANT_ID");
  const orderId = requireId(input.orderId, "ORDER_ID");
  const ref = db.doc(`inventoryReservations/${reservationId}`);
  let deduped = false;
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) throw new Error("INVENTORY_RESERVATION_NOT_FOUND");
    if (
      String(snapshot.get("merchantId") ?? "") !== merchantId ||
      String(snapshot.get("orderId") ?? "") !== orderId
    ) {
      throw new Error("INVENTORY_RESERVATION_BINDING_MISMATCH");
    }
    const paymentIntentId = requireId(
      snapshot.get("paymentIntentId"),
      "PAYMENT_INTENT_ID",
    );
    const intent = await tx.get(db.doc(`paymentIntents/${paymentIntentId}`));
    if (
      !intent.exists ||
      intent.get("purpose") !== "merchant_order" ||
      intent.get("status") !== "paid" ||
      intent.get("merchantId") !== merchantId ||
      intent.get("businessBinding.type") !== "owned_order" ||
      intent.get("businessBinding.id") !== orderId
    ) {
      throw new Error("INVENTORY_RESERVATION_PAYMENT_NOT_VERIFIED");
    }
    const status = String(snapshot.get("status") ?? "");
    if (status === "consumed") {
      deduped = true;
      return;
    }
    if (status !== "committed") throw new Error("RESERVATION_NOT_CONSUMABLE");
    tx.update(ref, {
      status: "consumed",
      consumedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { deduped };
}

export const expireOwnedInventoryReservations = functions.pubsub
  .schedule("every 5 minutes")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    const expired = await db
      .collection("inventoryReservations")
      .where("status", "==", "active")
      .where("expiresAt", "<=", Timestamp.now())
      .limit(100)
      .get();
    await Promise.all(
      expired.docs.map((doc) =>
        releaseOwnedInventoryReservation({
          reservationId: doc.id,
          reason: "expired",
        }).catch((error) => {
          console.error("[payments-v2] reservation expiry failed", {
            reservationId: doc.id,
            code: error instanceof Error ? error.message : "unknown",
          });
        }),
      ),
    );
    return null;
  });
