import { randomBytes } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { formatPhoneNumber } from "../utils/phoneUtils";
import { assertCallableStoreAccess } from "../stores/storeAccess";

const CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
const CODE_LENGTH = 6;
const MAX_CODE_ATTEMPTS = 20;

interface OrderingLinkData {
  action?: "get" | "regenerate" | "revoke";
  storeId?: string;
}

interface StoredOrderingLink {
  code?: string;
  status?: string;
  pasellaWhatsappNumber?: string;
  orderingUrl?: string;
  fallbackText?: string;
}

export interface OrderingLinkResult {
  code: string;
  pasellaWhatsappNumber: string;
  orderingUrl: string;
  fallbackText: string;
  created: boolean;
  regenerated: boolean;
}

type LinkTransactionResult =
  | { kind: "collision" }
  | {
      kind: "existing";
      link: StoredOrderingLink & { code: string };
    }
  | { kind: "created" };

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
    | StoredOrderingLink
    | undefined;
  if (isActiveLink(existing)) {
    return resultFromStoredLink(existing);
  }

  return createMerchantOrderingLink(merchantId, false);
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
    if (!(["get", "regenerate", "revoke"] as const).includes(action)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Choose a supported ordering-link action.",
      );
    }

    if (action === "revoke") {
      await revokeMerchantOrderingLink(merchantId);
      return { revoked: true };
    }

    const merchantRef = db.collection("users").doc(merchantId);
    const merchantSnap = await merchantRef.get();
    if (!merchantSnap.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Merchant profile was not found.",
      );
    }
    const existing = merchantSnap.get("whatsappOrdering") as
      | StoredOrderingLink
      | undefined;
    if (action === "get" && isActiveLink(existing)) {
      return resultFromStoredLink(existing);
    }

    return createMerchantOrderingLink(merchantId, action === "regenerate");
  },
);

/**
 * Allocates and persists a link in one transaction. The direct WhatsApp
 * destination is validated before a code is generated, so a missing release
 * configuration cannot leave an active orphan in `merchant_referrals`.
 */
async function createMerchantOrderingLink(
  merchantId: string,
  regenerate: boolean,
): Promise<OrderingLinkResult> {
  const whatsappNumber = requireConfiguredOrderingWhatsappNumber();
  const merchantRef = db.collection("users").doc(merchantId);

  for (let attempt = 0; attempt < MAX_CODE_ATTEMPTS; attempt++) {
    const code = randomCode();
    const referralRef = db.collection("merchant_referrals").doc(code);
    const result = buildResultForNumber(code, whatsappNumber, {
      created: true,
      regenerated: regenerate,
    });

    const outcome = await db.runTransaction<LinkTransactionResult>(
      async (tx) => {
        const [merchantSnap, referralSnap] = await Promise.all([
          tx.get(merchantRef),
          tx.get(referralRef),
        ]);
        if (!merchantSnap.exists) {
          throw new functions.https.HttpsError(
            "not-found",
            "Merchant profile was not found.",
          );
        }

        const current = merchantSnap.get("whatsappOrdering") as
          | StoredOrderingLink
          | undefined;
        if (!regenerate && isActiveLink(current)) {
          return { kind: "existing", link: current };
        }
        if (referralSnap.exists) return { kind: "collision" };

        tx.create(referralRef, {
          merchantId,
          status: "active",
          type: "whatsapp_ordering",
          useCount: 0,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        if (regenerate && current?.code && current.code !== code) {
          tx.set(
            db.collection("merchant_referrals").doc(current.code),
            {
              merchantId,
              status: "revoked",
              revokedAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
        }
        tx.set(
          merchantRef,
          {
            whatsappOrdering: {
              code,
              status: "active",
              pasellaWhatsappNumber: result.pasellaWhatsappNumber,
              orderingUrl: result.orderingUrl,
              fallbackText: result.fallbackText,
              createdAt: FieldValue.serverTimestamp(),
              updatedAt: FieldValue.serverTimestamp(),
            },
          },
          { merge: true },
        );
        return { kind: "created" };
      },
    );

    if (outcome.kind === "collision") continue;
    if (outcome.kind === "existing") {
      return resultFromStoredLink(outcome.link);
    }
    return result;
  }

  throw new functions.https.HttpsError(
    "resource-exhausted",
    "Could not allocate an ordering code. Please try again.",
  );
}

async function revokeMerchantOrderingLink(merchantId: string): Promise<void> {
  const merchantRef = db.collection("users").doc(merchantId);
  await db.runTransaction(async (tx) => {
    const merchantSnap = await tx.get(merchantRef);
    if (!merchantSnap.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "Merchant profile was not found.",
      );
    }
    const existing = merchantSnap.get("whatsappOrdering") as
      | StoredOrderingLink
      | undefined;
    if (existing?.code) {
      tx.set(
        db.collection("merchant_referrals").doc(existing.code),
        {
          merchantId,
          status: "revoked",
          revokedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    tx.set(
      merchantRef,
      {
        whatsappOrdering: {
          ...(existing ?? {}),
          status: "revoked",
          revokedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
      },
      { merge: true },
    );
  });
}

function isActiveLink(
  link: StoredOrderingLink | undefined,
): link is StoredOrderingLink & { code: string } {
  return Boolean(link?.code && link.status === "active");
}

function resultFromStoredLink(
  link: StoredOrderingLink & { code: string },
): OrderingLinkResult {
  const storedNumber = formatPhoneNumber(link.pasellaWhatsappNumber ?? "");
  if (storedNumber && link.orderingUrl?.trim() && link.fallbackText?.trim()) {
    return {
      code: link.code,
      pasellaWhatsappNumber: storedNumber,
      orderingUrl: link.orderingUrl.trim(),
      fallbackText: link.fallbackText.trim(),
      created: false,
      regenerated: false,
    };
  }
  return buildResultForNumber(
    link.code,
    requireConfiguredOrderingWhatsappNumber(),
    { created: false, regenerated: false },
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

function buildResultForNumber(
  code: string,
  pasellaWhatsappNumber: string,
  flags: { created: boolean; regenerated: boolean },
): OrderingLinkResult {
  const text = `shop ${code}`;
  const orderingUrl =
    `https://wa.me/${pasellaWhatsappNumber.replace(/\D/g, "")}` +
    `?text=${encodeURIComponent(text)}`;
  return {
    code,
    pasellaWhatsappNumber,
    orderingUrl,
    fallbackText: `Send ${text.toUpperCase()} to ${pasellaWhatsappNumber} on WhatsApp.`,
    created: flags.created,
    regenerated: flags.regenerated,
  };
}

function requireConfiguredOrderingWhatsappNumber(): string {
  const configured = configuredPasellaWhatsappNumber();
  const formatted = formatPhoneNumber(configured);
  if (!formatted) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "The Spaza One ordering WhatsApp channel is not configured.",
    );
  }
  return formatted;
}

/**
 * The direct Botpress WhatsApp lane is the supported release transport.
 * Legacy Twilio variables intentionally do not participate in link creation.
 */
export function configuredPasellaWhatsappNumber(): string {
  const cfg = functions.config();
  return (
    process.env.ORDERING_WHATSAPP_NUMBER || cfg.ordering?.whatsapp_number || ""
  );
}
