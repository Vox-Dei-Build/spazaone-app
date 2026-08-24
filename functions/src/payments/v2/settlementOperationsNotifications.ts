import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { MulticastMessage } from "firebase-admin/messaging";
import { db, functions } from "../../config/main";
import { stableDocumentId } from "./domain";

export const PAYMENT_OPERATIONS_NOTIFICATION_TYPE =
  "SETTLEMENT_VERIFICATION_REQUEST";
export const PAYMENT_INTENT_STALE_NOTIFICATION_TYPE =
  "PAYMENT_INTENT_CONFIRMATION_OVERDUE";
export const PAYMENT_OPERATIONS_WORKSPACE_URL =
  "https://workspace.spazaone.com/";

const MAX_RECIPIENT_IDENTITIES = 20;
const MAX_RECIPIENT_STORES = 50;
const MAX_PUSH_TOKENS = 100;

type UnknownRecord = Record<string, unknown>;

function asRecord(value: unknown): UnknownRecord {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? (value as UnknownRecord)
    : {};
}

function addTokens(target: Set<string>, value: unknown): void {
  const data = asRecord(value);
  const scalar = data.fcmToken;
  if (typeof scalar === "string" && scalar.trim()) target.add(scalar.trim());
  if (Array.isArray(data.fcmTokens)) {
    for (const token of data.fcmTokens) {
      if (typeof token === "string" && token.trim()) target.add(token.trim());
    }
  }
}

export function paymentOperationsRecipientEmails(value: unknown): string[] {
  return [
    ...new Set(
      String(value ?? "")
        .split(",")
        .map((entry) => entry.trim().toLowerCase())
        .filter((entry) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(entry)),
    ),
  ].slice(0, MAX_RECIPIENT_IDENTITIES);
}

export function settlementOperationsNotificationCopy(): {
  title: string;
  body: string;
} {
  return {
    title: "Bank verification request",
    body: "A merchant requested bank verification. Open the SpazaOne Payment Operations workspace to review it.",
  };
}

export function paymentIntentStaleNotificationCopy(): {
  title: string;
  body: string;
} {
  return {
    title: "Payment confirmation overdue",
    body: "A payment has not confirmed in time. Open the SpazaOne Payment Operations workspace to review it.",
  };
}

export function settlementOperationsNotificationId(input: {
  requestId: string;
  bankingDetailsId: string;
  bankingDetailsUpdatedAtMs: number;
  sequence: number;
}): string {
  return stableDocumentId("settlement_request_alert", [
    input.requestId,
    input.bankingDetailsId,
    String(input.bankingDetailsUpdatedAtMs),
    String(input.sequence),
  ]);
}

async function readOperationsIdentityTokens(uid: string): Promise<string[]> {
  const tokens = new Set<string>();
  const [legacyUser, devices, storeMemberships] = await Promise.all([
    db.doc(`users/${uid}`).get(),
    db.collection(`users/${uid}/devices`).where("active", "==", true).get(),
    db
      .collection(`operators/${uid}/stores`)
      .where("status", "==", "active")
      .get(),
  ]);
  if (legacyUser.exists) addTokens(tokens, legacyUser.data());
  devices.docs.forEach((device) => addTokens(tokens, device.data()));
  storeMemberships.docs.forEach((membership) =>
    addTokens(tokens, membership.data()),
  );

  const storeIds = [
    ...new Set(
      storeMemberships.docs
        .map((membership) =>
          String(membership.data().storeId ?? membership.id).trim(),
        )
        .filter((storeId) => /^[A-Za-z0-9_-]{1,200}$/.test(storeId)),
    ),
  ].slice(0, MAX_RECIPIENT_STORES);
  const canonicalMemberships = await Promise.all(
    storeIds.map((storeId) =>
      db.doc(`stores/${storeId}/operators/${uid}`).get(),
    ),
  );
  canonicalMemberships.forEach((membership) => {
    if (membership.exists && membership.data()?.status === "active") {
      addTokens(tokens, membership.data());
    }
  });
  return [...tokens].slice(0, MAX_PUSH_TOKENS);
}

async function readPaymentOperationsTokens(): Promise<string[]> {
  const emails = paymentOperationsRecipientEmails(
    process.env.PAYMENT_ADMIN_ALLOWED_EMAILS,
  );
  const tokens = new Set<string>();
  for (const email of emails) {
    try {
      const user = await admin.auth().getUserByEmail(email);
      const identityTokens = await readOperationsIdentityTokens(user.uid);
      identityTokens.forEach((token) => tokens.add(token));
    } catch (_) {
      // A removed or not-yet-registered administrator is simply not a push
      // destination. The durable workspace queue remains authoritative.
    }
  }
  return [...tokens].slice(0, MAX_PUSH_TOKENS);
}

export async function deliverPaymentOperationsNotification(
  notificationId: string,
): Promise<void> {
  const notificationRef = db.doc(
    `paymentOperationsNotifications/${notificationId}`,
  );
  const notification = await notificationRef.get();
  const data = notification.data() ?? {};
  const type = String(data.type ?? "");
  if (
    !notification.exists ||
    ![
      PAYMENT_OPERATIONS_NOTIFICATION_TYPE,
      PAYMENT_INTENT_STALE_NOTIFICATION_TYPE,
    ].includes(type)
  ) {
    return;
  }

  const tokens = await readPaymentOperationsTokens();
  if (tokens.length === 0) {
    await notificationRef.set(
      {
        pushDeliveryState: "no_registered_device",
        pushSuccessCount: 0,
        pushFailureCount: 0,
        pushDeliveryUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return;
  }

  const isStalePayment = type === PAYMENT_INTENT_STALE_NOTIFICATION_TYPE;
  const copy = isStalePayment
    ? paymentIntentStaleNotificationCopy()
    : settlementOperationsNotificationCopy();
  const message: MulticastMessage = {
    tokens,
    notification: copy,
    android: {
      priority: "high",
      notification: {
        channelId: "default_channel",
        sound: "default",
        clickAction: "FLUTTER_NOTIFICATION_CLICK",
      },
    },
    webpush: { fcmOptions: { link: PAYMENT_OPERATIONS_WORKSPACE_URL } },
    data: {
      type: "PAYMENT_ADMINISTRATION",
      notificationType: "payment_operations",
      route: PAYMENT_OPERATIONS_WORKSPACE_URL,
      idempotencyKey: notificationId,
      source: isStalePayment
        ? "paymentIntentMonitoring"
        : "settlementAuthorizationRequest",
    },
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
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
    console.error("[payments-v2] operations notification delivery failed", {
      code: error instanceof Error ? error.name : "unknown",
    });
    await notificationRef.set(
      {
        pushDeliveryState: "not_delivered",
        pushSuccessCount: 0,
        pushFailureCount: tokens.length,
        pushDeliveryUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
}

export const deliverSettlementOperationsNotification =
  deliverPaymentOperationsNotification;

export const onPaymentOperationsNotificationCreated = functions.firestore
  .document("paymentOperationsNotifications/{notificationId}")
  .onCreate(async (_snapshot, context) => {
    await deliverPaymentOperationsNotification(
      String(context.params.notificationId),
    );
  });
