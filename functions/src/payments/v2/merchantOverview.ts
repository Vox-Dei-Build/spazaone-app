import { db, functions } from "../../config/main";
import { paystackProviderMode } from "../../config/environment";
import { authorizeCallableMerchantOrBot } from "../../security/requestAuth";
import { requireStoreId } from "../../stores/storeAccess";
import { buyerSafePaymentsV2 } from "./buyerReadiness";
import {
  maskBankAccount,
  settlementAdminRequestRef,
} from "./settlementAdminRequests";
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

export type MerchantVerificationStage =
  | "not_started"
  | "missing_information"
  | "ready_to_submit"
  | "submitted"
  | "ready_to_verify"
  | "submitting"
  | "pending_review"
  | "approved"
  | "changes_required"
  | "rejected"
  | "blocked";

export function merchantVerificationJourney(input: {
  profile: Record<string, unknown>;
  request: Record<string, unknown>;
  hasSavedBankingDetails: boolean;
  destinationMatchesRequest?: boolean;
  nowMs: number;
}): { stage: MerchantVerificationStage; reason: string } {
  const profile = input.profile;
  const requestStatus = String(input.request.status ?? "");
  const authorization = (profile.settlementVerificationAuthorization ??
    {}) as Record<string, unknown>;
  const validationState = String(profile.validationAttemptState ?? "");
  const reviewState = String(profile.bankReviewState ?? "");

  if (!input.hasSavedBankingDetails) {
    return { stage: "missing_information", reason: "bank_details_required" };
  }
  if (requestStatus && input.destinationMatchesRequest === false) {
    return { stage: "ready_to_submit", reason: "bank_details_changed" };
  }

  if (requestStatus === "changes_required") {
    return { stage: "changes_required", reason: "review_changes_required" };
  }
  if (requestStatus === "rejected") {
    return { stage: "rejected", reason: "review_rejected" };
  }
  if (requestStatus === "revoked") {
    return { stage: "blocked", reason: "authorization_revoked" };
  }
  if (
    validationState === "provider_outcome_unknown" ||
    reviewState === "provider_outcome_unknown" ||
    reviewState.startsWith("blocked_") ||
    reviewState === "invalid_pending_destination"
  ) {
    return { stage: "blocked", reason: "support_review_required" };
  }
  if (
    validationState === "processing" &&
    Number(profile.validationAttemptLeaseUntilMs ?? 0) > input.nowMs
  ) {
    return { stage: "submitting", reason: "bank_check_processing" };
  }
  if (
    requestStatus === "pending_review" ||
    profile.status === "pending_review"
  ) {
    return { stage: "pending_review", reason: "final_review_pending" };
  }
  if (requestStatus === "authorization_required") {
    return { stage: "submitted", reason: "authorization_review_pending" };
  }
  if (requestStatus === "authorized") {
    const activeAuthorization =
      authorization.state === "authorized" &&
      Number(authorization.expiresAtMs ?? 0) >= input.nowMs &&
      Number(authorization.remainingAttempts ?? 0) > 0;
    return activeAuthorization
      ? { stage: "ready_to_verify", reason: "authorization_ready" }
      : { stage: "blocked", reason: "authorization_expired" };
  }
  if (
    requestStatus === "approved" ||
    profile.bankVerificationStatus === "approved"
  ) {
    return { stage: "approved", reason: "ready" };
  }
  if (input.hasSavedBankingDetails) {
    return { stage: "ready_to_submit", reason: "ready_to_request" };
  }
  return { stage: "not_started", reason: "not_started" };
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
    const [profile, request, bankingDetails, settlements, paymentsV2] =
      await Promise.all([
        db.doc(`merchantPaymentProfiles/${merchantId}`).get(),
        settlementAdminRequestRef(merchantId).get(),
        db.collection(`users/${merchantId}/bankingDetails`).limit(1).get(),
        db
          .collection("settlements")
          .where("merchantId", "==", merchantId)
          .limit(50)
          .get(),
        buyerSafePaymentsV2(merchantId),
      ]);
    const profileData = profile.data() ?? {};
    const requestData = request.data() ?? {};
    const bankingDetailsDocument = bankingDetails.docs[0];
    const bankingDetailsData = bankingDetailsDocument?.data() ?? {};
    const bankingDetailsUpdatedAtMs =
      bankingDetailsDocument?.updateTime?.toMillis() ?? 0;
    const destinationMatchesRequest =
      !request.exists ||
      (requestData.bankingDetailsId === bankingDetailsDocument?.id &&
        requestData.bankingDetailsUpdatedAtMs === bankingDetailsUpdatedAtMs);
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
    const verificationJourney = merchantVerificationJourney({
      profile: profileData,
      request: requestData,
      hasSavedBankingDetails: !bankingDetails.empty,
      destinationMatchesRequest,
      nowMs: Date.now(),
    });
    return {
      merchantId,
      // Backward-compatible 4.8.0 alias. New clients must use paymentsV2.
      readiness: {
        enabled: paymentsV2.ownedOrders.ready,
        reason: paymentsV2.ownedOrders.reason,
      },
      paymentsV2,
      verification: {
        ...verificationJourney,
        requestStatus: String(requestData.status ?? ""),
        hasSavedBankingDetails: !bankingDetails.empty,
        requestedAtMs: timestampMillis(requestData.requestedAt),
        updatedAtMs: timestampMillis(requestData.updatedAt),
        bankName: String(
          destinationMatchesRequest
            ? (requestData.bankName ?? "")
            : (bankingDetailsData.bankName ?? ""),
        ),
        maskedAccount: destinationMatchesRequest
          ? String(requestData.maskedAccount ?? "")
          : maskBankAccount(bankingDetailsData.accountNumber),
      },
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
