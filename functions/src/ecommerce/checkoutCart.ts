// functions/src/http/checkoutCart.ts
import { db, functions } from "../config/main";
import { FieldValue } from "firebase-admin/firestore";
import { computeCartSig } from "./cartSig";
import {
  authenticateFirebaseRequest,
  verifyBotRequest,
} from "../security/requestAuth";
import { assertStoreAccess } from "../stores/storeAccess";
import { paymentReadiness } from "../payments/v2/readiness";
import {
  releaseOwnedInventoryReservation,
  reserveOwnedInventoryForSale,
} from "../payments/v2/inventoryReservations";
import {
  merchantCheckoutOptionDecision,
  merchantOrderingOptionsFrom,
} from "./merchantOrderingOptions";

type PaymentType = "Cash" | "Online" | "BNPL" | string;
type FulfillmentType = "pickup" | "delivery" | string;

function idempotencyDocId(value: string | null): string | null {
  const normalized = String(value || "").trim();
  if (!normalized) return null;
  return encodeURIComponent(normalized).slice(0, 500);
}

const checkoutCartHandler = async (
  req: functions.https.Request,
  res: functions.Response,
) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  try {
    const {
      merchantId,
      customerId,
      paymentType = "Online",
      deliveryInfo = "",
      remarks = "",
      pickupAt = null,
      pickupLabel = null,
      orderRequest = false,
      orderChannel = null,
      fulfillmentType = null,
      deliveryAddress = "",
      requestedFulfillmentTime = "",
      cashChangeFor = null,
      customerNote = "",
      mediaRefs = [],
      preview = false, // <— only flag we keep
      idempotencyKey = null, // optional, for deduping sale creation
      paymentRail = null,
      deliveryFeeMinor: claimedDeliveryFeeMinor = undefined,
      totalMinor: claimedTotalMinor = undefined,
    } = (req.body || {}) as {
      merchantId: string;
      customerId: string;
      paymentType?: PaymentType;
      deliveryInfo?: string;
      remarks?: string;
      pickupAt?: string | null;
      pickupLabel?: string | null;
      orderRequest?: boolean;
      orderChannel?: string | null;
      fulfillmentType?: FulfillmentType | null;
      deliveryAddress?: string;
      requestedFulfillmentTime?: string;
      cashChangeFor?: number | string | null;
      customerNote?: string;
      mediaRefs?: string[];
      preview?: boolean;
      idempotencyKey?: string | null;
      paymentRail?: string | null;
      deliveryFeeMinor?: number;
      totalMinor?: number;
    };

    if (!merchantId || !customerId) {
      res.status(400).json({ error: "merchantId and customerId are required" });
      return;
    }

    if (!verifyBotRequest(req)) {
      const uid = await authenticateFirebaseRequest(req, res, {
        requireAppCheck: true,
      });
      if (!uid) return;
      await assertStoreAccess(uid, merchantId);
    }

    const ptype = String(paymentType || "").toLowerCase();
    const isPaystackV2 =
      ptype === "online" && String(paymentRail ?? "") === "paystack_v2";
    const idempotencyId = idempotencyDocId(idempotencyKey);
    const idempotencyRef = idempotencyId
      ? db
          .collection("users")
          .doc(merchantId)
          .collection("checkoutIdempotency")
          .doc(idempotencyId)
      : null;

    if (isPaystackV2) {
      if (!idempotencyRef) {
        res.status(400).json({ error: "An idempotency key is required." });
        return;
      }
      const readiness = await paymentReadiness({
        merchantId,
        purpose: "merchant_order",
      });
      if (!readiness.enabled) {
        res.status(409).json({
          error: "Online payments are not available for this shop yet.",
          reason: readiness.reason,
        });
        return;
      }
    }

    if (idempotencyRef) {
      const existing = await idempotencyRef.get();
      const existingSaleId = existing.exists
        ? String(existing.get("saleId") || "")
        : "";
      if (existingSaleId) {
        const saleSnap = await db
          .collection("users")
          .doc(merchantId)
          .collection("sales")
          .doc(existingSaleId)
          .get();
        if (saleSnap.exists) {
          const sale = saleSnap.data() || {};
          res.status(200).json({
            success: true,
            idempotent: true,
            saleId: existingSaleId,
            total: Number(sale.amount ?? sale.total ?? 0),
            itemsCount: Number(sale.itemsCount ?? 0),
            status: String(sale.status || "pending"),
          });
          return;
        }
      }
    }

    const cartDoc = db
      .collection("users")
      .doc(merchantId)
      .collection("carts")
      .doc(customerId);
    const itemsSnap = await cartDoc.collection("items").get();
    if (itemsSnap.empty) {
      res.status(400).json({ error: "Cart is empty" });
      return;
    }

    // Build quantities + fetch products
    const quantities: Record<string, number> = {};
    const productIds: string[] = [];
    itemsSnap.forEach((d) => {
      const q = Number((d.data() || {}).quantity || 0);
      if (q > 0) {
        productIds.push(d.id);
        quantities[d.id] = q;
      }
    });

    const productRefs = productIds.map((pid) =>
      db.collection("users").doc(merchantId).collection("products").doc(pid),
    );
    const productDocs = productRefs.length
      ? await db.getAll(...productRefs)
      : [];

    type SaleItem = {
      productId: string;
      quantity: number;
      details: {
        productId: string;
        name: string;
        productName: string;
        price: number;
        sellingPrice: number;
        imageUrl: string | null;
        image: string | null;
        description: string;
      };
    };

    const items: SaleItem[] = [];
    let subtotalMinor = 0;
    let itemsCount = 0;
    for (const snap of productDocs) {
      const pid = snap.id;
      const qty = Number(quantities[pid] || 0);
      if (qty <= 0) continue;
      itemsCount += qty;
      const data = snap.exists ? snap.data() || {} : {};
      const unit =
        Number(data.sellingPrice ?? data.price ?? data.productPrice ?? 0) || 0;
      subtotalMinor += Math.round(unit * 100) * qty;
      items.push({
        productId: pid,
        quantity: qty,
        details: {
          productId: pid,
          name: (data.name ?? data.productName ?? data.title ?? pid) as string,
          productName: (data.productName ??
            data.name ??
            data.title ??
            pid) as string,
          price: unit,
          sellingPrice: unit,
          imageUrl: (data.imageUrl ?? data.image ?? null) || null,
          image: (data.image ?? null) || null,
          description: (data.description ?? "") as string,
        },
      });
    }

    let checkoutOptions;
    try {
      const settings = await db
        .doc(`merchantCommerceSettings/${merchantId}`)
        .get();
      checkoutOptions = merchantCheckoutOptionDecision({
        options: merchantOrderingOptionsFrom(settings.data()),
        fulfillmentType,
        paymentType,
        deliveryAddress,
        claimedDeliveryFeeMinor,
        claimedTotalMinor,
        subtotalMinor,
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      const messages: Record<string, string> = {
        DELIVERY_DISABLED: "Delivery is not available from this shop.",
        DELIVERY_ADDRESS_REQUIRED: "Enter a delivery address.",
        PAY_LATER_DISABLED: "Pay Later is not available from this shop.",
        DELIVERY_FEE_MISMATCH: "The delivery fee changed. Review the total.",
        ORDER_TOTAL_MISMATCH: "The order total changed. Review the cart.",
        FULFILLMENT_TYPE_INVALID: "Choose pickup or delivery.",
        PAYMENT_TYPE_INVALID: "Choose an available payment method.",
      };
      res.status(409).json({
        error: messages[code] ?? "The selected order option is unavailable.",
        code: code || "ORDER_OPTIONS_INVALID",
      });
      return;
    }
    const total = checkoutOptions.totalMinor / 100;
    const canonicalPaymentType = checkoutOptions.paymentType;

    const productsMap: Record<string, number> = {};
    Object.keys(quantities).forEach(
      (pid) => (productsMap[pid] = Number(quantities[pid] || 0)),
    );

    const now = FieldValue.serverTimestamp();
    const isOrderRequest =
      orderRequest === true || checkoutOptions.requiresMerchantReview;
    const initialStatus = isOrderRequest
      ? "pending_merchant_review"
      : canonicalPaymentType === "cash"
        ? "awaiting_collection"
        : canonicalPaymentType === "bnpl"
          ? "pending_review"
          : canonicalPaymentType === "online"
            ? "pending_payment"
            : "pending";
    const initialPaymentStatus =
      canonicalPaymentType === "online"
        ? "pending"
        : canonicalPaymentType === "bnpl"
          ? "pending"
          : isOrderRequest
            ? "unpaid"
            : undefined;
    const paymentMethod =
      canonicalPaymentType === "cash"
        ? "Cash"
        : canonicalPaymentType === "transfer"
          ? "Transfer"
          : canonicalPaymentType === "bnpl"
            ? "BNPL"
            : canonicalPaymentType === "online"
              ? "Online"
              : paymentType;

    // PREVIEW: return computed snapshot only
    if (preview) {
      res.status(200).json({
        success: true,
        preview: true,
        total,
        subtotalMinor: checkoutOptions.subtotalMinor,
        deliveryFeeMinor: checkoutOptions.deliveryFeeMinor,
        totalMinor: checkoutOptions.totalMinor,
        itemsCount,
        currency: "ZAR",
        items,
      });
      return;
    }

    // Build normalized items for signature
    const signables = productDocs
      .map((snap) => {
        const pid = snap.id;
        const qty = Number(quantities[pid] || 0);
        const data = snap.exists ? snap.data() || {} : {};
        const unit =
          Number(data.sellingPrice ?? data.price ?? data.productPrice ?? 0) ||
          0;
        return { productId: pid, quantity: qty, unit };
      })
      .filter((x) => x.quantity > 0);

    const cartSig = computeCartSig(signables);

    // BEFORE creating a new sale: check for open one
    const openQ = await db
      .collection("users")
      .doc(merchantId)
      .collection("sales")
      .where("customerId", "==", customerId)
      .where("inventoryFinalized", "==", false)
      .orderBy("dateAdded", "desc")
      .limit(1)
      .get();

    const bodySupersede = Boolean((req.body || {}).supersedeOpenSale);
    const canSupersedeStatuses = new Set([
      "pending_payment",
      "pending_review",
      "pending_merchant_review",
    ]);

    if (!openQ.empty) {
      const os = openQ.docs[0].data();
      const openStatus = String(os.status || "").toLowerCase();
      if (
        [
          "pending_payment",
          "awaiting_collection",
          "pending_review",
          "pending_merchant_review",
          "bnpl_outstanding",
        ].includes(openStatus)
      ) {
        if (os.cartSig === cartSig) {
          // same cart → block; client should Resume/Cancel
          res.status(409).json({
            error: "OPEN_SALE_SAME_CART",
            saleId: os.id,
            status: os.status,
            total: os.amount,
          });
          return;
        } else {
          // cart changed
          if (!bodySupersede || !canSupersedeStatuses.has(openStatus)) {
            res.status(409).json({
              error: "OPEN_SALE_CART_CHANGED",
              saleId: os.id,
              status: os.status,
              total: os.amount,
            });
            return;
          }
          // Supersede: cancel old & drop its cart lock atomically
          const reservationId = String(os.inventoryReservationId ?? "").trim();
          if (reservationId && os.inventoryReserved === true) {
            await releaseOwnedInventoryReservation({
              reservationId,
              reason: "cart_changed",
            });
          }
          await db.runTransaction(async (tx) => {
            const prevRef = db
              .collection("users")
              .doc(merchantId)
              .collection("sales")
              .doc(os.id);
            tx.update(prevRef, {
              status: "cancelled",
              cancelledAt: FieldValue.serverTimestamp(),
              cancelledReason: "CART_CHANGED",
              updatedAt: FieldValue.serverTimestamp(),
            });
            const cartDoc = db
              .collection("users")
              .doc(merchantId)
              .collection("carts")
              .doc(customerId);
            tx.set(cartDoc, { lock: FieldValue.delete() }, { merge: true });
          });
        }
      }
    }
    // CREATE SALE RECORD (no stock changes, no cart clearing)
    const saleRef = db
      .collection("users")
      .doc(merchantId)
      .collection("sales")
      .doc();

    await saleRef.set(
      {
        id: saleRef.id,
        customerId,
        type: paymentMethod,
        status: initialStatus,
        paymentMethod,
        ...(initialPaymentStatus
          ? { paymentStatus: initialPaymentStatus }
          : {}),
        amount: total,
        itemsCount,
        currency: "ZAR",
        products: productsMap,
        items,
        cartSig,
        deliveryInfo: deliveryInfo || "",
        fulfillmentType: checkoutOptions.fulfillmentType,
        deliveryAddress: deliveryAddress || "",
        deliveryFeeMinor: checkoutOptions.deliveryFeeMinor,
        subtotalMinor: checkoutOptions.subtotalMinor,
        totalMinor: checkoutOptions.totalMinor,
        orderingOptionsVersion: 1,
        merchantReviewRequired: checkoutOptions.requiresMerchantReview,
        requestedFulfillmentTime: requestedFulfillmentTime || "",
        cashChangeFor: cashChangeFor || null,
        remarks: remarks || "",
        customerNote: customerNote || remarks || "",
        mediaRefs: Array.isArray(mediaRefs) ? mediaRefs : [],
        orderRequest: isOrderRequest,
        orderChannel: orderChannel || (isOrderRequest ? "whatsapp" : null),
        pickupAt: pickupAt || null,
        pickupLabel: pickupLabel || null,
        dateAdded: now,
        updatedAt: now,
        inventoryFinalized: false,
        ...(isPaystackV2
          ? { paymentRail: "paystack_v2", source: "paystack_v2" }
          : {}),
        idempotencyKey: idempotencyKey || null,
      },
      { merge: true },
    );

    if (isPaystackV2) {
      try {
        await reserveOwnedInventoryForSale({
          merchantId,
          orderId: saleRef.id,
        });
      } catch (error) {
        const code = error instanceof Error ? error.message : "unknown";
        await saleRef.set(
          {
            status: "cancelled",
            paymentStatus: "cancelled",
            cancelledReason: code,
            cancelledAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        const unavailable = [
          "INVENTORY_UNAVAILABLE",
          "INVENTORY_PRODUCT_UNAVAILABLE",
          "INVENTORY_PRICE_CHANGED",
          "SALE_TOTAL_CHANGED",
        ].includes(code);
        res.status(unavailable ? 409 : 500).json({
          error: unavailable
            ? "The cart changed or an item is no longer available. Review the cart and try again."
            : "The order could not reserve stock. No payment was opened.",
          code: unavailable ? code : "INVENTORY_RESERVATION_FAILED",
        });
        return;
      }
    }

    if (idempotencyRef) {
      await idempotencyRef.set(
        {
          saleId: saleRef.id,
          customerId,
          cartSig,
          createdAt: now,
          updatedAt: now,
        },
        { merge: true },
      );
    }

    // after creating saleRef and saving the sale (no stock, no clear)
    await db
      .collection("users")
      .doc(merchantId)
      .collection("carts")
      .doc(customerId)
      .set(
        {
          lock: {
            saleId: saleRef.id,
            status: initialStatus,
            cartSig,
            lockedAt: FieldValue.serverTimestamp(),
          },
        },
        { merge: true },
      );

    res.status(200).json({
      success: true,
      saleId: saleRef.id,
      total,
      subtotalMinor: checkoutOptions.subtotalMinor,
      deliveryFeeMinor: checkoutOptions.deliveryFeeMinor,
      totalMinor: checkoutOptions.totalMinor,
      itemsCount,
      status: initialStatus,
    });
  } catch (error: any) {
    console.error("Error completing checkout:", error?.message || error);
    res.status(500).json({ error: "Failed to checkout" });
    return;
  }
};

export const checkoutCart = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(checkoutCartHandler);
