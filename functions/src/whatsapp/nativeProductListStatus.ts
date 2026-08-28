import { db, functions } from "../config/main";
import { requireBotRequest } from "../security/requestAuth";
import { WHATSAPP_PRODUCT_LIST_DELIVERIES } from "./nativeProductListDelivery";
import { whatsappProductListRuntimeConfig } from "./nativeProductList";

type DeliveryStatusInput = {
  status?: unknown;
  updatedAtMs?: unknown;
};

export type ProductListDeliveryHealth = {
  total: number;
  sent: number;
  sending: number;
  retryWaiting: number;
  needsReview: number;
  failed: number;
  staleSending: number;
  healthy: boolean;
};

function safeCount(value: number): number {
  return Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

export function summarizeProductListDeliveryHealth(
  values: readonly DeliveryStatusInput[],
  nowMs = Date.now(),
): ProductListDeliveryHealth {
  const counts: Record<string, number> = {};
  let staleSending = 0;
  for (const value of values) {
    const status = String(value.status ?? "unknown");
    counts[status] = safeCount(counts[status] ?? 0) + 1;
    if (
      status === "sending" &&
      nowMs - Number(value.updatedAtMs ?? 0) > 60_000
    ) {
      staleSending++;
    }
  }
  const health = {
    total: values.length,
    sent: safeCount(counts.sent ?? 0),
    sending: safeCount(counts.sending ?? 0),
    retryWaiting: safeCount(counts.retry_wait ?? 0),
    needsReview: safeCount(counts.needs_review ?? 0),
    failed: safeCount(counts.failed ?? 0),
    staleSending,
  };
  return {
    ...health,
    healthy:
      health.needsReview === 0 &&
      health.failed === 0 &&
      health.staleSending === 0,
  };
}

async function merchantDeliveries(merchantId: string) {
  return db
    .collection(WHATSAPP_PRODUCT_LIST_DELIVERIES)
    .where("merchantId", "==", merchantId)
    .limit(2_000)
    .get();
}

/** Bot-authenticated, PII-free delivery dashboard for the canary. */
export const getWhatsAppProductListDeliveryStatusBotHttp = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"], maxInstances: 2 })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    if (req.method !== "POST") {
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }
    const merchantId = String(req.body?.merchantId ?? "").trim();
    if (!/^[A-Za-z0-9_-]{1,200}$/.test(merchantId)) {
      res.status(400).json({ error: "merchantId is required" });
      return;
    }
    const snapshot = await merchantDeliveries(merchantId);
    const rows = snapshot.docs.map((doc) => ({
      id: doc.id,
      status: String(doc.data().status ?? "unknown"),
      page: Number(doc.data().page ?? 0),
      itemCount: Number(doc.data().itemCount ?? 0),
      attempts: Number(doc.data().attempts ?? 0),
      lastErrorCode: String(doc.data().lastErrorCode ?? ""),
      updatedAtMs: Number(doc.data().updatedAtMs ?? 0),
      wamid: String(doc.data().wamid ?? ""),
    }));
    res.status(200).json({
      merchantId,
      generatedAt: new Date().toISOString(),
      health: summarizeProductListDeliveryHealth(rows),
      recent: rows.sort((a, b) => b.updatedAtMs - a.updatedAtMs).slice(0, 20),
    });
  });

/**
 * Structured logging is the alert source. Cloud Monitoring can alert on the
 * stable event name without this worker sending a customer or support message.
 */
export const monitorWhatsAppProductListDeliveries = functions
  .runWith({
    secrets: ["WHATSAPP_CATALOG_RECIPIENT_HASH_KEY"],
    timeoutSeconds: 60,
    memory: "256MB",
    maxInstances: 1,
  })
  .pubsub.schedule("every 5 minutes")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    const config = whatsappProductListRuntimeConfig();
    if (!config.enabled) return null;
    const snapshot = await db
      .collection(WHATSAPP_PRODUCT_LIST_DELIVERIES)
      .limit(2_000)
      .get();
    const health = summarizeProductListDeliveryHealth(
      snapshot.docs.map((doc) => doc.data()),
    );
    if (!health.healthy) {
      console.error("[whatsapp-product-list-monitor] attention_required", {
        event: "whatsapp_product_list_delivery_attention_required",
        ...health,
      });
    } else {
      console.info("[whatsapp-product-list-monitor] healthy", {
        event: "whatsapp_product_list_delivery_healthy",
        ...health,
      });
    }
    return null;
  });
