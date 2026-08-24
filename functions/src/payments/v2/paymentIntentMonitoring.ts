import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import { stableDocumentId } from "./domain";
import {
  PAYMENT_INTENT_STALE_NOTIFICATION_TYPE,
  PAYMENT_OPERATIONS_WORKSPACE_URL,
  paymentIntentStaleNotificationCopy,
} from "./settlementOperationsNotifications";

export const PAYMENT_INTENT_STALE_AFTER_MINUTES = 15;
const MAX_STALE_INTENTS_PER_RUN = 200;
const MAX_OPEN_INCIDENTS_PER_RUN = 200;

type UnknownRecord = Record<string, unknown>;

function timestampMillis(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (
    value != null &&
    typeof value === "object" &&
    typeof (value as { toMillis?: unknown }).toMillis === "function"
  ) {
    const millis = Number((value as { toMillis: () => number }).toMillis());
    return Number.isFinite(millis) ? millis : null;
  }
  return null;
}

export function paymentIntentRequiresMonitoring(input: {
  value: UnknownRecord;
  nowMs: number;
  staleAfterMinutes?: number;
}): boolean {
  if (String(input.value.status ?? "") !== "initialized") return false;
  const initializedAtMs = timestampMillis(input.value.initializedAt);
  const staleAfterMinutes = Math.max(
    1,
    Math.min(24 * 60, input.staleAfterMinutes ?? 15),
  );
  return (
    initializedAtMs != null &&
    initializedAtMs <= input.nowMs - staleAfterMinutes * 60 * 1000
  );
}

export function paymentIntentMonitoringIncidentId(intentId: string): string {
  return stableDocumentId("payment_monitor", [intentId]);
}

export type PaymentIntentMonitoringResult = {
  checkedCount: number;
  detectedCount: number;
  resolvedCount: number;
  truncated: boolean;
};

export async function monitorStalePaymentIntents(input: {
  nowMs?: number;
  staleAfterMinutes?: number;
  source: "scheduled" | "test";
}): Promise<PaymentIntentMonitoringResult> {
  const nowMs = input.nowMs ?? Date.now();
  const staleAfterMinutes = Math.max(
    1,
    Math.min(
      24 * 60,
      input.staleAfterMinutes ?? PAYMENT_INTENT_STALE_AFTER_MINUTES,
    ),
  );
  const cutoff = Timestamp.fromMillis(nowMs - staleAfterMinutes * 60 * 1000);
  const [stale, openIncidents] = await Promise.all([
    db
      .collection("paymentIntents")
      .where("status", "==", "initialized")
      .where("initializedAt", "<=", cutoff)
      .orderBy("initializedAt", "asc")
      .limit(MAX_STALE_INTENTS_PER_RUN + 1)
      .get(),
    db
      .collection("paymentMonitoringIncidents")
      .where("status", "==", "open")
      .limit(MAX_OPEN_INCIDENTS_PER_RUN)
      .get(),
  ]);

  let detectedCount = 0;
  for (const intent of stale.docs.slice(0, MAX_STALE_INTENTS_PER_RUN)) {
    if (
      !paymentIntentRequiresMonitoring({
        value: intent.data(),
        nowMs,
        staleAfterMinutes,
      })
    ) {
      continue;
    }
    const incidentId = paymentIntentMonitoringIncidentId(intent.id);
    const incidentRef = db.doc(`paymentMonitoringIncidents/${incidentId}`);
    const notificationRef = db.doc(
      `paymentOperationsNotifications/${incidentId}`,
    );
    const created = await db.runTransaction(async (tx) => {
      const [currentIntent, incident] = await Promise.all([
        tx.get(intent.ref),
        tx.get(incidentRef),
      ]);
      const value = currentIntent.data() ?? {};
      if (
        !currentIntent.exists ||
        incident.exists ||
        !paymentIntentRequiresMonitoring({
          value,
          nowMs,
          staleAfterMinutes,
        })
      ) {
        return false;
      }
      const copy = paymentIntentStaleNotificationCopy();
      const now = FieldValue.serverTimestamp();
      tx.create(incidentRef, {
        incidentId,
        type: PAYMENT_INTENT_STALE_NOTIFICATION_TYPE,
        intentId: intent.id,
        merchantId: String(value.merchantId ?? ""),
        purpose: String(value.purpose ?? ""),
        intentStatus: "initialized",
        status: "open",
        source: input.source,
        initializedAt: value.initializedAt,
        staleAfterMinutes,
        notificationId: incidentId,
        schemaVersion: 1,
        firstDetectedAt: now,
        updatedAt: now,
      });
      tx.create(notificationRef, {
        notificationId: incidentId,
        type: PAYMENT_INTENT_STALE_NOTIFICATION_TYPE,
        incidentId,
        title: copy.title,
        body: copy.body,
        route: PAYMENT_OPERATIONS_WORKSPACE_URL,
        pushDeliveryState: "pending",
        schemaVersion: 1,
        createdAt: now,
      });
      return true;
    });
    if (created) detectedCount += 1;
  }

  let resolvedCount = 0;
  for (const incident of openIncidents.docs) {
    const resolved = await db.runTransaction(async (tx) => {
      const currentIncident = await tx.get(incident.ref);
      const value = currentIncident.data() ?? {};
      if (!currentIncident.exists || value.status !== "open") return false;
      const intentId = String(value.intentId ?? "");
      const intent = intentId
        ? await tx.get(db.doc(`paymentIntents/${intentId}`))
        : null;
      const intentStatus = intent?.exists
        ? String(intent.get("status") ?? "")
        : "missing";
      if (intentStatus === "initialized") return false;
      tx.update(incident.ref, {
        status: "resolved",
        resolution:
          intentStatus === "missing" ? "intent_missing" : "status_changed",
        resolutionIntentStatus: intentStatus,
        resolvedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (resolved) resolvedCount += 1;
  }

  const truncated = stale.size > MAX_STALE_INTENTS_PER_RUN;
  if (truncated) {
    console.error("[payments-v2] stale intent monitoring window truncated", {
      checkedCount: MAX_STALE_INTENTS_PER_RUN,
    });
  }
  return {
    checkedCount: Math.min(stale.size, MAX_STALE_INTENTS_PER_RUN),
    detectedCount,
    resolvedCount,
    truncated,
  };
}

export const monitorStalePaymentIntentsV2 = functions
  .runWith({ timeoutSeconds: 120, memory: "512MB" })
  .pubsub.schedule("every 10 minutes")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    await monitorStalePaymentIntents({ source: "scheduled" });
    return null;
  });
