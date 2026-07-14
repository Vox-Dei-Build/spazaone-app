import { db, functions } from "../config/main";
import { formatPhoneNumber } from "./phoneUtils";
import twilio from "twilio";

const MERCHANT_ORDER_ALERT_TEMPLATE_SID = "HXe43579cfe5933d7312723bc85b3401d1";

export interface MerchantOrderSmsFallbackInput {
  merchantId: string;
  orderId: string;
  eventType: "ORDER_PLACED" | "ONLINE_PAYMENT_CONFIRMED";
  customerName?: string | null;
  orderTotal?: number | null;
  currency?: string;
  source: string;
  reason: "no_tokens" | "push_zero_success" | "push_error";
}

/**
 * Sends a best-effort transactional fallback when an order push cannot be
 * trusted. WhatsApp template is attempted first; SMS is used only if WhatsApp
 * fails. The send is idempotent per merchant/order/event so duplicate
 * notification paths cannot create duplicate external alerts.
 *
 * @param {MerchantOrderSmsFallbackInput} input Fallback context.
 * @returns {Promise<boolean>} True when an SMS was sent.
 */
export async function sendMerchantOrderSmsFallback(
  input: MerchantOrderSmsFallbackInput,
): Promise<boolean> {
  const fallbackId = `${input.eventType}_${input.orderId}`;
  const fallbackRef = db
    .collection("users")
    .doc(input.merchantId)
    .collection("orderAlertSmsFallbacks")
    .doc(fallbackId);

  const reserved = await db.runTransaction(async (tx) => {
    const existing = await tx.get(fallbackRef);
    if (existing.exists) return false;
    tx.create(fallbackRef, {
      eventType: input.eventType,
      orderId: input.orderId,
      source: input.source,
      reason: input.reason,
      status: "reserved",
      createdAt: new Date().toISOString(),
    });
    return true;
  });

  if (!reserved) {
    console.log(
      `[merchantOrderSmsFallback] already reserved ${fallbackId} for ${input.merchantId}`,
    );
    return false;
  }

  try {
    const merchantSnap = await db
      .collection("users")
      .doc(input.merchantId)
      .get();
    const merchantNumber = formatPhoneNumber(
      (merchantSnap.get("mobileNumber") as string | undefined) || "",
    );

    if (!merchantNumber) {
      await fallbackRef.set(
        {
          status: "skipped_no_valid_mobile",
          completedAt: new Date().toISOString(),
        },
        { merge: true },
      );
      return false;
    }

    const twilioConfig = functions.config().twilio;
    const client = twilio(twilioConfig.sid, twilioConfig.token);
    const orderTotal = formatOrderTotal(input);
    const contentVariables = JSON.stringify({
      customer_name: input.customerName || "a customer",
      order_total: orderTotal,
    });

    const messagingServiceSid = twilioConfig.customer_messaging_service_sid;
    if (!messagingServiceSid) {
      throw new Error(
        "Twilio customer messaging service SID is not configured.",
      );
    }

    try {
      const whatsappMessage = await client.messages.create({
        to: `whatsapp:${merchantNumber}`,
        messagingServiceSid,
        contentSid: MERCHANT_ORDER_ALERT_TEMPLATE_SID,
        contentVariables,
      });

      await fallbackRef.set(
        {
          status: "sent",
          channel: "whatsapp",
          to: merchantNumber,
          twilioSid: whatsappMessage.sid,
          completedAt: new Date().toISOString(),
        },
        { merge: true },
      );
      return true;
    } catch (whatsappError: unknown) {
      const err = whatsappError as { message?: string };
      await fallbackRef.set(
        {
          whatsappStatus: "failed",
          whatsappError: err?.message || String(whatsappError),
        },
        { merge: true },
      );
    }

    const senderNumber = twilioConfig.number;
    if (!senderNumber) {
      throw new Error("Twilio SMS sender number is not configured.");
    }

    const body = buildMerchantOrderSmsBody(input);
    const smsMessage = await client.messages.create({
      to: merchantNumber,
      from: senderNumber,
      body,
    });

    await fallbackRef.set(
      {
        status: "sent",
        channel: "sms",
        to: merchantNumber,
        twilioSid: smsMessage.sid,
        completedAt: new Date().toISOString(),
      },
      { merge: true },
    );
    return true;
  } catch (error: unknown) {
    const err = error as { message?: string };
    await fallbackRef.set(
      {
        status: "failed",
        error: err?.message || String(error),
        completedAt: new Date().toISOString(),
      },
      { merge: true },
    );
    console.error(
      `[merchantOrderSmsFallback] failed for ${input.merchantId}/${fallbackId}:`,
      err?.message || error,
    );
    return false;
  }
}

/**
 * Builds a concise one-segment SMS transactional alert.
 *
 * @param {MerchantOrderSmsFallbackInput} input Fallback context.
 * @returns {string} SMS body.
 */
function buildMerchantOrderSmsBody(
  input: MerchantOrderSmsFallbackInput,
): string {
  const event =
    input.eventType === "ONLINE_PAYMENT_CONFIRMED"
      ? "Online order paid"
      : "New WhatsApp order";
  const parts = [
    `SpazaOne: ${event}`,
    input.customerName ? `from ${input.customerName}` : null,
    typeof input.orderTotal === "number"
      ? `for ${(input.currency || "ZAR").toUpperCase()} ${input.orderTotal.toFixed(2)}`
      : null,
  ].filter(Boolean);

  return `${parts.join(" ")}. Open SpazaOne to respond.`;
}

/**
 * Formats the order amount for WhatsApp template variables.
 *
 * @param {MerchantOrderSmsFallbackInput} input Fallback context.
 * @returns {string} Human-readable order amount or "not shown".
 */
function formatOrderTotal(input: MerchantOrderSmsFallbackInput): string {
  if (typeof input.orderTotal !== "number") return "not shown";
  return `${(input.currency || "ZAR").toUpperCase()} ${input.orderTotal.toFixed(2)}`;
}
