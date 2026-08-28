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
import {
  loadMerchantBotFeatureAccess,
  requiredMerchantBotCheckoutFeatures,
} from "./merchantBotFeatureAccess";
import {
  CatalogCartPlan,
  StoredNativeCatalogCartLine,
  WhatsAppCatalogCartValidationError,
  WHATSAPP_CATALOG_CART_STATES,
  nativeCatalogCartStateDocumentId,
  planStoredNativeCatalogCart,
} from "./replaceWhatsAppCatalogCart";
import { WHATSAPP_CATALOG_MAPPINGS } from "../whatsapp/catalogQueue";

type PaymentType = "Cash" | "Online" | "BNPL" | string;
type FulfillmentType = "pickup" | "delivery" | string;

function idempotencyDocId(value: string | null): string | null {
  const normalized = String(value || "").trim();
  if (!normalized) return null;
  return encodeURIComponent(normalized).slice(0, 500);
}

type NativeCartDocument = {
  id: string;
  data(): FirebaseFirestore.DocumentData;
};

function storedNativeCartLines(
  documents: readonly NativeCartDocument[],
): StoredNativeCatalogCartLine[] {
  return documents.map((document) => {
    const data = document.data() ?? {};
    return {
      productId: document.id,
      quantity: data.quantity,
      source: data.source,
      retailerId: data.catalogRetailerId,
      catalogRevision: data.catalogRevision,
      catalogPriceMinor: data.catalogPriceMinor,
    };
  });
}

function nativeCartReferences(input: {
  merchantId: string;
  lines: readonly StoredNativeCatalogCartLine[];
}): {
  mappingRefs: FirebaseFirestore.DocumentReference[];
  productRefs: FirebaseFirestore.DocumentReference[];
} {
  const mappingRefs: FirebaseFirestore.DocumentReference[] = [];
  const productRefs: FirebaseFirestore.DocumentReference[] = [];
  for (const line of input.lines) {
    const productId = String(line.productId ?? "").trim();
    const retailerId = String(line.retailerId ?? "").trim();
    if (
      !/^[A-Za-z0-9_-]{1,500}$/.test(productId) ||
      !/^spz_[a-f0-9]{32}$/.test(retailerId)
    ) {
      throw new WhatsAppCatalogCartValidationError("cart_changed");
    }
    mappingRefs.push(db.doc(`${WHATSAPP_CATALOG_MAPPINGS}/${retailerId}`));
    productRefs.push(db.doc(`users/${input.merchantId}/products/${productId}`));
  }
  return { mappingRefs, productRefs };
}

function nativeCartMappings(
  snapshots: readonly FirebaseFirestore.DocumentSnapshot[],
) {
  return snapshots.map((snapshot) => ({
    exists: snapshot.exists,
    status: snapshot.get("status"),
    merchantId: snapshot.get("merchantId"),
    productId: snapshot.get("productId"),
    retailerId: snapshot.get("retailerId") ?? snapshot.id,
    lastAppliedRevision: snapshot.get("lastAppliedRevision"),
  }));
}

function nativeCartChangedResponse(
  res: functions.Response,
  error: unknown,
): void {
  const reason =
    error instanceof WhatsAppCatalogCartValidationError
      ? error.reason
      : "cart_changed";
  const typedCodes: Partial<Record<typeof reason, string>> = {
    idempotency_conflict: "IDEMPOTENCY_CONFLICT",
    price_changed: "PRICE_CHANGED",
    product_unavailable: "PRODUCT_UNAVAILABLE",
    quantity_unavailable: "QUANTITY_UNAVAILABLE",
  };
  res.status(409).json({
    error:
      "The catalogue cart changed. Review the latest products before ordering.",
    code: typedCodes[reason] ?? "NATIVE_CATALOG_CART_CHANGED",
    reason,
  });
}

/**
 * Rolls back only the server receipt and cart lock owned by a native sale
 * whose inventory reservation failed. Sale cancellation and ownership-checked
 * cleanup commit together, so a retry cannot observe a cancelled sale as a
 * successful idempotent checkout.
 */
export async function cancelFailedNativeInventoryReservationAtomically(input: {
  saleRef: FirebaseFirestore.DocumentReference;
  idempotencyRef: FirebaseFirestore.DocumentReference;
  cartRef: FirebaseFirestore.DocumentReference;
  saleId: string;
  reason: string;
}): Promise<void> {
  await db.runTransaction(async (tx) => {
    const [receipt, cart] = await Promise.all([
      tx.get(input.idempotencyRef),
      tx.get(input.cartRef),
    ]);
    tx.set(
      input.saleRef,
      {
        status: "cancelled",
        paymentStatus: "cancelled",
        cancelledReason: input.reason,
        cancelledAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    if (receipt.get("saleId") === input.saleId) {
      tx.delete(input.idempotencyRef);
    }
    if (cart.get("lock")?.saleId === input.saleId) {
      tx.set(input.cartRef, { lock: FieldValue.delete() }, { merge: true });
    }
  });
}

export const nativeCatalogCheckoutHandler = async (
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
      nativeCartFingerprint: claimedNativeCartFingerprint = null,
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
      nativeCartFingerprint?: string | null;
    };

    if (!merchantId || !customerId) {
      res.status(400).json({ error: "merchantId and customerId are required" });
      return;
    }

    const botRequest = verifyBotRequest(req);
    if (!botRequest) {
      const uid = await authenticateFirebaseRequest(req, res, {
        requireAppCheck: true,
      });
      if (!uid) return;
      await assertStoreAccess(uid, merchantId);
    }

    const ptype = String(paymentType || "").toLowerCase();
    const isPaystackV2 =
      ptype === "online" && String(paymentRail ?? "") === "paystack_v2";
    if (botRequest) {
      const requiredFeatures = requiredMerchantBotCheckoutFeatures({
        fulfillmentType,
        paymentType,
        paymentRail,
      });
      const access = requiredFeatures.length
        ? await loadMerchantBotFeatureAccess(merchantId)
        : null;
      const blockedFeature = requiredFeatures.find(
        (feature) => !access?.features[feature].enabled,
      );
      const blocked =
        blockedFeature && access
          ? {
              feature: blockedFeature,
              decision: access.features[blockedFeature],
            }
          : null;
      if (blocked) {
        res.status(409).json({
          error:
            "This shop needs to update Spaza One before this option can be used.",
          code: "MERCHANT_APP_UPDATE_REQUIRED",
          feature: blocked.feature,
          minimumBuild: blocked.decision.minimumBuild,
        });
        return;
      }
    }
    const idempotencyId = idempotencyDocId(idempotencyKey);
    const idempotencyRef = idempotencyId
      ? db
          .collection("users")
          .doc(merchantId)
          .collection("checkoutIdempotency")
          .doc(idempotencyId)
      : null;
    const suppliedNativeFingerprint = String(
      claimedNativeCartFingerprint ?? "",
    ).trim();
    const hasNativeCheckoutReceipt = /^[a-f0-9]{64}$/.test(
      suppliedNativeFingerprint,
    );

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

    // Native receipts are bound to customer + cart fingerprint inside the
    // final sale transaction. Never let the legacy shortcut bypass that
    // binding merely because an idempotency document already exists.
    if (idempotencyRef && !hasNativeCheckoutReceipt) {
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
    const [cartSnapshot, itemsSnap] = await Promise.all([
      cartDoc.get(),
      cartDoc.collection("items").get(),
    ]);
    if (itemsSnap.empty) {
      res.status(400).json({ error: "Cart is empty" });
      return;
    }
    const isNativeCatalogCart =
      cartSnapshot.get("source") === "whatsapp_native_catalog";
    if (isNativeCatalogCart && (!idempotencyRef || !hasNativeCheckoutReceipt)) {
      res.status(400).json({
        error:
          "Native catalogue checkout requires its cart receipt and idempotency key.",
        code: "NATIVE_CATALOG_CHECKOUT_RECEIPT_REQUIRED",
      });
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

    let nativeCartPlan:
      | { plan: CatalogCartPlan; fingerprint: string }
      | undefined;
    let productDocs: FirebaseFirestore.DocumentSnapshot[] = [];
    if (isNativeCatalogCart) {
      try {
        const lines = storedNativeCartLines(itemsSnap.docs);
        const { mappingRefs, productRefs } = nativeCartReferences({
          merchantId,
          lines,
        });
        const stateRef = db.doc(
          `${WHATSAPP_CATALOG_CART_STATES}/${nativeCatalogCartStateDocumentId({
            merchantId,
            customerId,
          })}`,
        );
        const [merchantSnapshot, stateSnapshot, mappingSnapshots, products] =
          await Promise.all([
            db.doc(`users/${merchantId}`).get(),
            stateRef.get(),
            db.getAll(...mappingRefs),
            db.getAll(...productRefs),
          ]);
        nativeCartPlan = planStoredNativeCatalogCart({
          merchantId,
          customerId,
          merchantExists: merchantSnapshot.exists,
          merchant: merchantSnapshot.data() ?? {},
          summary: cartSnapshot.data() ?? {},
          state: {
            exists: stateSnapshot.exists,
            merchantId: stateSnapshot.get("merchantId"),
            customerId: stateSnapshot.get("customerId"),
            catalogId: stateSnapshot.get("catalogId"),
            fingerprint: stateSnapshot.get("fingerprint"),
            schemaVersion: stateSnapshot.get("schemaVersion"),
          },
          lines,
          mappings: nativeCartMappings(mappingSnapshots),
          products: products.map((snapshot) =>
            snapshot.exists ? (snapshot.data() ?? {}) : undefined,
          ),
        });
        if (nativeCartPlan.fingerprint !== suppliedNativeFingerprint) {
          throw new WhatsAppCatalogCartValidationError("cart_changed");
        }
      } catch (error) {
        nativeCartChangedResponse(res, error);
        return;
      }
    } else {
      const productRefs = productIds.map((pid) =>
        db.collection("users").doc(merchantId).collection("products").doc(pid),
      );
      productDocs = productRefs.length ? await db.getAll(...productRefs) : [];
    }

    type SaleItem = {
      productId: string;
      quantity: number;
      priceMinor?: number;
      catalogRetailerId?: string;
      catalogRevision?: string;
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
    if (nativeCartPlan) {
      for (const item of nativeCartPlan.plan.items) {
        const unit = item.priceMinor / 100;
        quantities[item.productId] = item.quantity;
        itemsCount += item.quantity;
        subtotalMinor += item.priceMinor * item.quantity;
        items.push({
          productId: item.productId,
          quantity: item.quantity,
          priceMinor: item.priceMinor,
          catalogRetailerId: item.retailerId,
          catalogRevision: item.catalogRevision,
          details: {
            productId: item.productId,
            name: item.projection.title,
            productName: item.projection.title,
            price: unit,
            sellingPrice: unit,
            imageUrl: item.projection.imageUrl,
            image: item.projection.imageUrl,
            description: item.projection.description,
          },
        });
      }
    } else {
      for (const snap of productDocs) {
        const pid = snap.id;
        const qty = Number(quantities[pid] || 0);
        if (qty <= 0) continue;
        itemsCount += qty;
        const data = snap.exists ? snap.data() || {} : {};
        const unit =
          Number(data.sellingPrice ?? data.price ?? data.productPrice ?? 0) ||
          0;
        subtotalMinor += Math.round(unit * 100) * qty;
        items.push({
          productId: pid,
          quantity: qty,
          details: {
            productId: pid,
            name: (data.name ??
              data.productName ??
              data.title ??
              pid) as string,
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
    const cartSig =
      nativeCartPlan?.fingerprint ??
      computeCartSig(
        productDocs
          .map((snap) => {
            const pid = snap.id;
            const qty = Number(quantities[pid] || 0);
            const data = snap.exists ? snap.data() || {} : {};
            const unit =
              Number(
                data.sellingPrice ?? data.price ?? data.productPrice ?? 0,
              ) || 0;
            return { productId: pid, quantity: qty, unit };
          })
          .filter((item) => item.quantity > 0),
      );

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
    const saleData = {
      id: saleRef.id,
      customerId,
      type: paymentMethod,
      status: initialStatus,
      paymentMethod,
      ...(initialPaymentStatus ? { paymentStatus: initialPaymentStatus } : {}),
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
      ...(nativeCartPlan
        ? {
            cartSource: "whatsapp_native_catalog",
            nativeCartFingerprint: nativeCartPlan.fingerprint,
          }
        : {}),
      ...(isPaystackV2
        ? { paymentRail: "paystack_v2", source: "paystack_v2" }
        : {}),
      idempotencyKey: idempotencyKey || null,
    };

    let nativeDuplicateSaleId = "";
    if (nativeCartPlan) {
      try {
        if (!idempotencyRef) {
          throw new WhatsAppCatalogCartValidationError("cart_changed");
        }
        const nativeIdempotencyRef = idempotencyRef;
        const stateRef = db.doc(
          `${WHATSAPP_CATALOG_CART_STATES}/${nativeCatalogCartStateDocumentId({
            merchantId,
            customerId,
          })}`,
        );
        const result = await db.runTransaction(async (tx) => {
          const [idempotencySnapshot, finalCart, finalItems, merchantSnapshot] =
            await Promise.all([
              tx.get(nativeIdempotencyRef),
              tx.get(cartDoc),
              tx.get(cartDoc.collection("items")),
              tx.get(db.doc(`users/${merchantId}`)),
            ]);
          if (idempotencySnapshot.exists) {
            const existingSaleId = String(
              idempotencySnapshot.get("saleId") ?? "",
            ).trim();
            if (
              idempotencySnapshot.get("customerId") !== customerId ||
              idempotencySnapshot.get("cartSig") !== nativeCartPlan.fingerprint
            ) {
              throw new WhatsAppCatalogCartValidationError(
                "idempotency_conflict",
              );
            }
            if (existingSaleId) {
              return { outcome: "duplicate" as const, saleId: existingSaleId };
            }
          }
          const existingLock = finalCart.get("lock") as
            | Record<string, unknown>
            | undefined;
          if (String(existingLock?.saleId ?? "").trim()) {
            // The open-sale query is intentionally retained for its existing
            // customer response, but the cart lock is the transactional race
            // barrier. A concurrent checkout cannot create a second sale.
            throw new WhatsAppCatalogCartValidationError("cart_changed");
          }
          const lines = storedNativeCartLines(finalItems.docs);
          const { mappingRefs, productRefs } = nativeCartReferences({
            merchantId,
            lines,
          });
          const [stateSnapshot, mappingSnapshots, productSnapshots] =
            await Promise.all([
              tx.get(stateRef),
              Promise.all(mappingRefs.map((ref) => tx.get(ref))),
              Promise.all(productRefs.map((ref) => tx.get(ref))),
            ]);
          const finalPlan = planStoredNativeCatalogCart({
            merchantId,
            customerId,
            merchantExists: merchantSnapshot.exists,
            merchant: merchantSnapshot.data() ?? {},
            summary: finalCart.data() ?? {},
            state: {
              exists: stateSnapshot.exists,
              merchantId: stateSnapshot.get("merchantId"),
              customerId: stateSnapshot.get("customerId"),
              catalogId: stateSnapshot.get("catalogId"),
              fingerprint: stateSnapshot.get("fingerprint"),
              schemaVersion: stateSnapshot.get("schemaVersion"),
            },
            lines,
            mappings: nativeCartMappings(mappingSnapshots),
            products: productSnapshots.map((snapshot) =>
              snapshot.exists ? (snapshot.data() ?? {}) : undefined,
            ),
          });
          if (
            finalPlan.fingerprint !== nativeCartPlan.fingerprint ||
            finalPlan.fingerprint !== suppliedNativeFingerprint ||
            finalPlan.plan.totalMinor !== checkoutOptions.subtotalMinor
          ) {
            throw new WhatsAppCatalogCartValidationError("cart_changed");
          }
          tx.create(saleRef, saleData);
          tx.set(nativeIdempotencyRef, {
            saleId: saleRef.id,
            customerId,
            cartSig,
            createdAt: now,
            updatedAt: now,
          });
          tx.set(
            cartDoc,
            {
              lock: {
                saleId: saleRef.id,
                status: initialStatus,
                cartSig,
                lockedAt: now,
              },
            },
            { merge: true },
          );
          return { outcome: "created" as const, saleId: saleRef.id };
        });
        if (result.outcome === "duplicate") {
          nativeDuplicateSaleId = result.saleId;
        }
      } catch (error) {
        if (error instanceof WhatsAppCatalogCartValidationError) {
          nativeCartChangedResponse(res, error);
          return;
        }
        throw error;
      }
    } else {
      await saleRef.set(saleData, { merge: true });
    }

    if (nativeDuplicateSaleId) {
      const duplicateSale = await db
        .doc(`users/${merchantId}/sales/${nativeDuplicateSaleId}`)
        .get();
      if (!duplicateSale.exists) {
        res.status(409).json({
          error: "The checkout receipt no longer matches an order.",
          code: "CHECKOUT_IDEMPOTENCY_CONFLICT",
        });
        return;
      }
      const sale = duplicateSale.data() ?? {};
      if (
        sale.paymentRail === "paystack_v2" &&
        sale.inventoryReserved !== true
      ) {
        const status = String(sale.status ?? "").toLowerCase();
        res.status(409).json({
          error: "The order has not secured its inventory.",
          code:
            status === "cancelled"
              ? "INVENTORY_RESERVATION_FAILED"
              : "INVENTORY_RESERVATION_PENDING",
        });
        return;
      }
      res.status(200).json({
        success: true,
        idempotent: true,
        saleId: nativeDuplicateSaleId,
        total: Number(sale.amount ?? sale.total ?? 0),
        itemsCount: Number(sale.itemsCount ?? 0),
        status: String(sale.status || "pending"),
      });
      return;
    }

    if (isPaystackV2) {
      try {
        await reserveOwnedInventoryForSale({
          merchantId,
          orderId: saleRef.id,
        });
      } catch (error) {
        const code = error instanceof Error ? error.message : "unknown";
        if (nativeCartPlan && idempotencyRef) {
          await cancelFailedNativeInventoryReservationAtomically({
            saleRef,
            idempotencyRef,
            cartRef: cartDoc,
            saleId: saleRef.id,
            reason: code,
          });
        } else {
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
        }
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

    if (idempotencyRef && !nativeCartPlan) {
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
    if (!nativeCartPlan) {
      await cartDoc.set(
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
    }

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
  .https.onRequest(nativeCatalogCheckoutHandler);
