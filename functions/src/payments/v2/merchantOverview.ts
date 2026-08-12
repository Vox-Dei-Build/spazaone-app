import { db, functions } from "../../config/main";
import { authorizeCallableMerchantOrBot } from "../../security/requestAuth";
import { requireStoreId } from "../../stores/storeAccess";
import { paymentReadiness } from "./readiness";

function timestampMillis(value: unknown): number {
  const candidate = value as { toMillis?: () => number } | undefined;
  return typeof candidate?.toMillis === "function" ? candidate.toMillis() : 0;
}

export const getMerchantPaymentOverviewV2 = functions.https.onCall(
  async (data, context) => {
    const merchantId = requireStoreId(data?.merchantId);
    if (!(await authorizeCallableMerchantOrBot(context, merchantId))) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Access denied.",
      );
    }
    const [profile, settlements, readiness] = await Promise.all([
      db.doc(`merchantPaymentProfiles/${merchantId}`).get(),
      db
        .collection("settlements")
        .where("merchantId", "==", merchantId)
        .limit(50)
        .get(),
      paymentReadiness({ merchantId, purpose: "merchant_order" }),
    ]);
    const profileData = profile.data() ?? {};
    const recentSettlements = settlements.docs
      .map((doc) => {
        const value = doc.data();
        return {
          settlementId: doc.id,
          orderId: String(value.orderId ?? ""),
          status: String(value.status ?? "pending"),
          grossAmountMinor: Number(value.grossAmountMinor ?? 0),
          platformFeeMinor: Number(value.platformFeeMinor ?? 0),
          providerFeeMinor: Number(value.providerFeeMinor ?? 0),
          merchantNetProceedsMinor: Number(value.merchantNetProceedsMinor ?? 0),
          createdAtMs: timestampMillis(value.createdAt),
        };
      })
      .sort((left, right) => right.createdAtMs - left.createdAtMs)
      .slice(0, 20);
    return {
      merchantId,
      readiness,
      profile: {
        status: String(profileData.status ?? "not_started"),
        bankVerificationStatus: String(
          profileData.bankVerificationStatus ?? "not_started",
        ),
        bankName: String(profileData.bankName ?? ""),
        resolvedAccountName: String(profileData.resolvedAccountName ?? ""),
        maskedAccount: profileData.accountLast4
          ? `•••• ${String(profileData.accountLast4)}`
          : "",
      },
      settlements: recentSettlements,
    };
  },
);
