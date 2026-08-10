import { functions, db } from "../config/main";
import { AndroidConfig } from "firebase-admin/messaging";
import * as admin from "firebase-admin";
import { requireBotRequest } from "../security/requestAuth";
import { normalizePhoneNumber } from "../utils/phoneUtils";
import {
  readStoreNotificationTokens,
  removeInvalidStoreNotificationTokens,
} from "../notifications/storeNotificationTokens";
import {
  appendTruthSurfaceMessage,
  incrementUnreadCount,
} from "../notifications/unreadCounts";

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
 *
 * Push throttling: an inbound message that arrives within
 * `INBOUND_PUSH_THROTTLE_MS` of the previous inbound from the same customer
 * still appends to the array and increments `unreadCount`, but suppresses
 * the FCM push. Bypasses (always push, regardless of throttle):
 *   - Bot handoff records (message text begins with "Bot handoff:").
 *   - Image and document inbounds (payment proofs).
 *   - The first inbound in a brand-new conversation.
 */

const INBOUND_PUSH_THROTTLE_MS = 60 * 60 * 1000; // 1 hour

const digitsOnly = (raw: unknown) => String(raw ?? "").replace(/\D/g, "");

/**
 * Customer-number match used by `markMessagesAsRead` and now reused here:
 * compare the trailing 9 digits of both numbers (or the shorter common
 * length) so leading dial codes / formatting don't cause false negatives.
 */
const matchesCustomer = (stored: unknown, next: unknown): boolean => {
  const a = digitsOnly(stored);
  const b = digitsOnly(next);
  if (!a || !b) return false;
  const len = Math.min(9, a.length, b.length);
  return a.slice(-len) === b.slice(-len);
};

const isInboundEntry = (entry: Record<string, unknown>): boolean => {
  const direction = (entry as { direction?: unknown }).direction;
  if (direction == null) return true; // legacy entries default to inbound
  return String(direction).toLowerCase() === "inbound";
};

const parseTimestampMs = (raw: unknown): number | null => {
  if (typeof raw !== "string" || !raw) return null;
  const parsed = Date.parse(raw);
  return Number.isFinite(parsed) ? parsed : null;
};

/**
 * Decide whether to suppress the FCM push for an inbound message. We
 * suppress when the most recent prior inbound from the same customer (in
 * `unreadMessages[]`) is within the throttle window.
 *
 * Bypasses below take precedence over the throttle: handoff records and
 * payment proofs always push.
 */
const shouldThrottlePush = (args: {
  unreadMessages: Array<Record<string, unknown>>;
  customerNumber: string;
  newTimestampMs: number;
}): boolean => {
  const { unreadMessages, customerNumber, newTimestampMs } = args;
  // Walk newest to oldest so the first match is the most recent prior inbound.
  for (let i = unreadMessages.length - 1; i >= 0; i--) {
    const entry = unreadMessages[i];
    if (!entry) continue;
    if (!isInboundEntry(entry)) continue;
    if (
      !matchesCustomer(
        (entry as { customerNumber?: unknown }).customerNumber,
        customerNumber,
      )
    ) {
      continue;
    }
    const priorMs = parseTimestampMs(
      (entry as { timestamp?: unknown }).timestamp,
    );
    if (priorMs == null) return false; // no usable prior timestamp → push
    return newTimestampMs - priorMs < INBOUND_PUSH_THROTTLE_MS;
  }
  return false; // no prior inbound from this customer → push
};

export const logUnreadMessage = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
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
      if (!merchantDoc.exists) {
        res.status(404).json({ error: "Merchant not found" });
        return;
      }
      let unreadMessages: Array<Record<string, unknown>> = [];

      if (merchantDoc.exists) {
        const data = merchantDoc.data();
        unreadMessages =
          (data?.unreadMessages as Array<Record<string, unknown>>) ?? [];
      }

      // Idempotency: if the caller supplies an externalId we never persist the
      // same message twice. Bot retries (network, function cold start, etc.)
      // become safe.
      if (
        externalId &&
        unreadMessages.some(
          (entry) =>
            (entry as { externalId?: string }).externalId === externalId,
        )
      ) {
        res.status(200).json({
          message: "Duplicate externalId — message already logged.",
          deduped: true,
        });
        return;
      }

      // Decide push throttling BEFORE we mutate the array, so the throttle
      // compares against the previous state, not against the message we are
      // about to add.
      const messageText = typeof message === "string" ? message : "";
      const isHandoff = /^bot\s+handoff[:\s]/i.test(messageText.trim());
      const kindBypassesThrottle =
        resolvedKind === "image" || resolvedKind === "document";
      const newTimestampMs = parseTimestampMs(resolvedTimestamp) ?? Date.now();

      const throttlePush =
        resolvedDirection === "inbound" &&
        !isHandoff &&
        !kindBypassesThrottle &&
        shouldThrottlePush({
          unreadMessages,
          customerNumber: String(customerNumber),
          newTimestampMs,
        });

      // Keep the released fields and add structured truth-surface metadata.
      // Inbound persistence is committed atomically with counters below.
      const messageEntry = {
        customerNumber,
        message,
        timestamp: resolvedTimestamp,
        direction: resolvedDirection,
        senderRole: resolvedSenderRole,
        channel: resolvedChannel,
        kind: resolvedKind,
        ...(externalId ? { externalId } : {}),
      };

      // FCM push only fires for inbound (legacy + new customer messages).
      if (resolvedDirection !== "inbound") {
        const append = await appendTruthSurfaceMessage({
          merchantId,
          messageEntry,
          externalId:
            typeof externalId === "string" && externalId
              ? externalId
              : undefined,
        });
        res.status(200).json({
          message: append.deduped
            ? "Duplicate externalId — message already logged."
            : "Outbound reply mirrored to truth surface.",
          direction: resolvedDirection,
          deduped: append.deduped,
        });
        return;
      }

      const notificationCustomer = await findCustomerForMessageNotification(
        merchantId,
        customerNumber,
      );
      const unread = await incrementUnreadCount({
        merchantId,
        customerId: notificationCustomer?.id,
        customerNumber,
        kind: "messages",
        eventKey: `message:${String(
          externalId ||
            `${resolvedTimestamp}:${customerNumber}:${resolvedKind}:${messageText}`,
        )}`,
        messageEntry,
      });
      if (unread.deduped) {
        res.status(200).json({
          message: "Duplicate externalId — message already logged.",
          deduped: true,
        });
        return;
      }
      const nextUnreadCount = unread.merchant.messages;

      if (throttlePush) {
        console.log(
          `[logUnreadMessage] suppressing FCM push for ${merchantId}/${customerNumber} ` +
            "(within throttle window)",
        );
        res.status(200).json({
          message:
            "Unread message logged; FCM push suppressed by throttle window.",
          pushed: false,
          throttled: true,
        });
        return;
      }

      const tokens = await readStoreNotificationTokens(merchantId);

      if (tokens.length === 0) {
        console.log("Merchant FCM tokens not found.");
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

      const payload = {
        notification: {
          title: "New Customer Message 📩",
          body: "Tap to open the customer's account.",
        },
        android: androidConfig,
        data: {
          ...buildCustomerMessageNotificationData(
            nextUnreadCount,
            notificationCustomer,
            customerNumber,
          ),
          unreadTotalCount: String(unread.merchant.total),
        },
        tokens,
      };

      try {
        const response = await admin.messaging().sendEachForMulticast(payload);
        console.log(
          `✅ Push notification sent successfully to ${response.successCount}/${tokens.length} token(s).`,
        );

        const invalidTokens: string[] = [];
        response.responses.forEach((result, index) => {
          if (result.success) return;
          const code = result.error?.code;
          if (
            code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token"
          ) {
            invalidTokens.push(payload.tokens[index]);
          }
        });

        if (invalidTokens.length > 0) {
          await removeInvalidStoreNotificationTokens(merchantId, invalidTokens);
          console.log(
            `[logUnreadMessage] removed ${invalidTokens.length} invalid FCM token(s) for ${merchantId}`,
          );
        }
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
