import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { assertCallableStoreAccess } from "../stores/storeAccess";

export const MERCHANT_ORDERING_OPTIONS_VERSION = 1;

export type MerchantOrderingOptions = {
  version: number;
  pickup: { enabled: true };
  payLater: { enabled: boolean };
  delivery: {
    enabled: boolean;
    flatFeeMinor: number;
    serviceAreaText: string;
  };
};

export function merchantOrderingOptionsDefaults(): MerchantOrderingOptions {
  return {
    version: MERCHANT_ORDERING_OPTIONS_VERSION,
    pickup: { enabled: true },
    payLater: { enabled: false },
    delivery: { enabled: false, flatFeeMinor: 0, serviceAreaText: "" },
  };
}

function optionalText(value: unknown, max: number): string {
  const text = String(value ?? "")
    .trim()
    .replace(/\s+/g, " ");
  if (text.length > max) throw new Error("SERVICE_AREA_INVALID");
  return text;
}

function minorUnits(value: unknown): number {
  const amount = Number(value ?? 0);
  if (!Number.isSafeInteger(amount) || amount < 0 || amount > 10_000_000) {
    throw new Error("DELIVERY_FEE_INVALID");
  }
  return amount;
}

export function merchantOrderingOptionsFrom(
  value: Record<string, any> | undefined,
): MerchantOrderingOptions {
  const defaults = merchantOrderingOptionsDefaults();
  if (!value) return defaults;
  return {
    ...defaults,
    payLater: { enabled: value.payLater?.enabled === true },
    delivery: {
      enabled: value.delivery?.enabled === true,
      flatFeeMinor: minorUnits(value.delivery?.flatFeeMinor),
      serviceAreaText: optionalText(value.delivery?.serviceAreaText, 240),
    },
  };
}

export function merchantOrderingOptionsUpdate(
  value: Record<string, any> | undefined,
): MerchantOrderingOptions {
  if (
    typeof value?.payLater?.enabled !== "boolean" ||
    typeof value?.delivery?.enabled !== "boolean"
  ) {
    throw new Error("ORDERING_OPTIONS_INVALID");
  }
  const options = merchantOrderingOptionsFrom(value);
  if (options.delivery.enabled && !options.delivery.serviceAreaText) {
    throw new Error("SERVICE_AREA_REQUIRED");
  }
  return options;
}

export function merchantCheckoutOptionDecision(input: {
  options: MerchantOrderingOptions;
  fulfillmentType: unknown;
  paymentType: unknown;
  deliveryAddress: unknown;
  claimedDeliveryFeeMinor?: unknown;
  claimedTotalMinor?: unknown;
  subtotalMinor: number;
}): {
  fulfillmentType: "pickup" | "delivery";
  paymentType: "cash" | "online" | "bnpl" | "transfer";
  subtotalMinor: number;
  deliveryFeeMinor: number;
  totalMinor: number;
  requiresMerchantReview: boolean;
} {
  const fulfillment = String(input.fulfillmentType ?? "pickup")
    .trim()
    .toLowerCase();
  if (!new Set(["pickup", "delivery"]).has(fulfillment)) {
    throw new Error("FULFILLMENT_TYPE_INVALID");
  }
  if (fulfillment === "delivery" && !input.options.delivery.enabled) {
    throw new Error("DELIVERY_DISABLED");
  }
  if (
    fulfillment === "delivery" &&
    !String(input.deliveryAddress ?? "").trim()
  ) {
    throw new Error("DELIVERY_ADDRESS_REQUIRED");
  }

  const rawPayment = String(input.paymentType ?? "online")
    .trim()
    .toLowerCase();
  const payment =
    rawPayment === "eft"
      ? "transfer"
      : rawPayment === "pay_later"
        ? "bnpl"
        : rawPayment;
  if (!new Set(["cash", "online", "bnpl", "transfer"]).has(payment)) {
    throw new Error("PAYMENT_TYPE_INVALID");
  }
  if (payment === "bnpl" && !input.options.payLater.enabled) {
    throw new Error("PAY_LATER_DISABLED");
  }

  const subtotalMinor = minorUnits(input.subtotalMinor);
  const deliveryFeeMinor =
    fulfillment === "delivery" ? input.options.delivery.flatFeeMinor : 0;
  const totalMinor = subtotalMinor + deliveryFeeMinor;
  if (!Number.isSafeInteger(totalMinor) || totalMinor > 100_000_000) {
    throw new Error("ORDER_TOTAL_INVALID");
  }
  if (
    input.claimedDeliveryFeeMinor !== undefined &&
    Number(input.claimedDeliveryFeeMinor) !== deliveryFeeMinor
  ) {
    throw new Error("DELIVERY_FEE_MISMATCH");
  }
  if (
    input.claimedTotalMinor !== undefined &&
    Number(input.claimedTotalMinor) !== totalMinor
  ) {
    throw new Error("ORDER_TOTAL_MISMATCH");
  }
  return {
    fulfillmentType: fulfillment as "pickup" | "delivery",
    paymentType: payment as "cash" | "online" | "bnpl" | "transfer",
    subtotalMinor,
    deliveryFeeMinor,
    totalMinor,
    requiresMerchantReview:
      payment === "bnpl" ||
      (payment === "online" && fulfillment === "delivery"),
  };
}

async function requireManager(
  data: any,
  context: functions.https.CallableContext,
) {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign in is required.",
    );
  }
  if (!context.app) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "App verification is required.",
    );
  }
  const storeId = String(data?.storeId ?? "").trim();
  await assertCallableStoreAccess(context, storeId, ["owner", "admin"]);
  return storeId;
}

export const getMerchantOrderingOptionsV1 = functions.https.onCall(
  async (data, context) => {
    const storeId = await requireManager(data, context);
    const snapshot = await db.doc(`merchantCommerceSettings/${storeId}`).get();
    return {
      ...merchantOrderingOptionsFrom(snapshot.data()),
      configured: snapshot.exists,
    };
  },
);

export const updateMerchantOrderingOptionsV1 = functions.https.onCall(
  async (data, context) => {
    const storeId = await requireManager(data, context);
    let options: MerchantOrderingOptions;
    try {
      options = merchantOrderingOptionsUpdate(data);
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      const message =
        code === "SERVICE_AREA_REQUIRED"
          ? "Add a short delivery service-area description."
          : code === "DELIVERY_FEE_INVALID"
            ? "Enter a valid flat delivery fee."
            : "Review the order options and try again.";
      throw new functions.https.HttpsError("invalid-argument", message);
    }
    const now = FieldValue.serverTimestamp();
    await db.runTransaction(async (tx) => {
      const settingsRef = db.doc(`merchantCommerceSettings/${storeId}`);
      const existingSettings = await tx.get(settingsRef);
      tx.set(
        settingsRef,
        {
          ...options,
          merchantId: storeId,
          configured: true,
          ...(!existingSettings.exists ? { createdAt: now } : {}),
          updatedAt: now,
          updatedBy: context.auth!.uid,
          auditVersion: MERCHANT_ORDERING_OPTIONS_VERSION,
        },
        { merge: true },
      );
      tx.set(
        db.doc(`users/${storeId}`),
        { commerceOptionsConfigured: true, updatedAt: now },
        { merge: true },
      );
    });
    return { ...options, configured: true };
  },
);
