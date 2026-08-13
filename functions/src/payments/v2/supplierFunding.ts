import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import { cjSandboxMode, getCjBalanceUsdMinor } from "../../commerce/cjClient";
import {
  requireMinorUnits,
  requirePositiveMinorUnits,
  stableDocumentId,
} from "./domain";

const RESERVATION_TTL_MS = 45 * 60 * 1000;
const LOW_BALANCE_ALERT_USD_MINOR = 2_000;

export type SupplierFundingReservationStatus =
  | "active"
  | "released"
  | "consumed"
  | "expired";

export function supplierFundingReservationId(orderId: string): string {
  return stableDocumentId("sfr", [orderId]);
}

export function availableSupplierFunding(input: {
  providerBalanceUsdMinor: number;
  outstandingUsdMinor: number;
  currentReservationUsdMinor?: number;
}): number {
  const balance = requireMinorUnits(
    input.providerBalanceUsdMinor,
    "provider_balance_usd",
  );
  const outstanding = Number(input.outstandingUsdMinor ?? 0);
  const current = Number(input.currentReservationUsdMinor ?? 0);
  if (
    !Number.isSafeInteger(outstanding) ||
    outstanding < 0 ||
    !Number.isSafeInteger(current) ||
    current < 0 ||
    current > outstanding
  ) {
    throw new Error("SUPPLIER_FUNDING_STATE_INVALID");
  }
  return balance - (outstanding - current);
}

async function upsertReservation(input: {
  orderId: string;
  intentId?: string;
  requiredUsdMinor: number;
  mode: "initialize" | "post_payment_requote";
}): Promise<{
  reservationId: string;
  deduped: boolean;
  remainingUsdMinor: number;
}> {
  const required = requirePositiveMinorUnits(
    input.requiredUsdMinor,
    "supplier_funding_required",
  );
  // The provider call happens immediately before the serialized state update;
  // stale cached balances are never trusted for a new or enlarged commitment.
  const providerBalanceUsdMinor = await getCjBalanceUsdMinor();
  const providerBalanceMode = cjSandboxMode()
    ? "sandbox_simulated"
    : "provider_live";
  const observedAtMs = Date.now();
  const reservationId = supplierFundingReservationId(input.orderId);
  const reservationRef = db.doc(`supplierFundingReservations/${reservationId}`);
  const stateRef = db.doc("supplierFundingState/cj");
  let deduped = false;
  let remainingUsdMinor = 0;
  let insufficient = false;
  await db.runTransaction(async (tx) => {
    const [state, existing] = await Promise.all([
      tx.get(stateRef),
      tx.get(reservationRef),
    ]);
    const stateData = state.data() ?? {};
    const existingData = existing.data() ?? {};
    const existingActive = existingData.status === "active";
    const existingAmount = existingActive
      ? requirePositiveMinorUnits(
          existingData.requiredUsdMinor,
          "existing_funding",
        )
      : 0;
    const outstanding = Number(stateData.outstandingUsdMinor ?? 0);
    const available = availableSupplierFunding({
      providerBalanceUsdMinor,
      outstandingUsdMinor: outstanding,
      currentReservationUsdMinor: existingAmount,
    });
    if (available < required) {
      insufficient = true;
      remainingUsdMinor = Math.max(0, available);
      const now = FieldValue.serverTimestamp();
      const alertId = stableDocumentId("alert", [
        "cj_balance_insufficient",
        String(Math.floor(observedAtMs / RESERVATION_TTL_MS)),
      ]);
      tx.set(
        stateRef,
        {
          provider: "cj_dropshipping",
          providerBalanceMode,
          providerBalanceUsdMinor,
          providerBalanceObservedAtMs: observedAtMs,
          outstandingUsdMinor: outstanding,
          remainingUsdMinor,
          lastRejectedRequiredUsdMinor: required,
          lastRejectedAt: now,
          updatedAt: now,
          schemaVersion: 2,
        },
        { merge: true },
      );
      tx.set(
        db.doc(`operationsAlerts/${alertId}`),
        {
          alertId,
          type: "supplier_funding_insufficient",
          provider: "cj_dropshipping",
          requiredUsdMinor: required,
          availableUsdMinor: remainingUsdMinor,
          providerBalanceUsdMinor,
          outstandingUsdMinor: outstanding,
          owner: "operations",
          status: "open",
          createdAt: now,
          updatedAt: now,
          schemaVersion: 2,
        },
        { merge: true },
      );
      return;
    }
    const nextOutstanding = outstanding - existingAmount + required;
    remainingUsdMinor = providerBalanceUsdMinor - nextOutstanding;
    deduped =
      existingActive &&
      existingAmount === required &&
      Number(existingData.expiresAtMs ?? 0) > observedAtMs;
    const now = FieldValue.serverTimestamp();
    tx.set(
      stateRef,
      {
        provider: "cj_dropshipping",
        providerBalanceMode,
        providerBalanceUsdMinor,
        providerBalanceObservedAtMs: observedAtMs,
        outstandingUsdMinor: nextOutstanding,
        remainingUsdMinor,
        lockSequence: FieldValue.increment(1),
        updatedAt: now,
        schemaVersion: 2,
      },
      { merge: true },
    );
    tx.set(
      reservationRef,
      {
        reservationId,
        orderId: input.orderId,
        intentId: input.intentId ?? existingData.intentId ?? null,
        provider: "cj_dropshipping",
        providerBalanceMode,
        requiredUsdMinor: required,
        status: "active",
        mode: input.mode,
        expiresAtMs: observedAtMs + RESERVATION_TTL_MS,
        providerBalanceObservedAtMs: observedAtMs,
        createdAt: existing.exists ? (existingData.createdAt ?? now) : now,
        updatedAt: now,
        schemaVersion: 2,
      },
      { merge: true },
    );
    if (remainingUsdMinor < LOW_BALANCE_ALERT_USD_MINOR) {
      const alertId = stableDocumentId("alert", [
        "cj_low_balance",
        String(Math.floor(observedAtMs / RESERVATION_TTL_MS)),
      ]);
      tx.set(
        db.doc(`operationsAlerts/${alertId}`),
        {
          alertId,
          type: "supplier_funding_low_balance",
          provider: "cj_dropshipping",
          remainingUsdMinor,
          outstandingUsdMinor: nextOutstanding,
          owner: "operations",
          status: "open",
          createdAt: now,
          updatedAt: now,
          schemaVersion: 2,
        },
        { merge: true },
      );
    }
  });
  if (insufficient) throw new Error("CJ_BALANCE_INSUFFICIENT");
  return { reservationId, deduped, remainingUsdMinor };
}

export async function reserveSupplierFunding(input: {
  orderId: string;
  intentId?: string;
  requiredUsdMinor: number;
}): Promise<{
  reservationId: string;
  deduped: boolean;
  remainingUsdMinor: number;
}> {
  return upsertReservation({ ...input, mode: "initialize" });
}

export async function confirmSupplierFunding(input: {
  orderId: string;
  intentId: string;
  requiredUsdMinor: number;
}): Promise<{
  reservationId: string;
  deduped: boolean;
  remainingUsdMinor: number;
}> {
  return upsertReservation({ ...input, mode: "post_payment_requote" });
}

async function closeSupplierFundingReservation(
  reservationId: string,
  status: "released" | "consumed" | "expired",
  reason: string,
): Promise<boolean> {
  const ref = db.doc(`supplierFundingReservations/${reservationId}`);
  const stateRef = db.doc("supplierFundingState/cj");
  let changed = false;
  await db.runTransaction(async (tx) => {
    const [reservation, state] = await Promise.all([
      tx.get(ref),
      tx.get(stateRef),
    ]);
    if (!reservation.exists) return;
    if (reservation.get("status") === status) {
      changed = true;
      return;
    }
    if (reservation.get("status") !== "active") return;
    const required = requirePositiveMinorUnits(
      reservation.get("requiredUsdMinor"),
      "supplier_funding_required",
    );
    const outstanding = Number(state.get("outstandingUsdMinor") ?? 0);
    if (!Number.isSafeInteger(outstanding) || outstanding < required) {
      throw new Error("SUPPLIER_FUNDING_STATE_INVALID");
    }
    const nextOutstanding = outstanding - required;
    const balance = Number(state.get("providerBalanceUsdMinor") ?? 0);
    const now = FieldValue.serverTimestamp();
    tx.update(ref, {
      status,
      closeReason: reason.slice(0, 160),
      closedAt: now,
      updatedAt: now,
    });
    tx.set(
      stateRef,
      {
        outstandingUsdMinor: nextOutstanding,
        remainingUsdMinor: Math.max(0, balance - nextOutstanding),
        updatedAt: now,
      },
      { merge: true },
    );
    changed = true;
  });
  return changed;
}

export function releaseSupplierFunding(
  reservationId: string,
  reason: string,
): Promise<boolean> {
  return closeSupplierFundingReservation(reservationId, "released", reason);
}

export function consumeSupplierFunding(
  reservationId: string,
): Promise<boolean> {
  return closeSupplierFundingReservation(
    reservationId,
    "consumed",
    "cj_order_paid",
  );
}

export const expireSupplierFundingReservations = functions.pubsub
  .schedule("every 5 minutes")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    const expired = await db
      .collection("supplierFundingReservations")
      .where("status", "==", "active")
      .where("expiresAtMs", "<=", Date.now())
      .limit(100)
      .get();
    for (const doc of expired.docs) {
      await closeSupplierFundingReservation(
        doc.id,
        "expired",
        "reservation_expired",
      );
    }
    return null;
  });
