import axios from "axios";
import { db, functions } from "../config/main";
import { authenticateFirebaseRequest } from "../security/requestAuth";
import { formatPhoneNumber } from "../utils/phoneUtils";

const BOTPRESS_HOST = "https://api.botpress.cloud";
const DEFAULT_BOT_ID = "402deb8c-c6b2-45d3-85ce-d090b99e25b0";

type BotpressMessagesResponse = {
  data?: {
    messages?: unknown[];
    meta?: { nextToken?: string };
  };
};

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
      res.status(405).json({ error: "Method not allowed." });
      return;
    }

    const merchantId = await authenticateFirebaseRequest(req, res, {
      requireAppCheck: true,
    });
    if (!merchantId) return;

    const customerId = String(req.body?.customerId ?? "").trim();
    if (!customerId) {
      res.status(400).json({ error: "customerId is required." });
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
      res.status(403).json({ error: "Customer access could not be verified." });
      return;
    }

    const apiToken = process.env.BOTPRESS_API_TOKEN?.trim();
    const botId = process.env.BOTPRESS_BOT_ID?.trim() || DEFAULT_BOT_ID;
    if (!apiToken) {
      res.status(503).json({ error: "Conversation service unavailable." });
      return;
    }

    const headers = {
      Authorization: `Bearer ${apiToken}`,
      "x-bot-id": botId,
    };

    try {
      let conversationId: string | null = null;
      let nextToken: string | undefined;
      for (let page = 0; page < 20 && !conversationId; page += 1) {
        const response = await axios.get(
          `${BOTPRESS_HOST}/v1/chat/conversations`,
          {
            headers,
            params: nextToken ? { nextToken } : undefined,
            timeout: 10_000,
          },
        );
        const conversations = Array.isArray(response.data?.conversations)
          ? response.data.conversations
          : [];
        const match = conversations.find(
          (conversation: { id?: string; tags?: Record<string, unknown> }) =>
            normalizedDigits(conversation.tags?.["whatsapp:userPhone"]) ===
            customerNumber,
        );
        conversationId = match?.id ?? null;
        nextToken = response.data?.meta?.nextToken;
        if (!nextToken) break;
      }

      if (!conversationId) {
        res.status(200).json({ messages: [] });
        return;
      }

      const messages: unknown[] = [];
      nextToken = undefined;
      for (let page = 0; page < 20; page += 1) {
        const response: BotpressMessagesResponse = await axios.get(
          `${BOTPRESS_HOST}/v1/chat/messages`,
          {
            headers,
            params: {
              conversationId,
              ...(nextToken ? { nextToken } : {}),
            },
            timeout: 10_000,
          },
        );
        const responseData = response.data ?? {};
        const pageMessages = Array.isArray(responseData.messages)
          ? responseData.messages
          : [];
        messages.push(
          ...pageMessages.map(
            (message: {
              id?: string;
              payload?: unknown;
              createdAt?: unknown;
              created_at?: unknown;
              direction?: unknown;
              tags?: unknown;
            }) => ({
              id: message.id,
              payload: message.payload,
              createdAt: message.createdAt ?? message.created_at,
              direction: message.direction,
              tags: message.tags,
            }),
          ),
        );
        nextToken = responseData.meta?.nextToken;
        if (!nextToken) break;
      }

      res.status(200).json({ messages });
    } catch (error) {
      const status = axios.isAxiosError(error) ? error.response?.status : null;
      console.error("[getBotpressMessages] provider request failed", {
        status,
      });
      res.status(502).json({ error: "Conversation service unavailable." });
    }
  });
