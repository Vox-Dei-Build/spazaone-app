import twilio from "twilio/lib/index";
import { db, functions } from "../config/main";
import { authenticateFirebaseRequest } from "../security/requestAuth";
import { formatPhoneNumber } from "../utils/phoneUtils";
import { normalizeTwilioError } from "../utils/twilioError";

type TwilioAction = "send" | "status" | "messages" | "media";
type TwilioChannel = "whatsapp" | "sms";

// Twilio uses SM SIDs for standard messages and can return MM SIDs for
// WhatsApp messages created through a Messaging Service / Content Template.
// Both identify a Message resource and are safe to pass to client.messages().
const isMessageSid = (value: string): boolean =>
  /^(?:SM|MM)[a-fA-F0-9]{32}$/.test(value);

const env = (...names: string[]): string => {
  for (const name of names) {
    const value = process.env[name]?.trim();
    if (value) return value;
  }
  return "";
};

const normalizeRecipient = (raw: unknown): string => {
  const withoutChannel = String(raw ?? "").replace(/^whatsapp:/i, "");
  return formatPhoneNumber(withoutChannel);
};

const responseStatus = (providerStatus: number | null): number =>
  providerStatus != null && providerStatus >= 400 && providerStatus <= 599
    ? providerStatus
    : 502;

const parseAction = (raw: unknown): TwilioAction | null => {
  const action = String(raw ?? "send");
  return action === "send" ||
    action === "status" ||
    action === "messages" ||
    action === "media"
    ? action
    : null;
};

const authorizedCustomerNumber = async (
  merchantId: string,
  customerId: unknown,
): Promise<string | null> => {
  const id = String(customerId ?? "").trim();
  if (!id) return null;

  const customer = await db
    .collection("users")
    .doc(merchantId)
    .collection("customers")
    .doc(id)
    .get();
  if (!customer.exists) return null;
  return normalizeRecipient(customer.data()?.number);
};

/**
 * Authenticated Twilio proxy for the merchant app.
 *
 * The previous mobile implementation downloaded the master Twilio Auth Token
 * from Remote Config and called Twilio directly. Besides exposing a privileged
 * credential to every installed APK, that made every released app stop sending
 * the instant Twilio rotated the leaked token. This function keeps the token on
 * the server and supports both message dispatch and delivery-status polling.
 */
export const sendTwilioMessage = functions
  .runWith({ secrets: ["TWILIO_AUTH_TOKEN"] })
  .https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set(
      "Access-Control-Allow-Headers",
      "Authorization, Content-Type, X-Firebase-AppCheck",
    );
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({ success: false, error: "Method not allowed." });
      return;
    }

    const merchantId = await authenticateFirebaseRequest(req, res, {
      requireAppCheck: true,
    });
    if (!merchantId) return;

    const accountSid = env("TWILIO_ACCOUNT_SID", "TWILIO_SID");
    const authToken = env("TWILIO_AUTH_TOKEN", "TWILIO_TOKEN");
    if (!accountSid || !authToken) {
      console.error(
        "[sendTwilioMessage] Twilio credentials are not configured",
      );
      res.status(503).json({
        success: false,
        error: "Messaging is temporarily unavailable.",
      });
      return;
    }

    const action = parseAction(req.body?.action);
    if (!action) {
      res.status(400).json({ success: false, error: "Invalid action." });
      return;
    }
    const client = twilio(accountSid, authToken);

    if (action === "status") {
      const messageSid = String(req.body?.messageSid ?? "").trim();
      if (!isMessageSid(messageSid)) {
        res.status(400).json({ success: false, error: "Invalid message SID." });
        return;
      }

      try {
        const message = await client.messages(messageSid).fetch();
        res.status(200).json({ success: true, status: message.status });
      } catch (error) {
        const normalized = normalizeTwilioError(error, "whatsapp");
        console.error(
          `[sendTwilioMessage] status lookup failed for merchant ${merchantId}:`,
          normalized.providerCode ?? normalized.providerMessage,
        );
        res.status(responseStatus(normalized.providerStatus)).json({
          success: false,
          error: normalized.pasellaMessage,
          providerCode: normalized.providerCode,
        });
      }
      return;
    }

    if (action === "messages") {
      const customerNumber = await authorizedCustomerNumber(
        merchantId,
        req.body?.customerId,
      );
      if (!customerNumber) {
        res.status(403).json({
          success: false,
          error: "Customer access could not be verified.",
        });
        return;
      }

      const channel: TwilioChannel =
        req.body?.channel === "sms" ? "sms" : "whatsapp";
      const direction = req.body?.direction === "from" ? "from" : "to";
      const queryNumber =
        channel === "whatsapp" ? `whatsapp:${customerNumber}` : customerNumber;

      try {
        const messages = await client.messages.list({
          ...(direction === "from"
            ? { from: queryNumber }
            : { to: queryNumber }),
          limit: 100,
        });
        res.status(200).json({
          success: true,
          messages: messages.map((message) => ({
            sid: message.sid,
            body: message.body,
            dateSent: message.dateSent?.toISOString() ?? null,
            status: message.status,
            from: message.from,
            to: message.to,
            uri: message.uri,
            numMedia: message.numMedia,
          })),
        });
      } catch (error) {
        const normalized = normalizeTwilioError(error, channel);
        console.error(
          `[sendTwilioMessage] history lookup failed for merchant ${merchantId}:`,
          normalized.providerCode ?? normalized.providerMessage,
        );
        res.status(responseStatus(normalized.providerStatus)).json({
          success: false,
          error: normalized.pasellaMessage,
          providerCode: normalized.providerCode,
        });
      }
      return;
    }

    if (action === "media") {
      const messageSid = String(req.body?.messageSid ?? "").trim();
      const customerNumber = await authorizedCustomerNumber(
        merchantId,
        req.body?.customerId,
      );
      if (!isMessageSid(messageSid) || !customerNumber) {
        res.status(403).json({
          success: false,
          error: "Media access could not be verified.",
        });
        return;
      }

      try {
        const message = await client.messages(messageSid).fetch();
        const belongsToCustomer = [message.from, message.to].some(
          (number) => normalizeRecipient(number) === customerNumber,
        );
        if (!belongsToCustomer) {
          res.status(403).json({
            success: false,
            error: "Media access could not be verified.",
          });
          return;
        }

        const media = await client.messages(messageSid).media.list({
          limit: 20,
        });
        res.status(200).json({
          success: true,
          urls: media.map(
            (item) =>
              `https://api.twilio.com${item.uri.replace(/\.json$/, "")}`,
          ),
        });
      } catch (error) {
        const normalized = normalizeTwilioError(error, "whatsapp");
        console.error(
          `[sendTwilioMessage] media lookup failed for merchant ${merchantId}:`,
          normalized.providerCode ?? normalized.providerMessage,
        );
        res.status(responseStatus(normalized.providerStatus)).json({
          success: false,
          error: normalized.pasellaMessage,
          providerCode: normalized.providerCode,
        });
      }
      return;
    }

    const channel: TwilioChannel =
      req.body?.channel === "sms" ? "sms" : "whatsapp";
    const recipient = normalizeRecipient(req.body?.to);
    if (!recipient) {
      res
        .status(400)
        .json({ success: false, error: "Invalid SA mobile number." });
      return;
    }

    const merchantMessagingServiceSid = env(
      "TWILIO_MERCHANT_MESSAGING_SERVICE_SID",
    );
    const customerMessagingServiceSid = env(
      "TWILIO_CUSTOMER_MESSAGING_SERVICE_SID",
    );
    const messagingServiceSid =
      req.body?.botType === "Merchant"
        ? merchantMessagingServiceSid
        : customerMessagingServiceSid;

    try {
      if (channel === "sms") {
        const body = String(req.body?.body ?? "").trim();
        const from = env("TWILIO_NUMBER");
        if (!body || !from) {
          res.status(400).json({
            success: false,
            error: "SMS body or sender is missing.",
          });
          return;
        }

        const message = await client.messages.create({
          to: recipient,
          from,
          body,
        });
        res.status(201).json({ success: true, sid: message.sid });
        return;
      }

      const templateId = String(req.body?.templateId ?? "").trim();
      if (!templateId || !messagingServiceSid) {
        res.status(400).json({
          success: false,
          error: "WhatsApp template or messaging service is missing.",
        });
        return;
      }

      const templateParams = req.body?.templateParams;
      const message = await client.messages.create({
        to: `whatsapp:${recipient}`,
        messagingServiceSid,
        contentSid: templateId,
        ...(templateParams != null
          ? { contentVariables: JSON.stringify(templateParams) }
          : {}),
      });

      res.status(201).json({ success: true, sid: message.sid });
    } catch (error) {
      const normalized = normalizeTwilioError(error, channel);
      console.error(
        `[sendTwilioMessage] ${channel} send failed for merchant ${merchantId}:`,
        normalized.providerCode ?? normalized.providerMessage,
      );
      res.status(responseStatus(normalized.providerStatus)).json({
        success: false,
        error: normalized.pasellaMessage,
        providerCode: normalized.providerCode,
      });
    }
  });
