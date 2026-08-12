import axios from "axios";
import { createHash } from "crypto";
import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import { paystackSecret } from "../../config/environment";
import { authenticateFirebaseRequest } from "../../security/requestAuth";
import { assertStoreAccess, requireStoreId } from "../../stores/storeAccess";
import { stableDocumentId } from "./domain";

function normalizedName(value: unknown): string {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
}

function accountNumber(value: unknown): string {
  const account = String(value ?? "").replace(/\s+/g, "");
  if (!/^\d{5,20}$/.test(account)) throw new Error("BANK_ACCOUNT_INVALID");
  return account;
}

function accountFingerprint(bankCode: string, account: string): string {
  return createHash("sha256")
    .update(`paystack-za\u001f${bankCode}\u001f${account}`)
    .digest("hex");
}

function publicError(error: unknown): { status: number; message: string } {
  if (error instanceof functions.https.HttpsError) {
    const status =
      error.code === "unauthenticated"
        ? 401
        : error.code === "permission-denied"
          ? 403
          : 400;
    return { status, message: error.message };
  }
  const code = error instanceof Error ? error.message : "";
  const known: Record<string, [number, string]> = {
    BANK_ACCOUNT_INVALID: [400, "Enter a valid bank account number."],
    BANK_NOT_SUPPORTED: [
      409,
      "That bank could not be matched safely. Contact support.",
    ],
    BANK_ACCOUNT_NOT_RESOLVED: [
      409,
      "Paystack could not verify that bank account.",
    ],
    PAYSTACK_SUBACCOUNT_INVALID: [
      502,
      "Paystack did not confirm the settlement profile.",
    ],
  };
  const mapped = known[code];
  return mapped
    ? { status: mapped[0], message: mapped[1] }
    : {
        status: 500,
        message: "Settlement verification is temporarily unavailable.",
      };
}

export const prepareMerchantSettlementProfileV2 = functions
  .runWith({ secrets: ["PAYSTACK_SECRET_KEY"] })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const uid = await authenticateFirebaseRequest(req, res);
      if (!uid) return;
      const merchantId = requireStoreId(req.body?.merchantId);
      await assertStoreAccess(uid, merchantId);
      const bankingDetailsId = String(req.body?.bankingDetailsId ?? "").trim();
      if (!/^[A-Za-z0-9_-]{1,200}$/.test(bankingDetailsId)) {
        res.status(400).json({ error: "Choose saved banking details." });
        return;
      }
      const [banking, merchant] = await Promise.all([
        db.doc(`users/${merchantId}/bankingDetails/${bankingDetailsId}`).get(),
        db.doc(`users/${merchantId}`).get(),
      ]);
      if (!banking.exists) {
        res.status(404).json({ error: "Banking details not found." });
        return;
      }
      const raw = banking.data() ?? {};
      const account = accountNumber(raw.accountNumber);
      const requestedBankName = String(raw.bankName ?? "").trim();
      const businessName = String(
        merchant.data()?.shopName ??
          merchant.data()?.businessName ??
          merchant.data()?.name ??
          raw.accountHolderName ??
          "Spaza One merchant",
      )
        .trim()
        .slice(0, 100);
      const secret = paystackSecret();
      const banksResponse = await axios.get("https://api.paystack.co/bank", {
        headers: { Authorization: `Bearer ${secret}` },
        params: { country: "south africa", currency: "ZAR", perPage: 200 },
        timeout: 15_000,
      });
      const banks = Array.isArray(banksResponse.data?.data)
        ? banksResponse.data.data
        : [];
      const bank = banks.find(
        (candidate: any) =>
          normalizedName(candidate?.name) === normalizedName(requestedBankName),
      );
      const bankCode = String(bank?.code ?? "").trim();
      if (!bankCode) throw new Error("BANK_NOT_SUPPORTED");
      const fingerprint = accountFingerprint(bankCode, account);
      const profileRef = db.doc(`merchantPaymentProfiles/${merchantId}`);
      const existing = await profileRef.get();
      const existingData = existing.data() ?? {};
      if (
        existingData.accountFingerprint === fingerprint &&
        /^ACCT_[A-Za-z0-9]+$/.test(
          String(existingData.paystackSubaccountCode ?? ""),
        )
      ) {
        res.status(200).json({
          merchantId,
          status: existingData.bankVerificationStatus,
          bankName: existingData.bankName,
          resolvedAccountName: existingData.resolvedAccountName,
          maskedAccount: `•••• ${existingData.accountLast4}`,
          accountFingerprint: fingerprint,
          deduped: true,
        });
        return;
      }
      const resolveResponse = await axios.get(
        "https://api.paystack.co/bank/resolve",
        {
          headers: { Authorization: `Bearer ${secret}` },
          params: { account_number: account, bank_code: bankCode },
          timeout: 15_000,
        },
      );
      const resolved = resolveResponse.data?.data ?? {};
      const resolvedAccount = String(resolved.account_number ?? "").trim();
      const resolvedAccountName = String(resolved.account_name ?? "").trim();
      if (
        resolveResponse.data?.status !== true ||
        resolvedAccount !== account ||
        !resolvedAccountName
      ) {
        throw new Error("BANK_ACCOUNT_NOT_RESOLVED");
      }
      const subaccountResponse = await axios.post(
        "https://api.paystack.co/subaccount",
        {
          business_name: businessName,
          bank_code: bankCode,
          account_number: account,
          percentage_charge: 1.5,
          description: `Spaza One settlement for ${merchantId}`,
        },
        {
          headers: { Authorization: `Bearer ${secret}` },
          timeout: 15_000,
        },
      );
      const subaccount = subaccountResponse.data?.data ?? {};
      const subaccountCode = String(subaccount.subaccount_code ?? "").trim();
      if (
        subaccountResponse.data?.status !== true ||
        !/^ACCT_[A-Za-z0-9]+$/.test(subaccountCode)
      ) {
        throw new Error("PAYSTACK_SUBACCOUNT_INVALID");
      }
      const holderMatches =
        normalizedName(raw.accountHolderName) ===
        normalizedName(resolvedAccountName);
      const auditId = stableDocumentId("audit", [
        merchantId,
        uid,
        fingerprint,
        String(Date.now()),
      ]);
      await db.runTransaction(async (tx) => {
        const current = await tx.get(profileRef);
        const previous = current.data() ?? {};
        const now = FieldValue.serverTimestamp();
        tx.set(
          profileRef,
          {
            merchantId,
            status: "pending_review",
            capabilities: {},
            bankVerificationStatus: "pending_review",
            bankName: String(bank.name ?? requestedBankName),
            bankCode,
            resolvedAccountName,
            submittedAccountHolderName: String(raw.accountHolderName ?? ""),
            accountHolderExactMatch: holderMatches,
            accountLast4: account.slice(-4),
            accountFingerprint: fingerprint,
            paystackSubaccountCode: subaccountCode,
            paystackSubaccountId: String(subaccount.id ?? ""),
            paystackSubaccountVerified: subaccount.is_verified === true,
            submittedBy: uid,
            submittedAt: now,
            schemaVersion: 2,
            updatedAt: now,
          },
          { merge: true },
        );
        tx.create(profileRef.collection("audit").doc(auditId), {
          auditId,
          merchantId,
          actorUid: uid,
          action: "settlement_profile_submitted",
          previousAccountFingerprint: previous.accountFingerprint ?? null,
          accountFingerprint: fingerprint,
          bankName: String(bank.name ?? requestedBankName),
          accountLast4: account.slice(-4),
          accountHolderExactMatch: holderMatches,
          createdAt: now,
        });
      });
      res.status(200).json({
        merchantId,
        status: "pending_review",
        bankName: String(bank.name ?? requestedBankName),
        resolvedAccountName,
        maskedAccount: `•••• ${account.slice(-4)}`,
        accountFingerprint: fingerprint,
        accountHolderExactMatch: holderMatches,
        deduped: false,
      });
    } catch (error) {
      console.error("[payments-v2] settlement profile preparation failed", {
        code: error instanceof Error ? error.message : "unknown",
      });
      const response = publicError(error);
      res.status(response.status).json({ error: response.message });
    }
  });

export const reviewMerchantSettlementProfileV2 = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in is required.",
      );
    }
    if (context.auth.token.spazaAdmin !== true) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Spaza One payment administration access is required.",
      );
    }
    const adminUid = context.auth.uid;
    const merchantId = requireStoreId(data?.merchantId);
    const expectedFingerprint = String(data?.accountFingerprint ?? "").trim();
    if (!/^[a-f0-9]{64}$/.test(expectedFingerprint)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "The reviewed account fingerprint is required.",
      );
    }
    const approved = data?.approved === true;
    const reason = String(data?.reason ?? "")
      .trim()
      .slice(0, 500);
    if (!reason) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "An audit reason is required.",
      );
    }
    const profileRef = db.doc(`merchantPaymentProfiles/${merchantId}`);
    const auditId = stableDocumentId("audit", [
      merchantId,
      adminUid,
      approved ? "approved" : "rejected",
      expectedFingerprint,
      String(Date.now()),
    ]);
    await db.runTransaction(async (tx) => {
      const profile = await tx.get(profileRef);
      const current = profile.data() ?? {};
      if (
        !profile.exists ||
        current.bankVerificationStatus !== "pending_review"
      ) {
        throw new functions.https.HttpsError(
          "failed-precondition",
          "This settlement profile is not awaiting review.",
        );
      }
      if (current.accountFingerprint !== expectedFingerprint) {
        throw new functions.https.HttpsError(
          "aborted",
          "The banking destination changed during review.",
        );
      }
      const now = FieldValue.serverTimestamp();
      tx.update(profileRef, {
        bankVerificationStatus: approved ? "approved" : "rejected",
        status: "pending_review",
        bankReviewedBy: adminUid,
        bankReviewedAt: now,
        bankReviewReason: reason,
        updatedAt: now,
      });
      tx.create(profileRef.collection("audit").doc(auditId), {
        auditId,
        merchantId,
        actorUid: adminUid,
        action: approved
          ? "settlement_profile_approved"
          : "settlement_profile_rejected",
        accountFingerprint: expectedFingerprint,
        reason,
        createdAt: now,
      });
    });
    return {
      merchantId,
      bankVerificationStatus: approved ? "approved" : "rejected",
    };
  },
);
