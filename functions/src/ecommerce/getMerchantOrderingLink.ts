import * as admin from "firebase-admin";
import { randomBytes } from "crypto";
import { db, functions } from "../config/main";
import { formatPhoneNumber } from "../utils/phoneUtils";
import { assertCallableStoreAccess } from "../stores/storeAccess";

const CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const CODE_LENGTH = 6;

interface OrderingLinkData {
  action?: "get" | "regenerate" | "revoke";
  storeId?: string;
}

export interface OrderingLinkResult {
  code: string;
  pasellaWhatsappNumber: string;
  orderingUrl: string;
  fallbackText: string;
  created: boolean;
  regenerated: boolean;
}

/**
 * Returns the merchant's active ordering link, creating one when necessary.
 *
 * Product promotions call this server-side so merchants never have to visit
 * Settings before the "Order on WhatsApp" button can work.
 */
export async function ensureMerchantOrderingLink(
  merchantId: string,
): Promise<OrderingLinkResult> {
  const merchantRef = db.collection("users").doc(merchantId);
  const merchantSnap = await merchantRef.get();
  if (!merchantSnap.exists) {
    throw new functions.https.HttpsError(
      "not-found",
      "Merchant profile was not found.",
    );
  }

  const existing = merchantSnap.get("whatsappOrdering") as
    | { code?: string; status?: string }
    | undefined;
  if (existing?.code && existing.status === "active") {
    return buildResult(existing.code, {
      created: false,
      regenerated: false,
    });
  }

  const code = await createUniqueCode(merchantId);
  const result = buildResult(code, {
    created: true,
    regenerated: false,
  });
  await merchantRef.set(
    {
      whatsappOrdering: {
        code,
        status: "active",
        pasellaWhatsappNumber: result.pasellaWhatsappNumber,
        orderingUrl: result.orderingUrl,
        fallbackText: result.fallbackText,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    },
    { merge: true },
  );
  return result;
}

export const getMerchantOrderingLink = functions.https.onCall(
  async (
    data: OrderingLinkData | undefined,
    context,
  ): Promise<OrderingLinkResult | { revoked: true }> => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in before creating an ordering link.",
      );
    }
    const merchantId = String(data?.storeId ?? context.auth.uid).trim();
    await assertCallableStoreAccess(context, merchantId);

    const action = data?.action ?? "get";
    const merchantRef = db.collection("users").doc(merchantId);
    const merchantSnap = await merchantRef.get();
    if (!merchantSnap.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Merchant profile was not found.",
      );
    }

    const existing = merchantSnap.get("whatsappOrdering") as
      | { code?: string; status?: string }
      | undefined;

    if (action === "revoke") {
      if (existing?.code) {
        await revokeCode(existing.code, merchantId);
      }
      await merchantRef.set(
        {
          whatsappOrdering: {
            ...(existing ?? {}),
            status: "revoked",
            revokedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true },
      );
      return { revoked: true };
    }

    if (
      action !== "regenerate" &&
      existing?.code &&
      existing.status === "active"
    ) {
      return buildResult(existing.code, {
        created: false,
        regenerated: false,
      });
    }

    if (action === "regenerate" && existing?.code) {
      await revokeCode(existing.code, merchantId);
    }

    const code = await createUniqueCode(merchantId);
    const result = buildResult(code, {
      created: true,
      regenerated: action === "regenerate",
    });
    await merchantRef.set(
      {
        whatsappOrdering: {
          code,
          status: "active",
          pasellaWhatsappNumber: result.pasellaWhatsappNumber,
          orderingUrl: result.orderingUrl,
          fallbackText: result.fallbackText,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
      { merge: true },
    );

    return result;
  },
);

async function createUniqueCode(merchantId: string): Promise<string> {
  for (let attempt = 0; attempt < 20; attempt++) {
    const code = randomCode();
    const ref = db.collection("merchant_referrals").doc(code);
    const created = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.exists) return false;
      tx.create(ref, {
        merchantId,
        status: "active",
        type: "whatsapp_ordering",
        useCount: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (created) return code;
  }
  throw new functions.https.HttpsError(
    "resource-exhausted",
    "Could not allocate an ordering code. Please try again.",
  );
}

async function revokeCode(code: string, merchantId: string): Promise<void> {
  await db.collection("merchant_referrals").doc(code).set(
    {
      merchantId,
      status: "revoked",
      revokedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function randomCode(): string {
  const bytes = randomBytes(CODE_LENGTH);
  let code = "";
  for (const byte of bytes) {
    code += CODE_ALPHABET[byte % CODE_ALPHABET.length];
  }
  return code;
}

function buildResult(
  code: string,
  flags: { created: boolean; regenerated: boolean },
): OrderingLinkResult {
  const pasellaWhatsappNumber = configuredPasellaWhatsappNumber();
  const e164 = formatPhoneNumber(pasellaWhatsappNumber);
  if (!e164) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "SpazaOne ordering WhatsApp number is not configured.",
    );
  }
  const text = `shop ${code}`;
  const orderingUrl = `https://wa.me/${e164.replace(/\D/g, "")}?text=${encodeURIComponent(text)}`;
  return {
    code,
    pasellaWhatsappNumber: e164,
    orderingUrl,
    fallbackText: `Send ${text.toUpperCase()} to ${e164} on WhatsApp.`,
    created: flags.created,
    regenerated: flags.regenerated,
  };
}

export function configuredPasellaWhatsappNumber(): string {
  const cfg = functions.config();
  return (
    cfg.ordering?.whatsapp_number ||
    cfg.twilio?.customer_whatsapp_number ||
    cfg.twilio?.number ||
    ""
  );
}
