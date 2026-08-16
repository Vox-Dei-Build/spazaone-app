import { db, functions } from "../../config/main";
import { paystackProviderMode } from "../../config/environment";
import { authorizeCallableMerchantOrBot } from "../../security/requestAuth";
import { requireStoreId } from "../../stores/storeAccess";
import { buyerSafePaymentsV2 } from "./buyerReadiness";
import {
  addWorkingDays,
  normalizePaystackSettlementStatus,
} from "./settlementStatus";

function timestampMillis(value: unknown): number {
  const candidate = value as { toMillis?: () => number } | undefined;
  if (typeof candidate?.toMillis === "function") return candidate.toMillis();
  const parsed = Date.parse(String(value ?? ""));
  return Number.isFinite(parsed) ? parsed : 0;
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
    const [profile, settlements, paymentsV2] = await Promise.all([
      db.doc(`merchantPaymentProfiles/${merchantId}`).get(),
      db
        .collection("settlements")
        .where("merchantId", "==", merchantId)
        .limit(50)
        .get(),
      buyerSafePaymentsV2(merchantId),
    ]);
    const profileData = profile.data() ?? {};
    const pendingSettlement = (profileData.pendingSettlement ?? {}) as Record<
      string,
      unknown
    >;
    const displayedSettlement = pendingSettlement.accountFingerprint
      ? pendingSettlement
      : profileData;
    let currentProviderMode = "unknown";
    try {
      currentProviderMode = paystackProviderMode();
    } catch (_) {
      // A read remains available even when provider configuration is broken.
    }
    const recentSettlements = settlements.docs
      .map((doc) => {
        const value = doc.data();
        const createdAtMs = timestampMillis(value.createdAt);
        const providerSettlementAtMs = timestampMillis(
          value.providerSettlementAt,
        );
        const providerMode = String(
          value.providerMode ?? currentProviderMode,
        ).toLowerCase();
        const testOnly = value.testOnly === true || providerMode === "test";
        return {
          settlementId: doc.id,
          orderId: String(value.orderId ?? ""),
          status: normalizePaystackSettlementStatus(value.status),
          providerStatus: String(value.providerStatus ?? ""),
          providerMode,
          testOnly,
          currency: String(value.currency ?? "ZAR").toUpperCase(),
          grossAmountMinor: Number(value.grossAmountMinor ?? 0),
          platformFeeMinor: Number(value.platformFeeMinor ?? 0),
          providerFeeMinor: Number(value.providerFeeMinor ?? 0),
          merchantNetProceedsMinor: Number(value.merchantNetProceedsMinor ?? 0),
          createdAtMs,
          providerSettlementAtMs,
          expectedSettlementAtMs:
            providerSettlementAtMs ||
            (createdAtMs
              ? addWorkingDays(new Date(createdAtMs), 2).getTime()
              : 0),
        };
      })
      .sort((left, right) => right.createdAtMs - left.createdAtMs)
      .slice(0, 20);
    const zarSettlements = recentSettlements.filter(
      (settlement) => settlement.currency === "ZAR",
    );
    const totals = {
      currency: "ZAR",
      outstandingMinor: zarSettlements
        .filter(
          (settlement) =>
            !settlement.testOnly && settlement.status === "processing",
        )
        .reduce(
          (sum, settlement) => sum + settlement.merchantNetProceedsMinor,
          0,
        ),
      testOnlyMinor: zarSettlements
        .filter((settlement) => settlement.testOnly)
        .reduce(
          (sum, settlement) => sum + settlement.merchantNetProceedsMinor,
          0,
        ),
    };
    return {
      merchantId,
      // Backward-compatible 4.8.0 alias. New clients must use paymentsV2.
      readiness: {
        enabled: paymentsV2.ownedOrders.ready,
        reason: paymentsV2.ownedOrders.reason,
      },
      paymentsV2,
      profile: {
        status: String(profileData.status ?? "not_started"),
        bankVerificationStatus: String(
          pendingSettlement.accountFingerprint
            ? "pending_review"
            : (profileData.bankVerificationStatus ?? "not_started"),
        ),
        bankName: String(displayedSettlement.bankName ?? ""),
        resolvedAccountName: String(
          displayedSettlement.resolvedAccountName ?? "",
        ),
        maskedAccount: displayedSettlement.accountLast4
          ? `•••• ${String(displayedSettlement.accountLast4)}`
          : "",
      },
      totals,
      settlements: recentSettlements,
    };
  },
);
