import { functions } from "../config/main";
import { assertCallableStoreAccess } from "../stores/storeAccess";
import {
  getCjProductDetails,
  quoteCjVariant,
  searchCjProducts,
} from "./cjClient";
import { commercePaymentsEnabled } from "./readiness";

const cjRuntime = functions.runWith({ secrets: ["CJ_API_KEY"] });

function cleanId(value: unknown, field: string): string {
  const id = String(value ?? "").trim();
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(id)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `A valid ${field} is required.`,
    );
  }
  return id;
}

export function publicCjError(error: unknown): functions.https.HttpsError {
  const code = error instanceof Error ? error.message : "";
  if (code === "CJ_NOT_CONFIGURED" || code === "CJ_AUTH_FAILED") {
    return new functions.https.HttpsError(
      "failed-precondition",
      "CJdropshipping is not connected to Spaza One yet.",
    );
  }
  if (code === "CJ_OUT_OF_STOCK") {
    return new functions.https.HttpsError(
      "failed-precondition",
      "That variant is currently out of stock.",
    );
  }
  if (code === "CJ_NO_SHIPPING_TO_ZA") {
    return new functions.https.HttpsError(
      "failed-precondition",
      "That variant cannot currently be delivered to South Africa.",
    );
  }
  if (code.includes("VARIANT") || code.includes("PRODUCT")) {
    return new functions.https.HttpsError(
      "not-found",
      "That CJdropshipping product is no longer available.",
    );
  }
  if (code.startsWith("CJ_FX")) {
    return new functions.https.HttpsError(
      "unavailable",
      "Live supplier pricing is temporarily unavailable. Please try again.",
    );
  }
  return new functions.https.HttpsError(
    "unavailable",
    "CJdropshipping could not be reached. Please try again.",
  );
}

async function authorize(
  data: unknown,
  context: functions.https.CallableContext,
): Promise<Record<string, unknown>> {
  const input =
    data && typeof data === "object" ? (data as Record<string, unknown>) : {};
  await assertCallableStoreAccess(context, input.storeId);
  return input;
}

/** Seller-authenticated CJ catalog search; credentials remain server-side. */
export const searchCjSupplierCatalog = cjRuntime.https.onCall(
  async (data, context) => {
    const input = await authorize(data, context);
    const query = String(input.query ?? "")
      .trim()
      .slice(0, 100);
    const page = Number(input.page ?? 1);
    if (!Number.isSafeInteger(page) || page < 1 || page > 1000) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Choose a valid catalog page.",
      );
    }
    try {
      const result = await searchCjProducts({ query, page, size: 20 });
      return {
        ...result,
        digitalPaymentsEnabled: commercePaymentsEnabled(),
      };
    } catch (error) {
      console.error("searchCjSupplierCatalog failed", error);
      throw publicCjError(error);
    }
  },
);

/** Returns current CJ variants and server-converted product estimates. */
export const getCjSupplierProduct = cjRuntime.https.onCall(
  async (data, context) => {
    const input = await authorize(data, context);
    const productId = cleanId(input.productId, "productId");
    try {
      return await getCjProductDetails(productId);
    } catch (error) {
      console.error("getCjSupplierProduct failed", error);
      throw publicCjError(error);
    }
  },
);

/** Calculates a current landed-cost quote to South Africa. */
export const quoteCjSupplierVariant = cjRuntime.https.onCall(
  async (data, context) => {
    const input = await authorize(data, context);
    const productId = cleanId(input.productId, "productId");
    const variantId = cleanId(input.variantId, "variantId");
    const postalCode = String(input.postalCode ?? "").trim();
    if (postalCode && !/^\d{4}$/.test(postalCode)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Enter a valid four-digit South African postal code.",
      );
    }
    try {
      return await quoteCjVariant({ productId, variantId, postalCode });
    } catch (error) {
      console.error("quoteCjSupplierVariant failed", error);
      throw publicCjError(error);
    }
  },
);
