/**
 * @function getShopContextBotHttp
 * @description HTTP endpoint for Botpress to gate WhatsApp shopping. Prefers merchantId from bot.
 */
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import { normalizePhoneNumber } from "../utils/phoneUtils";

function versionLt(a = "0.0.0", b = "0.0.0"): boolean {
  const pa = a.split(".").map(Number);
  const pb = b.split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const x = pa[i] || 0;
    const y = pb[i] || 0;
    if (x < y) return true;
    if (x > y) return false;
  }
  return false;
}

function cleanRefCode(value: unknown): string {
  return String(value || "")
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, "");
}

async function findMerchantCustomerId(
  merchantId: string,
  customerPhone: unknown,
): Promise<string | undefined> {
  const normalized = normalizePhoneNumber(
    String(customerPhone || "").replace("whatsapp:", ""),
  );
  if (!normalized) return undefined;

  const snap = await db
    .collection("users")
    .doc(merchantId)
    .collection("customers")
    .where("number", "==", normalized)
    .limit(1)
    .get();
  return snap.empty ? undefined : snap.docs[0].id;
}

async function findOrCreateMerchantCustomerId(args: {
  merchantId: string;
  customerPhone: unknown;
  customerName?: unknown;
  sourceRefCode?: string;
}): Promise<string | undefined> {
  const normalized = normalizePhoneNumber(
    String(args.customerPhone || "").replace("whatsapp:", ""),
  );
  if (!normalized) return undefined;

  const customersRef = db
    .collection("users")
    .doc(args.merchantId)
    .collection("customers");
  const existing = await customersRef
    .where("number", "==", normalized)
    .limit(1)
    .get();
  if (!existing.empty) return existing.docs[0].id;

  const customerRef = customersRef.doc();
  const displayName =
    String(args.customerName || "").trim() ||
    `WhatsApp ${normalized.slice(-4)}`;
  await customerRef.set({
    category: "Customer",
    name: displayName,
    number: normalized,
    lastTransaction: {
      amount: 0,
      remarks: "No transactions yet",
      status: "PAID",
      type: "Payment",
      date: admin.firestore.FieldValue.serverTimestamp(),
    },
    balance: 0,
    isNPA: false,
    source: "whatsapp_ordering_link",
    sourceRefCode: args.sourceRefCode || null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return customerRef.id;
}

async function markRefCodeUsed(refCode: string | undefined): Promise<void> {
  if (!refCode) return;
  await db
    .collection("merchant_referrals")
    .doc(refCode)
    .set(
      {
        useCount: admin.firestore.FieldValue.increment(1),
        lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
}

export const getShopContextBotHttp = functions.https.onRequest(
  async (req, res) => {
    if (req.method !== "POST") {
      console.warn("Rejected non-POST request", { method: req.method });
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }

    const {
      customerPhone,
      merchantId,
      refCode: rawRefCode,
      autoCreateCustomer = false,
      customerName,
    } = req.body || {};
    const refCode = cleanRefCode(rawRefCode);
    console.log("Incoming gate check", { customerPhone, merchantId, refCode });

    try {
      const cfgSnap = await db.doc("config/app").get();
      const minVersion =
        cfgSnap.get("minMerchantVersionForWhatsApp") || "3.0.0";
      console.log("Config loaded", { minVersion });

      // ---------- Merchant resolution (prefer merchantId from bot) ----------
      let mid: string | undefined = merchantId;

      // If no merchantId but a refCode exists, try resolve via referral
      if (!mid && refCode) {
        const ref = await db
          .collection("merchant_referrals")
          .doc(refCode)
          .get();
        const status = String(ref.get("status") || "active");
        if (ref.exists && status === "active") mid = ref.get("merchantId");
        console.log("Resolved merchantId from refCode", { refCode, mid });
      }

      // If still no merchantId, optionally fall back to customer assignment (only if customerPhone present)
      let customerId: string | undefined;
      if (!mid && customerPhone) {
        const custSnap = await db
          .collection("customers")
          .where("phone", "==", customerPhone)
          .limit(1)
          .get();
        const customerDoc = custSnap.empty ? null : custSnap.docs[0];
        customerId = customerDoc?.id;
        const assignedMerchantId = customerDoc?.get("assignedMerchantId") as
          | string
          | undefined;
        console.log("Resolved customer for fallback", {
          found: !!customerDoc,
          customerId,
          assignedMerchantId,
        });
        if (assignedMerchantId) {
          mid = assignedMerchantId;
          console.log("Resolved merchantId from customer assignment", { mid });
        }
      }

      // If we STILL don't have a merchantId → NO_MERCHANT (with pilot alternatives)
      if (!mid) {
        console.log("No merchantId resolved, returning NO_MERCHANT");
        const alts = await db
          .collection("users")
          .where("whatsappEligibleOverride", "==", true)
          .limit(5)
          .get();
        const alternatives = alts.docs.map((d) => ({
          id: d.id,
          name: d.get("name") as string,
        }));
        res.json({
          state: "NO_MERCHANT",
          customerId: customerId || "ghost",
          alternatives,
        });
        return;
      }

      const existingMerchantCustomerId = await findMerchantCustomerId(
        mid,
        customerPhone,
      );
      if (existingMerchantCustomerId) {
        customerId = existingMerchantCustomerId;
      }

      // ---------- Load merchant + gate ----------
      const mSnap = await db.collection("users").doc(mid).get();
      if (!mSnap.exists) {
        console.log("Merchant not found in Firestore", { mid });
        res.json({
          state: "NO_MERCHANT",
          customerId: customerId || "ghost",
          alternatives: [],
        });
        return;
      }

      const m = mSnap.data() || {};

      // Banking details: optional subcollection on the merchant doc.
      // Used by the bot to surface EFT/deposit details inline in the
      // confirmation prompt for Transfer payments. Missing fields are
      // tolerated downstream; an empty object simply skips the block.
      let banking: {
        bankName?: string;
        accountHolderName?: string;
        accountNumber?: string;
        accountType?: string;
        branchCode?: string;
        reference?: string;
      } | null = null;
      try {
        const bSnap = await db
          .collection("users")
          .doc(mSnap.id)
          .collection("bankingDetails")
          .limit(1)
          .get();
        if (!bSnap.empty) {
          const b = bSnap.docs[0].data() || {};
          banking = {
            bankName: b.bankName || undefined,
            accountHolderName: b.accountHolderName || undefined,
            accountNumber: b.accountNumber || undefined,
            accountType: b.accountType || undefined,
            branchCode: b.branchCode || undefined,
            reference: b.reference || undefined,
          };
        }
      } catch (bankErr) {
        console.warn("Banking details lookup failed (non-fatal)", {
          mid: mSnap.id,
          err: (bankErr as Error)?.message,
        });
      }

      const merchant = {
        id: mSnap.id,
        name: m.name,
        appVersion: m.appVersion, // may be undefined pre-release
        isPaused: !!m.isPaused,
        hasProducts: !!m.hasProducts,
        whatsappEligibleOverride: !!m.whatsappEligibleOverride,
        forceEnableUntil: m.forceEnableUntil || null, // Firestore Timestamp or null
        minRequiredVersion: minVersion,
        banking,
      };
      console.log("Merchant loaded", {
        mid: merchant.id,
        name: merchant.name,
        appVersion: merchant.appVersion,
        isPaused: merchant.isPaused,
        hasProducts: merchant.hasProducts,
        whatsappEligibleOverride: merchant.whatsappEligibleOverride,
        forceEnableUntil: merchant.forceEnableUntil?.toString?.(),
      });

      if (merchant.isPaused) {
        console.log("Merchant is paused → MERCHANT_OFFLINE", { mid });
        res.json({
          state: "MERCHANT_OFFLINE",
          customerId: customerId || "ghost",
          merchant,
        });
        return;
      }

      // Catalog (fallback: check if any product exists)
      let hasCatalog = merchant.hasProducts;
      if (!hasCatalog) {
        const cat = await db
          .collection("users")
          .doc(merchant.id)
          .collection("products")
          .limit(1)
          .get();
        hasCatalog = !cat.empty;
      }
      if (!hasCatalog) {
        console.log("Merchant catalog empty", { mid });
        res.json({
          state: "CATALOG_EMPTY",
          customerId: customerId || "ghost",
          merchant: { ...merchant, hasProducts: false },
        });
        return;
      }

      // Pilot overrides
      const nowMs = Timestamp.now().toMillis();
      const forceUntilMs =
        typeof (merchant as any).forceEnableUntil?.toMillis === "function"
          ? (merchant as any).forceEnableUntil.toMillis()
          : 0;
      if (merchant.whatsappEligibleOverride || forceUntilMs >= nowMs) {
        const resolvedCustomerId =
          refCode && autoCreateCustomer
            ? await findOrCreateMerchantCustomerId({
                merchantId: merchant.id,
                customerPhone,
                customerName,
                sourceRefCode: refCode,
              })
            : customerId;
        if (resolvedCustomerId) await markRefCodeUsed(refCode);
        console.log("Merchant override or force window active → OK", { mid });
        res.json({
          state: "OK",
          customerId: resolvedCustomerId || customerId || "ghost",
          merchant: { ...merchant, eligible: true },
        });
        return;
      }

      // Version gating
      if (!merchant.appVersion) {
        console.log("Merchant appVersion missing → NEEDS_UPDATE", { mid });
        res.json({
          state: "MERCHANT_NEEDS_UPDATE",
          customerId: customerId || "ghost",
          merchant: { ...merchant, reason: "version_unknown" },
        });
        return;
      }
      if (versionLt(merchant.appVersion, minVersion)) {
        console.log("Merchant appVersion too low → NEEDS_UPDATE", {
          mid,
          appVersion: merchant.appVersion,
          minVersion,
        });
        res.json({
          state: "MERCHANT_NEEDS_UPDATE",
          customerId: customerId || "ghost",
          merchant: { ...merchant, reason: "version_too_low" },
        });
        return;
      }

      console.log("Merchant passed all checks → OK", { mid });
      const resolvedCustomerId =
        refCode && autoCreateCustomer
          ? await findOrCreateMerchantCustomerId({
              merchantId: merchant.id,
              customerPhone,
              customerName,
              sourceRefCode: refCode,
            })
          : customerId;
      if (resolvedCustomerId) await markRefCodeUsed(refCode);
      res.json({
        state: "OK",
        customerId: resolvedCustomerId || customerId || "ghost",
        merchant: { ...merchant, eligible: true },
      });
      return;
    } catch (e: any) {
      console.error("Error in getShopContextBotHttp", e);
      res.status(500).json({ error: e?.message || "internal_error" });
      return;
    }
  },
);
