import { db, functions } from "../config/main";
import { FieldValue } from "firebase-admin/firestore";
import { requireBotRequest } from "../security/requestAuth";
import { buildMerchantCatalogDecision } from "../whatsapp/catalogProjection";
import { WHATSAPP_CATALOG_MAPPINGS } from "../whatsapp/catalogQueue";

type AddToCartBody = {
  merchantId: string;
  customerId: string;
  productId: string;
  quantity?: number; // positive integer
};

export const addToCart = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const {
    merchantId,
    customerId,
    productId,
    quantity = 1,
  } = (req.body || {}) as AddToCartBody;

  if (!merchantId || !customerId || !productId) {
    res
      .status(400)
      .json({ error: "merchantId, customerId and productId are required" });
    return;
  }

  const qtyToAdd = Number(quantity);
  if (
    !Number.isFinite(qtyToAdd) ||
    qtyToAdd <= 0 ||
    !Number.isInteger(qtyToAdd)
  ) {
    res.status(400).json({ error: "quantity must be a positive integer" });
    return;
  }

  try {
    const productRef = db
      .collection("users")
      .doc(merchantId)
      .collection("products")
      .doc(productId);

    const cartSummaryRef = db
      .collection("users")
      .doc(merchantId)
      .collection("carts")
      .doc(customerId);

    const itemRef = cartSummaryRef.collection("items").doc(productId);

    const result = await db.runTransaction(async (tx) => {
      // 1) Load product (for price + details snapshot)
      const productSnap = await tx.get(productRef);
      if (!productSnap.exists) {
        throw new Error("Product not found");
      }
      const product = productSnap.data() || {};

      const unit = Number(product.sellingPrice ?? product.price ?? 0);
      if (!Number.isFinite(unit) || unit < 0) {
        throw new Error("Invalid product price");
      }

      // 2) Read current item and summary (create-if-missing)
      const [itemSnap, cartSnap] = await Promise.all([
        tx.get(itemRef),
        tx.get(cartSummaryRef),
      ]);

      const prevQty = Number(itemSnap.get("quantity") ?? 0);
      const newQty = prevQty + qtyToAdd;

      const prevTotal = Number(cartSnap.get("total") ?? 0);
      const prevCount = Number(cartSnap.get("itemsCount") ?? 0);

      // 3) Compute increments
      const lineIncrement = unit * qtyToAdd;
      const newTotal = prevTotal + lineIncrement;
      const newCount = prevCount + qtyToAdd;

      // 4) Upsert item with product snapshot
      tx.set(
        itemRef,
        {
          quantity: newQty,
          // snapshot used by UI (your cart step already reads these keys)
          details: {
            productId,
            name:
              product.name ?? product.productName ?? product.title ?? productId,
            productName:
              product.productName ?? product.name ?? product.title ?? productId,
            price: unit,
            sellingPrice: unit,
            imageUrl: product.imageUrl ?? product.image ?? null,
            image: product.image ?? null,
            description: product.description ?? "",
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      // 5) Upsert cart summary (denormalized running total)
      tx.set(
        cartSummaryRef,
        {
          total: newTotal,
          itemsCount: newCount,
          currency: "ZAR",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      return { total: newTotal, itemsCount: newCount, unitPrice: unit };
    });

    res.status(200).json({
      success: true,
      total: result.total,
      itemsCount: result.itemsCount,
    });
  } catch (error: any) {
    console.error("Error adding to cart:", error?.message || error);
    const code =
      error?.message === "Product not found" ||
      error?.message === "Invalid product price"
        ? 400
        : 500;
    res.status(code).json({ error: error?.message || "Failed to add item" });
  }
});

type AddWhatsAppCatalogProductBody = AddToCartBody & {
  retailerId: string;
  replaceQuantity?: boolean;
};

/**
 * Bot-only cart path for a native Meta catalogue selection. The mapping,
 * tenant, visibility, image, current price, retailer ID, and applied Meta
 * revision are revalidated in the same transaction that writes the cart.
 */
export const addWhatsAppCatalogProductToCartBotHttp = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"], timeoutSeconds: 15 })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }
    const {
      merchantId,
      customerId,
      productId,
      retailerId,
      quantity = 1,
      replaceQuantity = false,
    } = (req.body || {}) as AddWhatsAppCatalogProductBody;
    const qtyToAdd = Number(quantity);
    if (
      !/^[A-Za-z0-9_-]{1,200}$/.test(String(merchantId ?? "")) ||
      !/^[A-Za-z0-9_-]{1,500}$/.test(String(customerId ?? "")) ||
      !/^[A-Za-z0-9_-]{1,500}$/.test(String(productId ?? "")) ||
      !/^spz_[a-f0-9]{32}$/.test(String(retailerId ?? "")) ||
      !Number.isSafeInteger(qtyToAdd) ||
      qtyToAdd <= 0
    ) {
      res.status(400).json({ error: "CATALOG_CART_REQUEST_INVALID" });
      return;
    }

    const productRef = db.doc(`users/${merchantId}/products/${productId}`);
    const merchantRef = db.doc(`users/${merchantId}`);
    const mappingRef = db.doc(`${WHATSAPP_CATALOG_MAPPINGS}/${retailerId}`);
    const cartSummaryRef = db.doc(`users/${merchantId}/carts/${customerId}`);
    const itemRef = cartSummaryRef.collection("items").doc(productId);

    try {
      const result = await db.runTransaction(async (tx) => {
        const [mappingSnap, merchantSnap, productSnap, itemSnap, cartSnap] =
          await Promise.all([
            tx.get(mappingRef),
            tx.get(merchantRef),
            tx.get(productRef),
            tx.get(itemRef),
            tx.get(cartSummaryRef),
          ]);
        const mapping = mappingSnap.data() ?? {};
        const product = productSnap.exists
          ? (productSnap.data() ?? {})
          : undefined;
        const decision = buildMerchantCatalogDecision({
          merchantId,
          productId,
          product,
          merchant: merchantSnap.data() ?? {},
        });
        if (
          !mappingSnap.exists ||
          mapping.status !== "active" ||
          mapping.merchantId !== merchantId ||
          mapping.productId !== productId ||
          String(mapping.retailerId ?? mappingSnap.id) !== retailerId ||
          decision.action !== "upsert" ||
          !decision.projection ||
          decision.retailerId !== retailerId ||
          decision.revision !== mapping.lastAppliedRevision
        ) {
          throw new Error("CATALOG_PRODUCT_STALE");
        }

        const unit = decision.projection.priceMinor / 100;
        const prevQty = Number(itemSnap.get("quantity") ?? 0);
        const prevTotal = Number(cartSnap.get("total") ?? 0);
        const prevCount = Number(cartSnap.get("itemsCount") ?? 0);
        const newQty = replaceQuantity ? qtyToAdd : prevQty + qtyToAdd;
        const quantityDelta = newQty - prevQty;
        const priorDetails = itemSnap.data()?.details ?? {};
        const priorUnit = Number(
          priorDetails.sellingPrice ?? priorDetails.price ?? unit,
        );
        const newTotal = replaceQuantity
          ? prevTotal - prevQty * priorUnit + newQty * unit
          : prevTotal + unit * quantityDelta;
        const newCount = prevCount + quantityDelta;

        tx.set(
          itemRef,
          {
            quantity: newQty,
            details: {
              productId,
              name: decision.projection.title,
              productName: decision.projection.title,
              price: unit,
              sellingPrice: unit,
              imageUrl: decision.projection.imageUrl,
              image: decision.projection.imageUrl,
              description: decision.projection.description,
            },
            catalogRetailerId: retailerId,
            catalogRevision: decision.revision,
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        tx.set(
          cartSummaryRef,
          {
            total: newTotal,
            itemsCount: newCount,
            currency: "ZAR",
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        return { total: newTotal, itemsCount: newCount };
      });
      res.status(200).json({ success: true, ...result });
    } catch (error) {
      const code =
        error instanceof Error && error.message === "CATALOG_PRODUCT_STALE"
          ? 409
          : 500;
      res.status(code).json({
        error:
          code === 409 ? "CATALOG_PRODUCT_STALE" : "CATALOG_CART_WRITE_FAILED",
      });
    }
  });
