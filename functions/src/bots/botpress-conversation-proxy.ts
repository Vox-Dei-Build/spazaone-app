import axios, { isAxiosError } from "axios";
import { randomUUID } from "crypto";
import { db, functions } from "../config/main";
import { authenticateFirebaseRequest } from "../security/requestAuth";
import { formatPhoneNumber } from "../utils/phoneUtils";
import { assertStoreAccess, requireStoreId } from "../stores/storeAccess";

const BOTPRESS_HOST = "https://api.botpress.cloud";
const DEFAULT_BOT_ID = "402deb8c-c6b2-45d3-85ce-d090b99e25b0";

type JsonRecord = Record<string, unknown>;

export type SanitizedBotpressMessages = {
  messages: JsonRecord[];
  skippedMessageCount: number;
  sanitizedMessageCount: number;
};

const jsonRecord = (value: unknown): JsonRecord | null =>
  value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as JsonRecord)
    : null;

const safeDisplayString = (value: unknown): string | undefined => {
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return undefined;
};

export function parseBotpressProviderPage(
  value: unknown,
  collectionKey: "conversations" | "messages",
): { items: unknown[]; nextToken?: string } {
  const page = jsonRecord(value);
  if (!page || !Array.isArray(page[collectionKey])) {
    throw new Error("BOTPRESS_PROVIDER_CONTRACT_INVALID");
  }
  const meta = jsonRecord(page.meta);
  return {
    items: page[collectionKey] as unknown[],
    nextToken: safeDisplayString(meta?.nextToken),
  };
}

function sanitizeAction(value: unknown): JsonRecord | null {
  const action = jsonRecord(value);
  if (!action) return null;
  const sanitized: JsonRecord = { ...action };
  for (const key of ["label", "value", "title", "text", "description"]) {
    if (!(key in sanitized)) continue;
    const display = safeDisplayString(sanitized[key]);
    if (display === undefined) delete sanitized[key];
    else sanitized[key] = display;
  }
  return sanitized;
}

function sanitizePayload(value: unknown): JsonRecord {
  const payload = jsonRecord(value);
  if (!payload) return {};
  const sanitized: JsonRecord = { ...payload };

  for (const key of [
    "type",
    "kind",
    "text",
    "markdown",
    "caption",
    "value",
    "title",
    "subtitle",
    "description",
    "address",
    "footer",
    "buttonLabel",
    "fileName",
    "imageUrl",
    "audioUrl",
    "videoUrl",
    "fileUrl",
    "mediaUrl",
  ]) {
    if (!(key in sanitized)) continue;
    const display = safeDisplayString(sanitized[key]);
    if (display === undefined) delete sanitized[key];
    else sanitized[key] = display;
  }

  for (const key of ["options", "actions", "buttons", "rows"]) {
    if (!(key in sanitized)) continue;
    sanitized[key] = Array.isArray(sanitized[key])
      ? (sanitized[key] as unknown[])
          .map(sanitizeAction)
          .filter((entry): entry is JsonRecord => entry !== null)
      : [];
  }

  for (const key of ["items", "cards", "sections"]) {
    if (!(key in sanitized)) continue;
    sanitized[key] = Array.isArray(sanitized[key])
      ? (sanitized[key] as unknown[])
          .map((entry) => {
            const record = jsonRecord(entry);
            return record ? sanitizePayload(record) : null;
          })
          .filter((entry): entry is JsonRecord => entry !== null)
      : [];
  }

  return sanitized;
}

/**
 * Produces the narrow response contract consumed by released Flutter clients.
 * A malformed provider record is isolated instead of poisoning the full page.
 */
export function sanitizeBotpressMessages(
  values: readonly unknown[],
): SanitizedBotpressMessages {
  const messages: JsonRecord[] = [];
  let skippedMessageCount = 0;
  let sanitizedMessageCount = 0;

  for (const value of values) {
    const message = jsonRecord(value);
    if (!message) {
      skippedMessageCount += 1;
      continue;
    }
    const id = safeDisplayString(message.id)?.trim();
    if (!id) {
      skippedMessageCount += 1;
      continue;
    }
    const payload = sanitizePayload(message.payload);
    const tags = jsonRecord(message.tags) ?? {};
    if (!jsonRecord(message.payload) || !jsonRecord(message.tags)) {
      sanitizedMessageCount += 1;
    }
    messages.push({
      id,
      payload,
      createdAt: safeDisplayString(message.createdAt ?? message.created_at),
      direction: safeDisplayString(message.direction),
      tags,
    });
  }
  return { messages, skippedMessageCount, sanitizedMessageCount };
}

const normalizedDigits = (raw: unknown): string =>
  formatPhoneNumber(String(raw ?? "")).replace(/\D/g, "");

export const getBotpressMessages = functions
  .runWith({ secrets: ["BOTPRESS_API_TOKEN"] })
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
      res.status(405).json({
        error: "Method not allowed.",
        code: "METHOD_NOT_ALLOWED",
      });
      return;
    }

    const authenticatedUid = await authenticateFirebaseRequest(req, res, {
      requireAppCheck: true,
    });
    if (!authenticatedUid) return;

    let merchantId: string;
    try {
      merchantId = requireStoreId(req.body?.storeId ?? authenticatedUid);
      await assertStoreAccess(authenticatedUid, merchantId);
    } catch (error) {
      res.status(403).json({ error: "Access denied.", code: "ACCESS_DENIED" });
      return;
    }

    const customerId = String(req.body?.customerId ?? "").trim();
    if (!customerId) {
      res.status(400).json({
        error: "customerId is required.",
        code: "INVALID_ARGUMENT",
      });
      return;
    }

    const customer = await db
      .collection("users")
      .doc(merchantId)
      .collection("customers")
      .doc(customerId)
      .get();
    const customerNumber = normalizedDigits(customer.data()?.number);
    if (!customer.exists || !customerNumber) {
      res.status(403).json({
        error: "Customer access could not be verified.",
        code: "CUSTOMER_ACCESS_DENIED",
      });
      return;
    }

    const requestId = randomUUID();
    const apiToken = process.env.BOTPRESS_API_TOKEN?.trim();
    const botId = process.env.BOTPRESS_BOT_ID?.trim() || DEFAULT_BOT_ID;
    if (!apiToken) {
      res.status(503).json({
        error: "Conversation service unavailable.",
        state: "error",
        diagnostic: {
          code: "BOTPRESS_CONFIGURATION_MISSING",
          requestId,
        },
      });
      return;
    }

    const headers = {
      Authorization: `Bearer ${apiToken}`,
      "x-bot-id": botId,
    };
    try {
      let conversationId: string | null = null;
      let nextToken: string | undefined;
      let conversationPages = 0;
      let conversationsScanned = 0;
      for (let page = 0; page < 20 && !conversationId; page += 1) {
        const response = await axios.get(
          `${BOTPRESS_HOST}/v1/chat/conversations`,
          {
            headers,
            params: nextToken ? { nextToken } : undefined,
            timeout: 10_000,
          },
        );
        const providerPage = parseBotpressProviderPage(
          response.data,
          "conversations",
        );
        const conversations = providerPage.items;
        conversationPages += 1;
        conversationsScanned += conversations.length;
        const match = conversations
          .map(jsonRecord)
          .filter((conversation): conversation is JsonRecord =>
            Boolean(conversation),
          )
          .find((conversation) => {
            const tags = jsonRecord(conversation.tags);
            return (
              normalizedDigits(tags?.["whatsapp:userPhone"]) === customerNumber
            );
          });
        conversationId = safeDisplayString(match?.id) ?? null;
        nextToken = providerPage.nextToken;
        if (!nextToken) break;
      }

      if (!conversationId) {
        console.info("[getBotpressMessages] conversation not found", {
          surface: "botpress_conversation",
          stage: "provider_lookup",
          code: "BOTPRESS_CONVERSATION_NOT_FOUND",
          retryOutcome: "not_applicable",
          requestId,
          conversationPages,
          conversationsScanned,
        });
        res.status(200).json({
          messages: [],
          state: "not_found",
          diagnostic: {
            code: "BOTPRESS_CONVERSATION_NOT_FOUND",
            requestId,
            conversationPages,
            conversationsScanned,
          },
        });
        return;
      }

      const messages: unknown[] = [];
      nextToken = undefined;
      let messagePages = 0;
      for (let page = 0; page < 20; page += 1) {
        const response = await axios.get(`${BOTPRESS_HOST}/v1/chat/messages`, {
          headers,
          params: {
            conversationId,
            ...(nextToken ? { nextToken } : {}),
          },
          timeout: 10_000,
        });
        const providerPage = parseBotpressProviderPage(
          response.data,
          "messages",
        );
        messagePages += 1;
        messages.push(...providerPage.items);
        nextToken = providerPage.nextToken;
        if (!nextToken) break;
      }

      const sanitized = sanitizeBotpressMessages(messages);
      res.status(200).json({
        messages: sanitized.messages,
        state: "ok",
        diagnostic: {
          code: "BOTPRESS_MESSAGES_FETCHED",
          requestId,
          conversationPages,
          conversationsScanned,
          messagePages,
          messageCount: sanitized.messages.length,
          skippedMessageCount: sanitized.skippedMessageCount,
          sanitizedMessageCount: sanitized.sanitizedMessageCount,
        },
      });
    } catch (error) {
      const status = isAxiosError(error) ? error.response?.status : null;
      console.error("[getBotpressMessages] provider request failed", {
        surface: "botpress_conversation",
        stage: "provider_transport",
        code: "BOTPRESS_PROVIDER_UNAVAILABLE",
        retryOutcome: "not_applicable",
        requestId,
        status,
      });
      res.status(502).json({
        error: "Conversation service unavailable.",
        state: "error",
        diagnostic: {
          code: "BOTPRESS_PROVIDER_UNAVAILABLE",
          requestId,
          providerStatus: status ?? null,
        },
      });
    }
  });
