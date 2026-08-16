import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { assertCallableStoreAccess } from "../stores/storeAccess";
import { priceCommerceOrder, requireMinorUnits } from "./domain";
import { commercePaymentsEnabled } from "./readiness";

export type DropshipListingState = "active" | "internal" | "paused";

function cleanId(value: unknown, field: string): string {
  const text = String(value ?? "").trim();
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(text)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `A valid ${field} is required.`,
    );
  }
  return text;
}

function listingState(value: unknown): DropshipListingState {
  const state = String(value ?? "")
    .trim()
    .toLowerCase();
  if (!new Set(["active", "internal", "paused"]).has(state)) {
    throw new Error("LISTING_STATE_INVALID");
  }
  return state as DropshipListingState;
}

export function dropshipListingUpdate(input: {
  baseCostMinor: unknown;
  markupMinor: unknown;
  state: unknown;
  digitalPaymentsEnabled: boolean;
}): {
  state: DropshipListingState;
  markupMinor: number;
  sellPriceMinor: number;
  active: boolean;
  availability: "available" | "internal" | "paused";
  whatsappListed: boolean;
} {
  const baseCostMinor = requireMinorUnits(input.baseCostMinor, "base_cost");
  const markupMinor = requireMinorUnits(input.markupMinor, "markup");
  if (markupMinor <= 0 || markupMinor > 10_000_000) {
    throw new Error("MARKUP_INVALID");
  }
  const sellPriceMinor = baseCostMinor + markupMinor;
  priceCommerceOrder({
    baseCostMinor,
    sellPriceMinor,
    paymentFeeMinor: input.digitalPaymentsEnabled ? undefined : 0,
  });
  const state = listingState(input.state);
  return {
    state,
    markupMinor,
    sellPriceMinor,
    active: state === "active",
    availability: state === "active" ? "available" : state,
    whatsappListed: state === "active",
  };
}

export const updateDropshipListing = functions
  .runWith({ timeoutSeconds: 30, memory: "256MB" })
  .https.onCall(async (data, context) => {
    if (!context.app) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "App verification is required.",
      );
    }
    const storeId = cleanId(data?.storeId, "storeId");
    const sellerProductId = cleanId(data?.sellerProductId, "sellerProductId");
    const requestedListingId = cleanId(data?.listingId, "listingId");
    await assertCallableStoreAccess(context, storeId);

    const productRef = db.doc(`users/${storeId}/products/${sellerProductId}`);
    const listingRef = db.doc(`commerceListings/${requestedListingId}`);
    let result: ReturnType<typeof dropshipListingUpdate> | undefined;
    const now = FieldValue.serverTimestamp();

    await db.runTransaction(async (tx) => {
      const [productSnapshot, listingSnapshot] = await Promise.all([
        tx.get(productRef),
        tx.get(listingRef),
      ]);
      const product = productSnapshot.data();
      const listing = listingSnapshot.data();
      if (!productSnapshot.exists || !listingSnapshot.exists) {
        throw new functions.https.HttpsError(
          "not-found",
          "This supplier listing no longer exists.",
        );
      }
      if (
        product?.isDropshipListing !== true ||
        String(product?.commerceListingId ?? "") !== requestedListingId ||
        String(listing?.sellerId ?? "") !== storeId ||
        String(listing?.sellerProductId ?? "") !== sellerProductId
      ) {
        throw new functions.https.HttpsError(
          "permission-denied",
          "This supplier listing does not belong to the active shop.",
        );
      }

      try {
        result = dropshipListingUpdate({
          baseCostMinor: listing?.baseCostMinor,
          markupMinor: data?.markupMinor,
          state: data?.state,
          digitalPaymentsEnabled: commercePaymentsEnabled(),
        });
      } catch (error) {
        const code = error instanceof Error ? error.message : "";
        const message =
          code === "LISTING_STATE_INVALID"
            ? "Choose Active, Internal only, or Paused."
            : code === "MARKUP_INVALID"
              ? "Markup must be greater than zero and within the listing limit."
              : "Increase the markup so it covers the estimated payment fee.";
        throw new functions.https.HttpsError("invalid-argument", message);
      }

      tx.update(productRef, {
        markupMinor: result.markupMinor,
        sellPriceMinor: result.sellPriceMinor,
        sellingPrice: result.sellPriceMinor / 100,
        whatsappListed: result.whatsappListed,
        dropshipListingState: result.state,
        updatedAt: now,
        updatedBy: context.auth!.uid,
      });
      tx.update(listingRef, {
        markupMinor: result.markupMinor,
        sellPriceMinor: result.sellPriceMinor,
        active: result.active,
        availability: result.availability,
        listingState: result.state,
        updatedAt: now,
        updatedBy: context.auth!.uid,
      });
    });

    return {
      sellerProductId,
      listingId: requestedListingId,
      ...result!,
    };
  });
