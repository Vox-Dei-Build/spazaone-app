import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import twilio from "twilio";
import { db, functions } from "../config/main";
import {
  readStoreNotificationTokens,
  removeInvalidStoreNotificationTokens,
} from "../notifications/storeNotificationTokens";
import { formatPhoneNumber } from "../utils/phoneUtils";

type OrderNotice = {
  orderId: string;
  sellerId: string;
  customerId?: string;
  buyerName: string;
  buyerPhone: string;
  status: string;
  paymentMethod?: string;
  amountDueMinor: number;
  trackingCarrier?: string;
  trackingNumber?: string;
  notifyBuyer?: boolean;
};

function statusMessage(order: OrderNotice): string {
  const reference = order.orderId.slice(0, 8).toUpperCase();
  const amount = `R ${(order.amountDueMinor / 100).toFixed(2)}`;
  switch (order.status) {
    case "pending_payment":
      if (order.paymentMethod === "manual") {
        return (
          `Spaza One: Order request ${reference} (${amount}) was sent to the seller. ` +
          "They will contact you to arrange payment and confirm the order."
        );
      }
      return `Spaza One: Order ${reference} is awaiting payment.`;
    case "paid":
      return (
        `Spaza One: Payment received for order ${reference} (${amount}). ` +
        "We will update you when fulfilment starts."
      );
    case "submitted_for_fulfilment":
      return `Spaza One: Order ${reference} was submitted for fulfilment.`;
    case "shipped": {
      const tracking = [order.trackingCarrier, order.trackingNumber]
        .filter(Boolean)
        .join(" ");
      return (
        `Spaza One: Order ${reference} has shipped.` +
        (tracking ? ` Tracking: ${tracking}.` : "")
      );
    }
    case "delivered":
      return (
        `Spaza One: Order ${reference} has been marked delivered. ` +
        "Thank you for shopping with Spaza One."
      );
    case "cancelled":
      return `Spaza One: Order ${reference} was cancelled.`;
    case "refunded":
      return `Spaza One: The refund for order ${reference} was recorded.`;
    default:
      return `Spaza One: Order ${reference} is now ${order.status}.`;
  }
}

async function notifyBuyer(order: OrderNotice): Promise<string> {
  const to = formatPhoneNumber(order.buyerPhone);
  if (!to) return "skipped_no_phone";
  const config = functions.config().twilio ?? {};
  const accountSid = process.env.TWILIO_ACCOUNT_SID || config.sid;
  const authToken = process.env.TWILIO_AUTH_TOKEN || config.token;
  const whatsappFrom =
    process.env.TWILIO_WHATSAPP_NUMBER ||
    config.customer_whatsapp_number ||
    config.number;
  const smsFrom =
    process.env.TWILIO_SMS_NUMBER || config.sms_number || config.number;
  if (!accountSid || !authToken) return "skipped_not_configured";

  const client = twilio(accountSid, authToken);
  const body = statusMessage(order);
  if (whatsappFrom) {
    try {
      await client.messages.create({
        to: `whatsapp:${to}`,
        from: `whatsapp:${formatPhoneNumber(String(whatsappFrom))}`,
        body,
      });
      return "whatsapp_sent";
    } catch (error) {
      console.warn("[commerce] WhatsApp update failed; trying SMS", error);
    }
  }
  if (!smsFrom) return "failed";
  try {
    await client.messages.create({
      to,
      from: formatPhoneNumber(String(smsFrom)),
      body,
    });
    return "sms_sent";
  } catch (error) {
    console.error("[commerce] buyer notification failed", error);
    return "failed";
  }
}

async function notifySeller(order: OrderNotice): Promise<string> {
  const tokens = await readStoreNotificationTokens(order.sellerId);
  if (!tokens.length) return "skipped_no_tokens";
  const reference = order.orderId.slice(0, 8).toUpperCase();
  const result = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title:
        order.status === "pending_payment" && order.paymentMethod === "manual"
          ? "New dropship order request"
          : order.status === "paid"
            ? "Dropship payment confirmed"
            : "Order updated",
      body: `Order ${reference} is ${order.status.split("_").join(" ")}.`,
    },
    data: {
      type: "COMMERCE_ORDER_EVENT",
      orderId: order.orderId,
      merchantId: order.sellerId,
      route: "/customerAccount",
      notificationType: "commerce_order",
      action: "open_customer_orders",
      customerId: order.customerId ?? "",
      customerName: order.buyerName,
      customerNumber: order.buyerPhone,
      status: order.status,
    },
  });
  const invalid = result.responses
    .map((response, index) => ({ response, token: tokens[index] }))
    .filter(({ response }) =>
      String(response.error?.code ?? "").includes(
        "registration-token-not-registered",
      ),
    )
    .map(({ token }) => token);
  if (invalid.length) {
    await removeInvalidStoreNotificationTokens(order.sellerId, invalid);
  }
  return result.successCount > 0 ? "push_sent" : "failed";
}

export async function notifyCommerceOrder(order: OrderNotice): Promise<void> {
  const [buyerResult, sellerResult] = await Promise.all([
    order.notifyBuyer === false
      ? Promise.resolve("skipped_conversational_reply")
      : notifyBuyer(order).catch(() => "failed"),
    notifySeller(order).catch(() => "failed"),
  ]);
  await db.doc(`commerceOrders/${order.orderId}`).set(
    {
      notificationHistory: FieldValue.arrayUnion({
        status: order.status,
        buyerResult,
        sellerResult,
        attemptedAt: new Date().toISOString(),
      }),
      notificationUpdatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}
