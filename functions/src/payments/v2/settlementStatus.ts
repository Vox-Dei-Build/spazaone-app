import axios from "axios";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import { paystackProviderMode, paystackSecret } from "../../config/environment";
import { assertCallableStoreAccess } from "../../stores/storeAccess";

export type NormalizedSettlementStatus =
  | "completed"
  | "processing"
  | "failed"
  | "review_required";

export function normalizePaystackSettlementStatus(
  value: unknown,
): NormalizedSettlementStatus {
  const status = String(value ?? "")
    .trim()
    .toLowerCase();
  if (status === "success" || status === "completed") return "completed";
  if (status === "pending" || status === "processing") return "processing";
  if (status === "failed") return "failed";
  return "review_required";
}

export function addWorkingDays(date: Date, days: number): Date {
  const result = new Date(date.getTime());
  let remaining = Math.max(0, Math.floor(days));
  while (remaining > 0) {
    result.setUTCDate(result.getUTCDate() + 1);
    const weekday = result.getUTCDay();
    if (weekday !== 0 && weekday !== 6) remaining -= 1;
  }
  return result;
}

type ProviderSettlement = {
  id?: string | number;
  domain?: string;
  status?: string;
  settlement_date?: string;
};

async function providerTransactions(
  secret: string,
  settlementId: string,
): Promise<Array<Record<string, unknown>>> {
  const records: Array<Record<string, unknown>> = [];
  for (let page = 1; page <= 10; page += 1) {
    const response = await axios.get(
      `https://api.paystack.co/settlement/${encodeURIComponent(settlementId)}/transactions`,
      {
        headers: { Authorization: `Bearer ${secret}` },
        params: { perPage: 100, page },
        timeout: 15_000,
      },
    );
    const data = Array.isArray(response.data?.data) ? response.data.data : [];
    records.push(...data);
    const pageCount = Number(response.data?.meta?.pageCount ?? page);
    if (page >= pageCount || data.length === 0) break;
  }
  return records;
}

async function reconcileSettlementDocuments(input?: {
  merchantId?: string;
}): Promise<{ checked: number; matched: number; testOnly: number }> {
  const mode = paystackProviderMode();
  let query: FirebaseFirestore.Query = db
    .collection("settlements")
    .where("provider", "==", "paystack");
  if (input?.merchantId) {
    query = query.where("merchantId", "==", input.merchantId);
  }
  const snapshot = await query.limit(500).get();
  const candidates = snapshot.docs.filter((doc) => {
    const status = normalizePaystackSettlementStatus(doc.get("status"));
    return status !== "completed" && status !== "failed";
  });

  if (mode === "test") {
    const batch = db.batch();
    for (const doc of candidates) {
      batch.set(
        doc.ref,
        {
          providerMode: "test",
          testOnly: true,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    if (candidates.length > 0) await batch.commit();
    return {
      checked: candidates.length,
      matched: 0,
      testOnly: candidates.length,
    };
  }
  if (mode !== "live" || candidates.length === 0) {
    return { checked: candidates.length, matched: 0, testOnly: 0 };
  }

  const secret = paystackSecret();
  const bySubaccount = new Map<string, typeof candidates>();
  for (const doc of candidates) {
    const code = String(doc.get("subaccountCode") ?? "").trim();
    if (!/^ACCT_[A-Za-z0-9]+$/.test(code)) continue;
    bySubaccount.set(code, [...(bySubaccount.get(code) ?? []), doc]);
  }

  let matched = 0;
  for (const [subaccount, docs] of bySubaccount) {
    const oldest = Math.min(
      ...docs.map((doc) => {
        const value = doc.get("createdAt") as { toMillis?: () => number };
        return value?.toMillis?.() ?? Date.now();
      }),
    );
    const response = await axios.get("https://api.paystack.co/settlement", {
      headers: { Authorization: `Bearer ${secret}` },
      params: {
        subaccount,
        perPage: 50,
        from: new Date(oldest - 86_400_000).toISOString(),
      },
      timeout: 15_000,
    });
    const providerSettlements: ProviderSettlement[] = Array.isArray(
      response.data?.data,
    )
      ? response.data.data
      : [];
    const references = new Map<string, ProviderSettlement>();
    for (const settlement of providerSettlements) {
      const providerId = String(settlement.id ?? "").trim();
      if (!providerId) continue;
      for (const transaction of await providerTransactions(
        secret,
        providerId,
      )) {
        const reference = String(transaction.reference ?? "").trim();
        if (reference) references.set(reference, settlement);
      }
    }

    for (const doc of docs) {
      let reference = String(doc.get("providerReference") ?? "").trim();
      if (!reference) {
        const intentId = String(doc.get("intentId") ?? "").trim();
        if (intentId) {
          const intent = await db.doc(`paymentIntents/${intentId}`).get();
          reference = String(intent.get("providerReference") ?? "").trim();
        }
      }
      const providerSettlement = references.get(reference);
      if (!providerSettlement) continue;
      const providerStatus = String(providerSettlement.status ?? "");
      const normalizedStatus =
        normalizePaystackSettlementStatus(providerStatus);
      const settlementDate = new Date(
        String(providerSettlement.settlement_date ?? ""),
      );
      await doc.ref.set(
        {
          status: normalizedStatus,
          providerStatus,
          providerMode: "live",
          testOnly: false,
          providerReference: reference,
          providerSettlementId: String(providerSettlement.id ?? ""),
          ...(Number.isFinite(settlementDate.getTime())
            ? { providerSettlementAt: Timestamp.fromDate(settlementDate) }
            : {}),
          reconciledAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      matched += 1;
    }
  }
  return { checked: candidates.length, matched, testOnly: 0 };
}

export const reconcileMerchantSettlementsV2 = functions
  .runWith({ secrets: ["PAYSTACK_SECRET_KEY"] })
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in is required.",
      );
    }
    if (!context.app) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "App verification is required.",
      );
    }
    const merchantId = String(data?.merchantId ?? "").trim();
    await assertCallableStoreAccess(context, merchantId, ["owner", "admin"]);
    return reconcileSettlementDocuments({ merchantId });
  });

export const reconcilePaystackSettlementsScheduled = functions
  .runWith({
    timeoutSeconds: 540,
    memory: "1GB",
    secrets: ["PAYSTACK_SECRET_KEY"],
  })
  .pubsub.schedule("15 */6 * * *")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    await reconcileSettlementDocuments();
    return null;
  });
