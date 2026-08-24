import axios from "axios";
import { createHash } from "crypto";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { db, functions } from "../../config/main";
import {
  paystackPaymentActivationScope,
  paystackPaymentProviderMode,
  paystackPaymentSecret,
} from "../../config/environment";
import {
  commerceNotificationDocumentId,
  deliverCommerceOrderNotificationOutbox,
  enqueueCommerceOrderNotification,
  OrderNotice,
} from "../../commerce/notifications";
import { finalizeInventoryOnce } from "../../ecommerce/finalizeOnlinePaid";
import {
  authenticateFirebaseRequest,
  verifyBotRequest,
} from "../../security/requestAuth";
import { merchantBotFeatureDecision } from "../../ecommerce/merchantBotFeatureAccess";
import { assertStoreAccess, requireStoreId } from "../../stores/storeAccess";
import {
  buildMoneySnapshot,
  calculatePlatformFeeMinor,
  requirePositiveMinorUnits,
  stableDocumentId,
} from "./domain";
import {
  createPaymentIntentV2,
  providerEventDocumentId,
  recordProviderEventV2,
} from "./financialCore";
import { paymentReadiness } from "./readiness";

export const OWNED_ORDER_CHANNELS = [
  "card",
  "eft",
  "capitec_pay",
  "qr",
] as const;
export type OwnedOrderChannel = (typeof OWNED_ORDER_CHANNELS)[number];

export function isOwnedOrderChannel(
  value: unknown,
): value is OwnedOrderChannel {
  return OWNED_ORDER_CHANNELS.includes(value as OwnedOrderChannel);
}

function roundRational(numerator: number, denominator: number): number {
  return Math.floor((numerator + Math.floor(denominator / 2)) / denominator);
}

/** Conservative quote; Paystack's verified fee is stored at payment time. */
export function estimatedOwnedOrderProviderFeeMinor(input: {
  amountMinor: number;
  channel: OwnedOrderChannel;
}): number {
  const amount = requirePositiveMinorUnits(input.amountMinor, "amount");
  if (!isOwnedOrderChannel(input.channel))
    throw new Error("ORDER_CHANNEL_INVALID");
  const rateBps =
    input.channel === "card"
      ? 310
      : ["eft", "capitec_pay"].includes(input.channel)
        ? 200
        : 290;
  const flat =
    ["card", "qr"].includes(input.channel) && amount >= 1000 ? 100 : 0;
  return roundRational(
    (amount * rateBps + flat * 10_000) * 11_500,
    100_000_000,
  );
}

function publicError(error: unknown): { status: number; message: string } {
  if (error instanceof functions.https.HttpsError) {
    const status =
      error.code === "unauthenticated"
        ? 401
        : error.code === "permission-denied"
          ? 403
          : error.code === "failed-precondition"
            ? 409
            : 400;
    return { status, message: error.message };
  }
  const code = error instanceof Error ? error.message : "";
  const known: Record<string, [number, string]> = {
    PAYMENT_CAPABILITY_DISABLED: [
      409,
      "Online payment is not available for this shop yet.",
    ],
    MERCHANT_SETTLEMENT_NOT_APPROVED: [
      409,
      "The shop's settlement account is not ready.",
    ],
    INVENTORY_RESERVATION_NOT_ACTIVE: [
      409,
      "The stock reservation expired. Review the cart and try again.",
    ],
    SALE_ALREADY_PAID: [409, "This order is already paid."],
    ORDER_CHANNEL_INVALID: [400, "Choose an available payment method."],
  };
  const mapped = known[code];
  return mapped
    ? { status: mapped[0], message: mapped[1] }
    : { status: 500, message: "The payment could not be prepared." };
}

function referenceForIntent(intentId: string): string {
  return `p2-${createHash("sha256").update(intentId).digest("hex").slice(0, 36)}`;
}

export const handleCreateOwnedOrderPaymentV2 = async (
  req: functions.https.Request,
  res: functions.Response,
): Promise<void> => {
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method Not Allowed" });
    return;
  }
  try {
    const merchantId = requireStoreId(req.body?.merchantId);
    let initiatedBy = "bot";
    const botRequest = verifyBotRequest(req);
    if (!botRequest) {
      const uid = await authenticateFirebaseRequest(req, res);
      if (!uid) return;
      await assertStoreAccess(uid, merchantId);
      initiatedBy = uid;
    }
    if (
      botRequest &&
      !(await merchantBotFeatureDecision(merchantId, "ownedOrderPayments"))
        .enabled
    ) {
      res.status(409).json({
        error:
          "This shop needs to update Spaza One before online payments can be used.",
        code: "MERCHANT_APP_UPDATE_REQUIRED",
      });
      return;
    }
    const readiness = await paymentReadiness({
      merchantId,
      purpose: "merchant_order",
    });
    if (!readiness.enabled) throw new Error("PAYMENT_CAPABILITY_DISABLED");
    const paymentContext = { merchantId, purpose: "merchant_order" };
    const providerMode = paystackPaymentProviderMode(paymentContext);
    const activationScope = paystackPaymentActivationScope(paymentContext);
    const orderId = String(req.body?.orderId ?? "").trim();
    if (!/^[A-Za-z0-9_-]{1,200}$/.test(orderId)) {
      res.status(400).json({ error: "A valid order is required." });
      return;
    }
    const email = String(req.body?.email ?? "")
      .trim()
      .toLowerCase();
    if (!/^\S+@\S+\.\S+$/.test(email)) {
      res.status(400).json({ error: "Enter a valid email address." });
      return;
    }
    const channel = String(req.body?.channel ?? "").trim();
    if (!isOwnedOrderChannel(channel)) throw new Error("ORDER_CHANNEL_INVALID");
    if (!(readiness.channels ?? []).includes(channel)) {
      throw new Error("ORDER_CHANNEL_INVALID");
    }
    const [sale, profile] = await Promise.all([
      db.doc(`users/${merchantId}/sales/${orderId}`).get(),
      db.doc(`merchantPaymentProfiles/${merchantId}`).get(),
    ]);
    if (!sale.exists) {
      res.status(404).json({ error: "Order not found." });
      return;
    }
    const saleData = sale.data() ?? {};
    if (
      botRequest &&
      String(saleData.customerId ?? "") !==
        String(req.body?.customerId ?? "").trim()
    ) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "This WhatsApp customer does not own that order.",
      );
    }
    if (
      String(saleData.paymentRail ?? "") !== "paystack_v2" ||
      String(saleData.status ?? "") !== "pending_payment" ||
      String(saleData.paymentStatus ?? "") !== "pending"
    ) {
      throw new Error("SALE_ALREADY_PAID");
    }
    const profileData = profile.data() ?? {};
    const subaccountCode = String(profileData.paystackSubaccountCode ?? "");
    if (
      profileData.bankVerificationStatus !== "approved" ||
      !/^ACCT_[A-Za-z0-9]+$/.test(subaccountCode)
    ) {
      throw new Error("MERCHANT_SETTLEMENT_NOT_APPROVED");
    }
    const reservationId = String(saleData.inventoryReservationId ?? "");
    const reservationRef = db.doc(`inventoryReservations/${reservationId}`);
    const reservation = await reservationRef.get();
    const reservationData = reservation.data() ?? {};
    const expiresAt = reservationData.expiresAt as Timestamp | undefined;
    if (
      !reservation.exists ||
      reservationData.status !== "active" ||
      reservationData.merchantId !== merchantId ||
      reservationData.orderId !== orderId ||
      !expiresAt ||
      expiresAt.toMillis() <= Date.now()
    ) {
      throw new Error("INVENTORY_RESERVATION_NOT_ACTIVE");
    }
    const amountMinor = requirePositiveMinorUnits(
      reservationData.totalAmountMinor,
      "order_amount",
    );
    const platformFeeMinor = calculatePlatformFeeMinor({
      grossAmountMinor: amountMinor,
    });
    const providerFeeMinor = estimatedOwnedOrderProviderFeeMinor({
      amountMinor,
      channel,
    });
    const money = buildMoneySnapshot({
      grossAmountMinor: amountMinor,
      platformFeeMinor,
      providerFeeMinor,
    });
    const created = await createPaymentIntentV2({
      merchantId,
      purpose: "merchant_order",
      idempotencyKey: `owned-order:${orderId}`,
      expectedAmountMinor: amountMinor,
      businessBinding: { type: "owned_order", id: orderId },
      money,
      initiatedBy,
    });
    const intentRef = db.doc(`paymentIntents/${created.intentId}`);
    const reference = referenceForIntent(created.intentId);
    const claimId = stableDocumentId("claim", [
      created.intentId,
      initiatedBy,
      String(Date.now()),
    ]);
    const existing = await db.runTransaction(async (tx) => {
      const [intent, currentReservation] = await Promise.all([
        tx.get(intentRef),
        tx.get(reservationRef),
      ]);
      const intentData = intent.data() ?? {};
      const currentReservationData = currentReservation.data() ?? {};
      if (intentData.status === "initialized") {
        return {
          authorizationUrl: String(intentData.authorizationUrl ?? ""),
          providerReference: String(intentData.providerReference ?? ""),
        };
      }
      if (currentReservationData.status !== "active") {
        throw new Error("INVENTORY_RESERVATION_NOT_ACTIVE");
      }
      if (
        currentReservationData.paymentIntentId &&
        currentReservationData.paymentIntentId !== created.intentId
      ) {
        throw new Error("INVENTORY_RESERVATION_PAYMENT_COLLISION");
      }
      if (
        intentData.initializationState === "processing" &&
        Number(intentData.initializationLeaseUntilMs ?? 0) > Date.now()
      ) {
        throw new Error("PAYMENT_INITIALIZATION_IN_PROGRESS");
      }
      const now = FieldValue.serverTimestamp();
      tx.update(intentRef, {
        initializationState: "processing",
        initializationClaimId: claimId,
        initializationLeaseUntilMs: Date.now() + 45_000,
        initializationAttempts: FieldValue.increment(1),
        selectedChannel: channel,
        inventoryReservationId: reservationId,
        paystackSubaccountCode: subaccountCode,
        settlementDestination: {
          bankName: String(profileData.bankName ?? ""),
          accountName: String(profileData.resolvedAccountName ?? ""),
          accountLast4: String(profileData.accountLast4 ?? ""),
        },
        providerMode,
        activationScope,
        updatedAt: now,
      });
      tx.update(reservationRef, {
        paymentIntentId: created.intentId,
        providerReference: reference,
        updatedAt: now,
      });
      tx.set(
        db.doc(`users/${merchantId}/sales/${orderId}`),
        {
          paymentIntentId: created.intentId,
          paymentReference: reference,
          updatedAt: now,
        },
        { merge: true },
      );
      return { authorizationUrl: "", providerReference: "" };
    });
    if (existing.authorizationUrl && existing.providerReference) {
      res.status(200).json({
        authorizationUrl: existing.authorizationUrl,
        reference: existing.providerReference,
        intentId: created.intentId,
        amountMinor,
        deduped: true,
      });
      return;
    }
    try {
      const response = await axios.post(
        "https://api.paystack.co/transaction/initialize",
        {
          email,
          amount: amountMinor,
          currency: "ZAR",
          channels: [channel],
          reference,
          subaccount: subaccountCode,
          transaction_charge: platformFeeMinor,
          bearer: "subaccount",
          ...(process.env.PAYSTACK_CALLBACK_URL
            ? { callback_url: process.env.PAYSTACK_CALLBACK_URL }
            : {}),
          metadata: {
            schemaVersion: 2,
            purpose: "merchant_order",
            intentId: created.intentId,
            merchantId,
            orderId,
            reservationId,
            selectedChannel: channel,
          },
        },
        {
          headers: {
            Authorization: `Bearer ${paystackPaymentSecret(paymentContext)}`,
          },
          timeout: 15_000,
        },
      );
      const authorizationUrl = String(
        response.data?.data?.authorization_url ?? "",
      ).trim();
      const providerReference = String(
        response.data?.data?.reference ?? "",
      ).trim();
      if (!authorizationUrl || providerReference !== reference) {
        throw new Error("PAYSTACK_INITIALIZE_RESPONSE_INVALID");
      }
      await db.runTransaction(async (tx) => {
        const intent = await tx.get(intentRef);
        const data = intent.data() ?? {};
        if (
          data.status === "initialized" &&
          data.providerReference === reference
        ) {
          return;
        }
        if (data.initializationClaimId !== claimId) {
          throw new Error("PAYMENT_INITIALIZATION_CLAIM_LOST");
        }
        tx.update(intentRef, {
          status: "initialized",
          previousStatus: "created",
          provider: "paystack",
          providerReference: reference,
          authorizationUrl,
          initializationState: "completed",
          initializationLeaseUntilMs: 0,
          initializedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
      res.status(200).json({
        authorizationUrl,
        reference,
        intentId: created.intentId,
        amountMinor,
        deduped: created.deduped,
      });
    } catch (error) {
      await intentRef.set(
        {
          initializationState: "retryable",
          initializationLeaseUntilMs: 0,
          initializationErrorCode: "provider_initialization_failed",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      throw error;
    }
  } catch (error) {
    console.error("[payments-v2] owned order initialization failed", {
      code: error instanceof Error ? error.message : "unknown",
    });
    const response = publicError(error);
    res.status(response.status).json({ error: response.message });
  }
};

export const createOwnedOrderPaymentV2 = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN", "PAYSTACK_SECRET_KEY"] })
  .https.onRequest(handleCreateOwnedOrderPaymentV2);

export async function applyVerifiedOwnedOrderPaymentV2(
  transaction: Record<string, any>,
  rawBody: Buffer,
): Promise<{ deduped: boolean; intentId: string; notificationId?: string }> {
  const metadata = transaction.metadata ?? {};
  const intentId = String(metadata.intentId ?? "").trim();
  if (!/^pi_[a-f0-9]{64}$/.test(intentId)) throw new Error("INTENT_ID_INVALID");
  const reference = String(transaction.reference ?? "").trim();
  const amountMinor = requirePositiveMinorUnits(transaction.amount, "amount");
  const providerFeeMinor = Number(transaction.fees ?? 0);
  if (!Number.isSafeInteger(providerFeeMinor) || providerFeeMinor < 0) {
    throw new Error("PROVIDER_FEE_INVALID");
  }
  const channel = String(transaction.channel ?? "").trim();
  if (!isOwnedOrderChannel(channel)) throw new Error("ORDER_CHANNEL_INVALID");
  const providerId = String(transaction.id ?? "").trim();
  const eventInput = {
    provider: "paystack" as const,
    ...(providerId ? { providerEventId: `charge-${providerId}` } : {}),
    eventType: "charge.success",
    reference,
    rawBody,
    intentId,
  };
  const recorded = await recordProviderEventV2(eventInput);
  const eventRef = db.doc(
    `paymentEvents/${providerEventDocumentId(eventInput)}`,
  );
  const intentRef = db.doc(`paymentIntents/${intentId}`);
  const intentBefore = await intentRef.get();
  if (!intentBefore.exists) throw new Error("INTENT_NOT_FOUND");
  const initial = intentBefore.data() ?? {};
  const merchantId = requireStoreId(initial.merchantId);
  const orderId = String(initial.businessBinding?.id ?? "");
  const reservationId = String(initial.inventoryReservationId ?? "");
  if (
    initial.purpose !== "merchant_order" ||
    initial.businessBinding?.type !== "owned_order" ||
    String(initial.providerReference ?? "") !== reference ||
    String(initial.selectedChannel ?? "") !== channel ||
    Number(initial.expectedAmountMinor) !== amountMinor ||
    String(metadata.merchantId ?? "") !== merchantId ||
    String(metadata.orderId ?? "") !== orderId ||
    String(metadata.reservationId ?? "") !== reservationId
  ) {
    throw new Error("OWNED_ORDER_PAYMENT_BINDING_MISMATCH");
  }
  const saleRef = db.doc(`users/${merchantId}/sales/${orderId}`);
  const reservationRef = db.doc(`inventoryReservations/${reservationId}`);
  const settlementId = stableDocumentId("st", [intentId]);
  const settlementRef = db.doc(`settlements/${settlementId}`);
  let notificationId = "";
  let finalizedCustomerId = "";
  let shouldFinalize = false;
  let deduped = recorded.deduped;
  await db.runTransaction(async (tx) => {
    const [intent, event, sale, reservation, settlement] = await Promise.all([
      tx.get(intentRef),
      tx.get(eventRef),
      tx.get(saleRef),
      tx.get(reservationRef),
      tx.get(settlementRef),
    ]);
    if (
      !intent.exists ||
      !event.exists ||
      !sale.exists ||
      !reservation.exists
    ) {
      throw new Error("OWNED_ORDER_PAYMENT_CORE_MISSING");
    }
    const intentData = intent.data() ?? {};
    const saleData = sale.data() ?? {};
    finalizedCustomerId = String(
      saleData.customerId ?? saleData.customerID ?? "",
    );
    const applied = Array.isArray(intentData.appliedProviderEventIds)
      ? intentData.appliedProviderEventIds.map(String)
      : [];
    if (applied.includes(eventRef.id)) {
      deduped = true;
      shouldFinalize = intentData.status === "paid";
      return;
    }
    const reservationData = reservation.data() ?? {};
    const expired =
      reservationData.status !== "active" ||
      !(reservationData.expiresAt instanceof Timestamp) ||
      reservationData.expiresAt.toMillis() <= Date.now();
    const now = FieldValue.serverTimestamp();
    if (expired) {
      const refundCaseId = stableDocumentId("rf", [
        intentId,
        "stock_unavailable",
      ]);
      tx.set(
        db.doc(`refundCases/${refundCaseId}`),
        {
          refundCaseId,
          intentId,
          refundAmountMinor: amountMinor,
          currency: "ZAR",
          status: "requested",
          provider: "paystack",
          providerConfirmed: false,
          reason: "owned_inventory_reservation_unavailable_after_payment",
          owner: "operations",
          attemptCount: 0,
          schemaVersion: 2,
          createdAt: now,
          updatedAt: now,
        },
        { merge: false },
      );
      tx.update(intentRef, {
        status: "refund_pending",
        previousStatus: String(intentData.status ?? "initialized"),
        providerAmountMinor: amountMinor,
        providerFeeMinor,
        requestedRefundMinor: amountMinor,
        appliedProviderEventIds: FieldValue.arrayUnion(eventRef.id),
        updatedAt: now,
      });
      tx.set(
        saleRef,
        {
          status: "cancelled",
          paymentStatus: "refund_pending",
          refundCaseId,
          updatedAt: now,
        },
        { merge: true },
      );
      tx.update(eventRef, {
        processingState: "applied_refund_pending",
        attemptCount: FieldValue.increment(1),
        processedAt: now,
        updatedAt: now,
      });
      return;
    }
    if (settlement.exists) throw new Error("SETTLEMENT_IDEMPOTENCY_COLLISION");
    const platformFeeMinor = Number(intentData.money?.platformFeeMinor ?? 0);
    const actualMoney = buildMoneySnapshot({
      grossAmountMinor: amountMinor,
      platformFeeMinor,
      providerFeeMinor,
    });
    const customerId = String(saleData.customerId ?? saleData.customerID ?? "");
    const customer = customerId
      ? await tx.get(db.doc(`users/${merchantId}/customers/${customerId}`))
      : null;
    const customerData = customer?.data() ?? {};
    const notice: OrderNotice = {
      orderId,
      sellerId: merchantId,
      customerId,
      buyerName: String(
        customerData.name ?? saleData.customerName ?? "Customer",
      ),
      buyerPhone: String(
        customerData.number ??
          customerData.phone ??
          saleData.customerPhone ??
          "",
      ),
      status: "paid",
      paymentMethod: "paystack",
      amountDueMinor: amountMinor,
      orderKind: "merchant_stock",
      eventKey: eventRef.id,
    };
    notificationId = commerceNotificationDocumentId(notice);
    shouldFinalize = true;
    tx.update(intentRef, {
      status: "paid",
      previousStatus: String(intentData.status),
      providerAmountMinor: amountMinor,
      providerFeeMinor,
      actualMoney,
      appliedProviderEventIds: FieldValue.arrayUnion(eventRef.id),
      paidAt: now,
      updatedAt: now,
    });
    tx.update(reservationRef, {
      status: "committed",
      committedAt: now,
      updatedAt: now,
    });
    tx.set(
      saleRef,
      {
        status: "paid",
        paymentStatus: "paid",
        paymentMethod: "Online",
        paymentProvider: "paystack",
        paymentReference: reference,
        paymentIntentId: intentId,
        paymentSource: "paystack_v2",
        channelUsed: channel,
        paidAt: now,
        updatedAt: now,
      },
      { merge: true },
    );
    tx.create(settlementRef, {
      settlementId,
      intentId,
      merchantId,
      orderId,
      provider: "paystack",
      purpose: "merchant_order",
      providerMode: String(intentData.providerMode ?? "disabled"),
      testOnly: String(intentData.providerMode ?? "") === "test",
      activationScope: String(intentData.activationScope ?? "global"),
      providerReference: reference,
      subaccountCode: String(intentData.paystackSubaccountCode ?? ""),
      destination: intentData.settlementDestination ?? {},
      grossAmountMinor: amountMinor,
      platformFeeMinor,
      providerFeeMinor,
      merchantNetProceedsMinor: actualMoney.merchantNetProceedsMinor,
      status: "pending",
      currency: "ZAR",
      schemaVersion: 2,
      createdAt: now,
      updatedAt: now,
    });
    tx.update(eventRef, {
      processingState: "applied",
      attemptCount: FieldValue.increment(1),
      processedAt: now,
      updatedAt: now,
    });
    enqueueCommerceOrderNotification(tx, notice);
  });
  if (shouldFinalize) {
    await finalizeInventoryOnce(merchantId, orderId, finalizedCustomerId);
  }
  if (notificationId) {
    await deliverCommerceOrderNotificationOutbox(notificationId).catch(
      (error) => {
        console.error("[payments-v2] owned order notification queued", {
          notificationId,
          code: error instanceof Error ? error.message : "unknown",
        });
      },
    );
  }
  return {
    deduped,
    intentId,
    ...(notificationId ? { notificationId } : {}),
  };
}
