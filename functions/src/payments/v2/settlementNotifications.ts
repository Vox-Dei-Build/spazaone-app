import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { MulticastMessage } from "firebase-admin/messaging";
import { db } from "../../config/main";
import {
  readStoreNotificationTokens,
  removeInvalidStoreNotificationTokens,
} from "../../notifications/storeNotificationTokens";

export type SettlementReviewNotificationOutcome =
  | "approve"
  | "changes_required"
  | "reject";

export function settlementReviewNotificationCopy(
  outcome: SettlementReviewNotificationOutcome,
): { title: string; body: string } {
  switch (outcome) {
    case "approve":
      return {
        title: "Online payments verified",
        body: "Your payout bank account is verified. Open SpazaOne to continue.",
      };
    case "changes_required":
      return {
        title: "Bank details need attention",
        body: "Update your payout bank details in SpazaOne and submit them again.",
      };
    case "reject":
      return {
        title: "Bank verification not approved",
        body: "Open SpazaOne to review your payout bank details and next steps.",
      };
  }
}

/**
 * Best-effort FCM delivery for a durable in-app review notification. A failed
 * push never rolls back the bank-review decision; its delivery state remains
 * visible for support and the notification stays available in Firestore.
 */
export async function deliverSettlementReviewNotification(input: {
  merchantId: string;
  notificationId: string;
  outcome: SettlementReviewNotificationOutcome;
}): Promise<void> {
  const notificationRef = db.doc(
    `users/${input.merchantId}/notifications/${input.notificationId}`,
  );
  const tokens = await readStoreNotificationTokens(input.merchantId);
  if (tokens.length === 0) {
    await notificationRef.set(
      {
        pushDeliveryState: "no_registered_device",
        pushDeliveryUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return;
  }

  const copy = settlementReviewNotificationCopy(input.outcome);
  const message: MulticastMessage = {
    tokens,
    notification: copy,
    android: {
      priority: "high",
      notification: { channelId: "default_channel", sound: "default" },
    },
    data: {
      type: "PAYMENT_VERIFICATION",
      outcome: input.outcome,
      route: "/walletPage?destination=online_payments",
      idempotencyKey: input.notificationId,
      source: "settlementReview",
    },
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    const invalidTokens = response.responses
      .map((result, index) => ({ result, token: tokens[index] }))
      .filter(({ result }) =>
        String(result.error?.code ?? "").includes(
          "registration-token-not-registered",
        ),
      )
      .map(({ token }) => token);
    if (invalidTokens.length > 0) {
      await removeInvalidStoreNotificationTokens(
        input.merchantId,
        invalidTokens,
      );
    }
    await notificationRef.set(
      {
        pushDeliveryState:
          response.successCount > 0 ? "delivered" : "not_delivered",
        pushSuccessCount: response.successCount,
        pushFailureCount: response.failureCount,
        pushDeliveryUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (error) {
    console.error("[payments-v2] settlement review push failed", {
      notificationId: input.notificationId,
      code: error instanceof Error ? error.name : "unknown",
    });
    await notificationRef.set(
      {
        pushDeliveryState: "not_delivered",
        pushDeliveryUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}
