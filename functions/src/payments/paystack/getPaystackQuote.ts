import { functions } from "../../config/main";

/**
 * getPaystackQuote
 * Returns Paystack fees (ZAR) and net payout for a given amount and method.
 *
 * Methods:
 * - "local_card"  -> 2.9% + R1.00 (excl VAT)
 * - "eft"         -> 2.0% (no flat fee) (excl VAT)
 * - "international" -> 3.1% + R1.00 (excl VAT)
 *
 * All fees exclude VAT; function returns VAT and totals too.
 * Settlement/payout fee (R3.00 excl VAT) is optional because you usually
 * withdraw aggregated balances — pass includePayout=true to factor it in.
 */
export const getPaystackQuote = functions.https.onCall(async (data) => {
  const amount = Number(data?.amountZar);
  const method = String(data?.method || "local_card") as
    | "local_card"
    | "eft"
    | "international";
  const includePayout = Boolean(data?.includePayout || false);

  if (!Number.isFinite(amount) || amount <= 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "amountZar must be > 0 (rands).",
    );
  }

  const VAT = 0.15;
  const R1 = 1.0;
  const PAYOUT_FEE_EX_VAT = includePayout ? 3.0 : 0.0;

  let pct = 0;
  let flat = 0;

  switch (method) {
    case "local_card":
      pct = 0.029;
      flat = R1;
      break;
    case "eft":
      pct = 0.02;
      flat = 0;
      break;
    case "international":
      pct = 0.031;
      flat = R1;
      break;
    default:
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Unsupported method.",
      );
  }

  const feeExVat = amount * pct + flat;
  const vat = feeExVat * VAT;
  const feeInclVat = feeExVat + vat;

  const payoutFeeExVat = PAYOUT_FEE_EX_VAT;
  const payoutVat = payoutFeeExVat * VAT;
  const payoutFeeInclVat = payoutFeeExVat + payoutVat;

  const totalFeesInclVat = feeInclVat + payoutFeeInclVat;
  const netToMerchant = amount - totalFeesInclVat;

  const r = (n: number) => Math.round(n * 100) / 100;

  return {
    amount: r(amount),
    method,
    feeExVat: r(feeExVat),
    vat: r(vat),
    feeInclVat: r(feeInclVat),
    payoutFeeExVat: r(payoutFeeExVat),
    payoutVat: r(payoutVat),
    payoutFeeInclVat: r(payoutFeeInclVat),
    totalFeesInclVat: r(totalFeesInclVat),
    netToMerchant: r(netToMerchant),
  };
});
