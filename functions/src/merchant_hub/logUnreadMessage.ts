import { functions, db } from "../config/main";
import { AndroidConfig } from "firebase-admin/messaging";
import * as admin from "firebase-admin";
import { normalizePhoneNumber } from "../utils/phoneUtils";

type NotificationCustomer = {
  id: string;
  name: string;
  number: string;
};

async function findCustomerForMessageNotification(
  merchantId: string,
  customerNumber: string,
): Promise<NotificationCustomer | null> {
  const normalizedNumber = normalizePhoneNumber(customerNumber);
  if (!normalizedNumber) return null;

  const snapshot = await db
    .collection("users")
    .doc(merchantId)
    .collection("customers")
    .where("number", "==", normalizedNumber)
    .limit(1)
    .get();

  if (snapshot.empty) return null;

  const doc = snapshot.docs[0];
  const data = doc.data();
  const rawName = data?.name;
  const rawNumber = data?.number;
  const name =
    typeof rawName === "string" && rawName.trim() !== ""
      ? rawName.trim()
      : "Customer";
  const number =
    typeof rawNumber === "string" && rawNumber.trim() !== ""
      ? rawNumber.trim()
      : normalizedNumber;

  return { id: doc.id, name, number };
}

function buildCustomerMessageNotificationData(
  unreadCount: number,
  customer: NotificationCustomer | null,
  customerNumber: string,
): Record<string, string> {
  const data: Record<string, string> = {
    unreadCount: unreadCount.toString(),
    notificationType: "customer_message",
    action: "open_customer_messages",
    route: "/customerAccount?tab=messages",
  };

  if (customer) {
    data.customerId = customer.id;
    data.customerName = customer.name;
    data.customerNumber = customer.number;
    data.route =
      `/customerAccount?customerId=${encodeURIComponent(customer.id)}` +
      "&tab=messages";
    return data;
  }

  const normalizedNumber = normalizePhoneNumber(customerNumber);
  if (normalizedNumber) {
    data.customerNumber = normalizedNumber;
  }

  return data;
}

/**
 * Cloud Function: Append a message entry to the merchant truth surface and
 * (for inbound only) trigger the unread-count badge + FCM push.
 *
 * V1 truth-surface (`fix/pas-wa-v1-bot-message-truth`):
 *
 *   - Legacy callers (Twilio receive hooks, older Botpress paths) post
 *     `{ merchantId, customerNumber, message }` and are treated as inbound.
 *   - New callers (Botpress bot mirror) additionally pass `direction`,
 *     `senderRole`, `channel`, `kind`, `externalId`, `timestamp` so the
 *     merchant Connect tab can render bot replies (balance, statement, menu,
 *     clarifications, payment links, …) faithfully.
 *
 * Persistence model: appended to `users/{merchantId}.unreadMessages[]` (same
 * array the existing app already streams). Each entry now carries the
 * extended fields. The unread badge counter (`unreadCount`) and the FCM push
 * are gated on `direction === 'inbound'` so the bot's own outbound mirrors
 * do not ring the merchant's bell.
 *
 * Idempotency: when `externalId` is provided we skip persistence if any
 * existing entry in the array already has the same `externalId`. This makes
 * the bot's "send then mirror" flow safe to retry.
 */
export const logUnreadMessage = functions.https.onRequest(async (req, res) => {
  try {
    const {
      merchantId,
      customerNumber,
      message,
      direction,
      senderRole,
      channel,
      kind,
      externalId,
      timestamp,
    } = req.body ?? {};

    if (!merchantId || !customerNumber || !message) {
      res.status(400).json({ error: "Missing required fields" });
      return;
    }

    // Default direction to 'inbound' so legacy callers (Twilio receive hooks)
    // keep their existing behaviour: badge + FCM ring on the merchant.
    const resolvedDirection: "inbound" | "outbound" =
      direction === "outbound" ? "outbound" : "inbound";
    const resolvedSenderRole: string =
      senderRole ?? (resolvedDirection === "outbound" ? "bot" : "customer");
    const resolvedChannel: string = channel ?? "whatsapp";
    const resolvedKind: string = kind ?? "text";
    const resolvedTimestamp: string =
      typeof timestamp === "string" && timestamp
        ? timestamp
        : new Date().toISOString();

    const merchantRef = db.collection("users").doc(merchantId);
    const merchantDoc = await merchantRef.get();
    let unreadCount = 0;
    let unreadMessages: Array<Record<string, unknown>> = [];

    if (merchantDoc.exists) {
      const data = merchantDoc.data();
      unreadMessages =
        (data?.unreadMessages as Array<Record<string, unknown>>) ?? [];
      unreadCount = (data?.unreadCount as number) ?? 0;
    }

    // Idempotency: if the caller supplies an externalId we never persist the
    // same message twice. Bot retries (network, function cold start, etc.)
    // become safe.
    if (
      externalId &&
      unreadMessages.some(
        (entry) => (entry as { externalId?: string }).externalId === externalId,
      )
    ) {
      res.status(200).json({
        message: "Duplicate externalId — message already logged.",
        deduped: true,
      });
      return;
    }

    // Append the new entry. We keep `customerNumber`, `message`, `timestamp`
    // for backwards compatibility with the existing app stream and add the
    // structured fields for the Connect tab's truth-surface renderer.
    unreadMessages.push({
      customerNumber,
      message,
      timestamp: resolvedTimestamp,
      direction: resolvedDirection,
      senderRole: resolvedSenderRole,
      channel: resolvedChannel,
      kind: resolvedKind,
      ...(externalId ? { externalId } : {}),
    });

    // Outbound bot replies should NOT ring the merchant's bell — the merchant
    // already saw their bot reply in the conversation, this is just truth
    // capture. Only inbound entries advance the unread counter.
    const nextUnreadCount =
      resolvedDirection === "inbound" ? unreadCount + 1 : unreadCount;

    await merchantRef.set(
      {
        unreadMessages,
        unreadCount: nextUnreadCount,
      },
      { merge: true },
    );

    // FCM push only fires for inbound (legacy + new customer messages).
    if (resolvedDirection !== "inbound") {
      res.status(200).json({
        message: "Outbound reply mirrored to truth surface.",
        direction: resolvedDirection,
      });
      return;
    }

    const merchantData = await merchantRef.get();
    const merchantFCMToken = merchantData.data()?.fcmToken;

    if (!merchantFCMToken) {
      console.log("Merchant FCM Token not found.");
      res
        .status(200)
        .json({ message: "Unread message logged, but no FCM token." });
      return;
    }

    const androidConfig: AndroidConfig = {
      priority: "high",
      notification: {
        channelId: "default_channel",
        sound: "default",
      },
    };

    const notificationCustomer = await findCustomerForMessageNotification(
      merchantId,
      customerNumber,
    );

    const payload = {
      notification: {
        title: "New Customer Message 📩",
        body: "Tap to open the customer's account.",
      },
      android: androidConfig,
      data: buildCustomerMessageNotificationData(
        nextUnreadCount,
        notificationCustomer,
        customerNumber,
      ),
      token: merchantFCMToken,
    };

    try {
      const response = await admin.messaging().send(payload);
      console.log("✅ Push notification sent successfully:", response);
    } catch (error) {
      console.error("❌ Error sending push notification:", error);
    }

    res
      .status(200)
      .json({ message: "Unread message logged & notification sent." });
  } catch (error) {
    console.error("Error logging unread message:", error);
    res.status(500).json({ error: "Internal Server Error" });
  }
});
