import { db } from "../config/main";

export type ManualPaymentOption = "eft" | "pay_at_shop";
export type SupplierManualPaymentOption = "cash" | "eft";

export type MerchantBanking = {
  bankName: string;
  accountHolderName: string;
  accountNumber: string;
  accountType: string;
  branchCode: string;
};

function clean(value: unknown, max = 160): string {
  return String(value ?? "")
    .trim()
    .replace(/\s+/g, " ")
    .slice(0, max);
}

export async function merchantManualPaymentOptions(
  merchantId: string,
): Promise<{
  paymentOptions: ManualPaymentOption[];
  banking: MerchantBanking | null;
}> {
  const merchantRef = db.doc(`users/${merchantId}`);
  const [merchant, bankingSnapshot] = await Promise.all([
    merchantRef.get(),
    merchantRef.collection("bankingDetails").limit(1).get(),
  ]);
  const raw = bankingSnapshot.empty ? {} : bankingSnapshot.docs[0].data();
  const banking: MerchantBanking = {
    bankName: clean(raw.bankName),
    accountHolderName: clean(raw.accountHolderName),
    accountNumber: clean(raw.accountNumber, 60),
    accountType: clean(raw.accountType, 80),
    branchCode: clean(raw.branchCode, 40),
  };
  const bankingComplete = Boolean(
    banking.bankName &&
      banking.accountHolderName &&
      banking.accountNumber &&
      banking.accountType &&
      banking.branchCode,
  );
  const merchantData = merchant.data() ?? {};
  const paymentOptions =
    merchantData.paymentOptions &&
    typeof merchantData.paymentOptions === "object"
      ? merchantData.paymentOptions
      : {};
  // Pasella merchants are existing physical shops, so released merchants
  // remain reachable without a migration. The customer must still explicitly
  // choose this option at review; either supported flag can explicitly disable
  // it before it is offered.
  const acceptsPayAtShop =
    merchant.exists &&
    merchantData.acceptsPayAtShop !== false &&
    paymentOptions.payAtShop !== false;
  return {
    paymentOptions: [
      ...(bankingComplete ? (["eft"] as const) : []),
      ...(acceptsPayAtShop ? (["pay_at_shop"] as const) : []),
    ],
    banking: bankingComplete ? banking : null,
  };
}

/**
 * Release-safe supplier payments are arranged directly with the seller.
 * Cash is available for every active merchant; EFT is exposed only when the
 * seller has a complete saved banking profile. Neither option initializes a
 * provider transaction or claims that Spaza One received the money.
 */
export async function merchantSupplierPaymentOptions(
  merchantId: string,
): Promise<{
  paymentOptions: SupplierManualPaymentOption[];
  banking: MerchantBanking | null;
}> {
  const merchantRef = db.doc(`users/${merchantId}`);
  const [merchant, bankingSnapshot] = await Promise.all([
    merchantRef.get(),
    merchantRef.collection("bankingDetails").limit(1).get(),
  ]);
  if (!merchant.exists) return { paymentOptions: [], banking: null };
  const raw = bankingSnapshot.empty ? {} : bankingSnapshot.docs[0].data();
  const banking: MerchantBanking = {
    bankName: clean(raw.bankName),
    accountHolderName: clean(raw.accountHolderName),
    accountNumber: clean(raw.accountNumber, 60),
    accountType: clean(raw.accountType, 80),
    branchCode: clean(raw.branchCode, 40),
  };
  const bankingComplete = Boolean(
    banking.bankName &&
      banking.accountHolderName &&
      banking.accountNumber &&
      banking.accountType &&
      banking.branchCode,
  );
  const merchantData = merchant.data() ?? {};
  const configured =
    merchantData.paymentOptions &&
    typeof merchantData.paymentOptions === "object"
      ? merchantData.paymentOptions
      : {};
  const acceptsCash =
    merchantData.acceptsCash !== false && configured.cash !== false;
  const acceptsEft = bankingComplete && configured.eft !== false;
  return {
    paymentOptions: [
      ...(acceptsCash ? (["cash"] as const) : []),
      ...(acceptsEft ? (["eft"] as const) : []),
    ],
    banking: bankingComplete ? banking : null,
  };
}
