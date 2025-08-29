// functions/src/http/checkoutCart.ts
import { db, functions } from "../config/main";
import * as admin from "firebase-admin";
import { computeCartSig } from "./cartSig";

type PaymentType = "Cash" | "Online" | "BNPL" | string;

export const checkoutCart = functions.https.onRequest(async (req, res) => {
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
      preview = false, // <— only flag we keep
      idempotencyKey = null, // optional, for deduping sale creation
    } = (req.body || {}) as {
      merchantId: string;
      customerId: string;
      paymentType?: PaymentType;
      deliveryInfo?: string;
      remarks?: string;
      pickupAt?: string | null;
      pickupLabel?: string | null;
      preview?: boolean;
      idempotencyKey?: string | null;
    };

    if (!merchantId || !customerId) {
      res.status(400).json({ error: "merchantId and customerId are required" });
      return;
    }

    const ptype = String(paymentType || "").toLowerCase();

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
    let total = 0;
    let itemsCount = 0;
    for (const snap of productDocs) {
      const pid = snap.id;
      const qty = Number(quantities[pid] || 0);
      if (qty <= 0) continue;
      itemsCount += qty;
      const data = snap.exists ? snap.data() || {} : {};
      const unit =
        Number(data.sellingPrice ?? data.price ?? data.productPrice ?? 0) || 0;
      total += unit * qty;
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

    const productsMap: Record<string, number> = {};
    Object.keys(quantities).forEach(
      (pid) => (productsMap[pid] = Number(quantities[pid] || 0)),
    );

    const now = admin.firestore.FieldValue.serverTimestamp();
    const initialStatus =
      ptype === "cash"
        ? "awaiting_collection"
        : ptype === "bnpl"
          ? "pending_review"
          : ptype === "online"
            ? "pending_payment"
            : "pending";

    // PREVIEW: return computed snapshot only
    if (preview) {
      res.status(200).json({
        success: true,
        preview: true,
        total,
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
    const canSupersedeStatuses = new Set(["pending_payment", "pending_review"]);

    if (!openQ.empty) {
      const os = openQ.docs[0].data();
      const openStatus = String(os.status || "").toLowerCase();
      if (
        [
          "pending_payment",
          "awaiting_collection",
          "pending_review",
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
          await db.runTransaction(async (tx) => {
            const prevRef = db
              .collection("users")
              .doc(merchantId)
              .collection("sales")
              .doc(os.id);
            tx.update(prevRef, {
              status: "cancelled",
              cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
              cancelledReason: "CART_CHANGED",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            const cartDoc = db
              .collection("users")
              .doc(merchantId)
              .collection("carts")
              .doc(customerId);
            tx.set(
              cartDoc,
              { lock: admin.firestore.FieldValue.delete() },
              { merge: true },
            );
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
        type: paymentType,
        status: initialStatus,
        amount: total,
        itemsCount,
        currency: "ZAR",
        products: productsMap,
        items,
        cartSig,
        deliveryInfo: deliveryInfo || "",
        remarks: remarks || "",
        pickupAt: pickupAt || null,
        pickupLabel: pickupLabel || null,
        dateAdded: now,
        updatedAt: now,
        inventoryFinalized: false,
        idempotencyKey: idempotencyKey || null,
      },
      { merge: true },
    );

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
            lockedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true },
      );

    res.status(200).json({
      success: true,
      saleId: saleRef.id,
      total,
      itemsCount,
      status: initialStatus,
    });
  } catch (error: any) {
    console.error("Error completing checkout:", error?.message || error);
    res.status(500).json({ error: "Failed to checkout" });
    return;
  }
});
