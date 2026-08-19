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
  deliverCommerceOrderNotificationOutbox,
  enqueueCommerceOrderNotification,
} from "../../commerce/notifications";
import {
  authenticateFirebaseRequest,
  verifyBotRequest,
} from "../../security/requestAuth";
import { merchantBotFeatureDecision } from "../../ecommerce/merchantBotFeatureAccess";
import { assertStoreAccess, requireStoreId } from "../../stores/storeAccess";
import { normalizePhoneNumber } from "../../utils/phoneUtils";
import {
  buildMoneySnapshot,
  calculatePlatformFeeMinor,
  PaymentPurpose,
  requirePositiveMinorUnits,
  stableDocumentId,
} from "./domain";
import {
  createPaymentIntentV2,
  providerEventDocumentId,
  recordProviderEventV2,
} from "./financialCore";
import { estimatedOwnedOrderProviderFeeMinor } from "./ownedOrders";
import { paymentReadiness } from "./readiness";
import { executePaystackRefundV2 } from "./refunds";

const ACCOUNT_CHANNELS = ["card", "eft", "capitec_pay", "qr"] as const;
type AccountChannel = (typeof ACCOUNT_CHANNELS)[number];

function id(value: unknown, field: string): string {
  const result = String(value ?? "").trim();
  if (!/^[A-Za-z0-9_-]{1,200}$/.test(result)) {
    throw new Error(`${field}_INVALID`);
  }
  return result;
}

function accountChannel(value: unknown): AccountChannel {
  const result = String(value ?? "eft").trim() as AccountChannel;
  if (!ACCOUNT_CHANNELS.includes(result)) {
    throw new Error("ACCOUNT_CHANNEL_INVALID");
  }
  return result;
}

function paymentReference(intentId: string): string {
  return `p2-acct-${createHash("sha256")
    .update(intentId)
    .digest("hex")
    .slice(0, 31)}`;
}

export function accountOutstandingMinor(balanceValue: unknown): number {
  const balance = Number(balanceValue ?? 0);
  const minor = Math.round(Math.max(0, -balance) * 100);
  if (!Number.isFinite(balance) || !Number.isSafeInteger(minor)) {
    throw new Error("CUSTOMER_BALANCE_INVALID");
  }
  return minor;
}

export function nextRepaymentInstallmentMinor(input: {
  remainingAmountMinor: number;
  installmentAmountMinor: number;
}): number {
  const remaining = requirePositiveMinorUnits(
    input.remainingAmountMinor,
    "plan_remaining",
  );
  const installment = requirePositiveMinorUnits(
    input.installmentAmountMinor,
    "installment_amount",
  );
  return Math.min(remaining, installment);
}

export function shouldReopenPaymentRequestAfterExpiry(input: {
  requestStatus: unknown;
  lastPaymentIntentId: unknown;
  expiredIntentId: string;
}): boolean {
  return (
    ["sent", "customer_engaged", "link_created"].includes(
      String(input.requestStatus ?? ""),
    ) && String(input.lastPaymentIntentId ?? "") === input.expiredIntentId
  );
}

async function authorizeMerchantOrBot(
  req: functions.https.Request,
  res: functions.Response,
  merchantId: string,
): Promise<string | null> {
  if (verifyBotRequest(req)) return "botpress";
  const uid = await authenticateFirebaseRequest(req, res, {
    requireAppCheck: true,
  });
  if (!uid) return null;
  await assertStoreAccess(uid, merchantId);
  return uid;
}

function publicError(error: unknown): { status: number; message: string } {
  if (error instanceof functions.https.HttpsError) {
    return {
      status: error.code === "permission-denied" ? 403 : 400,
      message: error.message,
    };
  }
  const code = error instanceof Error ? error.message : "";
  const known: Record<string, [number, string]> = {
    PAYMENT_CAPABILITY_DISABLED: [
      409,
      "Online account payments are not enabled for this shop yet.",
    ],
    CUSTOMER_NOT_FOUND: [404, "Customer account not found."],
    CUSTOMER_BINDING_MISMATCH: [
      403,
      "This WhatsApp chat is not linked to that customer account.",
    ],
    CUSTOMER_ACCOUNT_SETTLED: [409, "This account is already settled."],
    ACCOUNT_PAYMENT_EXCEEDS_BALANCE: [
      409,
      "The payment cannot exceed the current outstanding balance.",
    ],
    MERCHANT_SETTLEMENT_NOT_APPROVED: [
      409,
      "The shop's settlement account is not ready.",
    ],
    ACCOUNT_CHANNEL_INVALID: [400, "Choose an available payment method."],
    PAYMENT_REQUEST_NOT_FOUND: [404, "Payment request not found."],
    PAYMENT_REQUEST_BINDING_MISMATCH: [
      403,
      "This payment request is not linked to that customer account.",
    ],
    REPAYMENT_PLAN_AMOUNT_INVALID: [
      400,
      "Check the plan total and installment amount.",
    ],
    REPAYMENT_CADENCE_INVALID: [400, "Choose a repayment frequency."],
    REPAYMENT_START_INVALID: [400, "Choose a future first payment date."],
    REPAYMENT_PLAN_ALREADY_ACTIVE: [
      409,
      "This customer already has an active repayment plan.",
    ],
    REPAYMENT_PLAN_IDEMPOTENCY_MISMATCH: [
      409,
      "That repayment plan request has changed. Start again.",
    ],
  };
  const mapped = known[code];
  return mapped
    ? { status: mapped[0], message: mapped[1] }
    : { status: 500, message: "The payment link could not be prepared." };
}

export const createAccountSettlementLinkV2 = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN", "PAYSTACK_SECRET_KEY"] })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const merchantId = requireStoreId(
        req.body?.merchantId ?? req.body?.storeId,
      );
      const initiatedBy = await authorizeMerchantOrBot(req, res, merchantId);
      if (!initiatedBy) return;
      if (
        initiatedBy === "botpress" &&
        !(await merchantBotFeatureDecision(merchantId, "accountPayments"))
          .enabled
      ) {
        res.status(409).json({
          error:
            "This shop needs to update Spaza One before account payments can be used.",
          code: "MERCHANT_APP_UPDATE_REQUIRED",
        });
        return;
      }
      const customerId = id(req.body?.customerId, "CUSTOMER_ID");
      const paymentRequestValue = String(
        req.body?.paymentRequestId ?? "",
      ).trim();
      const paymentRequestId = paymentRequestValue
        ? id(paymentRequestValue, "PAYMENT_REQUEST_ID")
        : "";
      const planIdValue = String(req.body?.repaymentPlanId ?? "").trim();
      const planId = planIdValue ? id(planIdValue, "REPAYMENT_PLAN_ID") : "";
      const purpose: PaymentPurpose = planId
        ? "repayment_installment"
        : "account_settlement";
      const readiness = await paymentReadiness({ merchantId, purpose });
      if (!readiness.enabled) throw new Error("PAYMENT_CAPABILITY_DISABLED");
      const providerMode = paystackPaymentProviderMode({
        merchantId,
        purpose,
      });
      const activationScope = paystackPaymentActivationScope({
        merchantId,
        purpose,
      });
      const channel = accountChannel(req.body?.channel);
      if (!(readiness.channels ?? []).includes(channel)) {
        throw new Error("ACCOUNT_CHANNEL_INVALID");
      }
      const customerRef = db.doc(`users/${merchantId}/customers/${customerId}`);
      const profileRef = db.doc(`merchantPaymentProfiles/${merchantId}`);
      const paymentRequestRef = paymentRequestId
        ? db.doc(`customerPaymentRequests/${paymentRequestId}`)
        : null;
      const [customer, profile, plan, paymentRequest] = await Promise.all([
        customerRef.get(),
        profileRef.get(),
        planId
          ? db.doc(`repaymentPlans/${planId}`).get()
          : Promise.resolve(null),
        paymentRequestRef ? paymentRequestRef.get() : Promise.resolve(null),
      ]);
      if (!customer.exists) throw new Error("CUSTOMER_NOT_FOUND");
      const customerData = customer.data() ?? {};
      if (initiatedBy === "botpress") {
        const claimedPhone = normalizePhoneNumber(
          String(req.body?.customerPhone ?? "").replace("whatsapp:", ""),
        );
        const storedPhone = normalizePhoneNumber(
          String(customerData.number ?? ""),
        );
        if (!claimedPhone || !storedPhone || claimedPhone !== storedPhone) {
          throw new Error("CUSTOMER_BINDING_MISMATCH");
        }
      }
      if (paymentRequestRef) {
        if (
          !paymentRequest?.exists ||
          paymentRequest.get("merchantId") !== merchantId ||
          paymentRequest.get("customerId") !== customerId ||
          ![
            "sent",
            "customer_engaged",
            "link_created",
            "partially_paid",
          ].includes(String(paymentRequest.get("status") ?? ""))
        ) {
          throw new Error("PAYMENT_REQUEST_BINDING_MISMATCH");
        }
        if (initiatedBy === "botpress") {
          const requestPhone = normalizePhoneNumber(
            String(paymentRequest.get("deliveryPhone") ?? ""),
          );
          const claimedPhone = normalizePhoneNumber(
            String(req.body?.customerPhone ?? "").replace("whatsapp:", ""),
          );
          if (!requestPhone || requestPhone !== claimedPhone) {
            throw new Error("PAYMENT_REQUEST_BINDING_MISMATCH");
          }
        }
      }
      const outstanding = accountOutstandingMinor(customerData.balance);
      if (outstanding <= 0) throw new Error("CUSTOMER_ACCOUNT_SETTLED");
      const requested =
        req.body?.amountMinor == null
          ? outstanding
          : requirePositiveMinorUnits(req.body.amountMinor, "amount");
      if (requested > outstanding) {
        throw new Error("ACCOUNT_PAYMENT_EXCEEDS_BALANCE");
      }
      if (planId) {
        if (
          !plan?.exists ||
          plan.get("merchantId") !== merchantId ||
          plan.get("customerId") !== customerId ||
          plan.get("status") !== "active"
        ) {
          throw new Error("REPAYMENT_PLAN_NOT_ACTIVE");
        }
        const remaining = requirePositiveMinorUnits(
          plan.get("remainingAmountMinor"),
          "plan_remaining",
        );
        const scheduled = requirePositiveMinorUnits(
          plan.get("installmentAmountMinor"),
          "installment_amount",
        );
        if (
          requested !==
          nextRepaymentInstallmentMinor({
            remainingAmountMinor: remaining,
            installmentAmountMinor: scheduled,
          })
        ) {
          throw new Error("REPAYMENT_INSTALLMENT_AMOUNT_CHANGED");
        }
      }
      const profileData = profile.data() ?? {};
      const subaccountCode = String(profileData.paystackSubaccountCode ?? "");
      if (
        profileData.bankVerificationStatus !== "approved" ||
        !/^ACCT_[A-Za-z0-9]+$/.test(subaccountCode)
      ) {
        throw new Error("MERCHANT_SETTLEMENT_NOT_APPROVED");
      }
      const platformFeeMinor = calculatePlatformFeeMinor({
        grossAmountMinor: requested,
      });
      const providerFeeMinor = estimatedOwnedOrderProviderFeeMinor({
        amountMinor: requested,
        channel,
      });
      const money = buildMoneySnapshot({
        grossAmountMinor: requested,
        platformFeeMinor,
        providerFeeMinor,
      });
      const idempotencyKey = id(req.body?.idempotencyKey, "IDEMPOTENCY_KEY");
      const created = await createPaymentIntentV2({
        merchantId,
        purpose,
        idempotencyKey,
        expectedAmountMinor: requested,
        businessBinding: {
          type: planId ? "repayment_installment" : "customer_account",
          id: planId || customerId,
        },
        money,
        initiatedBy,
        expiresAt: Timestamp.fromMillis(Date.now() + 30 * 60 * 1000),
      });
      const intentRef = db.doc(`paymentIntents/${created.intentId}`);
      const reference = paymentReference(created.intentId);
      const claimId = stableDocumentId("claim", [
        created.intentId,
        String(Date.now()),
      ]);
      const existing = await db.runTransaction(async (tx) => {
        const intent = await tx.get(intentRef);
        const data = intent.data() ?? {};
        if (data.status === "initialized") {
          return {
            authorizationUrl: String(data.authorizationUrl ?? ""),
            providerReference: String(data.providerReference ?? ""),
          };
        }
        if (
          data.initializationState === "processing" &&
          Number(data.initializationLeaseUntilMs ?? 0) > Date.now()
        ) {
          throw new Error("PAYMENT_INITIALIZATION_IN_PROGRESS");
        }
        tx.update(intentRef, {
          customerId,
          repaymentPlanId: planId || null,
          paymentRequestId: paymentRequestId || null,
          selectedChannel: channel,
          paystackSubaccountCode: subaccountCode,
          settlementDestination: {
            bankName: String(profileData.bankName ?? ""),
            accountName: String(profileData.resolvedAccountName ?? ""),
            accountLast4: String(profileData.accountLast4 ?? ""),
          },
          providerMode,
          activationScope,
          initializationState: "processing",
          initializationClaimId: claimId,
          initializationLeaseUntilMs: Date.now() + 45_000,
          initializationAttempts: FieldValue.increment(1),
          updatedAt: FieldValue.serverTimestamp(),
        });
        return { authorizationUrl: "", providerReference: "" };
      });
      if (existing.authorizationUrl && existing.providerReference) {
        res.status(200).json({
          authorizationUrl: existing.authorizationUrl,
          reference: existing.providerReference,
          intentId: created.intentId,
          amountMinor: requested,
          outstandingAmountMinor: outstanding,
          deduped: true,
        });
        return;
      }
      try {
        const email = String(req.body?.email ?? customerData.email ?? "")
          .trim()
          .toLowerCase();
        if (!/^\S+@\S+\.\S+$/.test(email))
          throw new Error("BUYER_EMAIL_INVALID");
        const callbackUrl = String(req.body?.callbackUrl ?? "").trim();
        const response = await axios.post(
          "https://api.paystack.co/transaction/initialize",
          {
            email,
            amount: requested,
            currency: "ZAR",
            channels: [channel],
            reference,
            ...(callbackUrl ? { callback_url: callbackUrl } : {}),
            subaccount: subaccountCode,
            transaction_charge: platformFeeMinor,
            bearer: "subaccount",
            metadata: {
              schemaVersion: 2,
              purpose,
              intentId: created.intentId,
              merchantId,
              customerId,
              repaymentPlanId: planId || null,
              paymentRequestId: paymentRequestId || null,
              selectedChannel: channel,
            },
          },
          {
            headers: {
              Authorization: `Bearer ${paystackPaymentSecret({
                merchantId,
                purpose,
              })}`,
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
          const [intent, request] = await Promise.all([
            tx.get(intentRef),
            paymentRequestRef
              ? tx.get(paymentRequestRef)
              : Promise.resolve(null),
          ]);
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
          const now = FieldValue.serverTimestamp();
          tx.update(intentRef, {
            status: "initialized",
            previousStatus: "created",
            provider: "paystack",
            providerReference: reference,
            authorizationUrl,
            initializationState: "completed",
            initializationLeaseUntilMs: 0,
            initializedAt: now,
            updatedAt: now,
          });
          if (paymentRequestRef && request?.exists) {
            tx.update(paymentRequestRef, {
              status: "link_created",
              linkedPaymentIntentIds: FieldValue.arrayUnion(created.intentId),
              lastPaymentIntentId: created.intentId,
              linkCreatedAt: now,
              updatedAt: now,
            });
          }
        });
        res.status(200).json({
          authorizationUrl,
          reference,
          intentId: created.intentId,
          amountMinor: requested,
          outstandingAmountMinor: outstanding,
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
      console.error("[payments-v2] account link initialization failed", {
        code: error instanceof Error ? error.message : "unknown",
      });
      const response = publicError(error);
      res.status(response.status).json({ error: response.message });
    }
  });

export async function applyVerifiedAccountSettlementV2(
  transaction: Record<string, any>,
  rawBody: Buffer,
): Promise<{ deduped: boolean; intentId: string; transactionId?: string }> {
  const metadata = transaction.metadata ?? {};
  const purpose = String(metadata.purpose ?? "") as PaymentPurpose;
  if (!["account_settlement", "repayment_installment"].includes(purpose)) {
    throw new Error("ACCOUNT_PAYMENT_PURPOSE_MISMATCH");
  }
  const intentId = id(metadata.intentId, "INTENT_ID");
  const merchantId = requireStoreId(metadata.merchantId);
  const customerId = id(metadata.customerId, "CUSTOMER_ID");
  const paymentRequestIdValue = String(metadata.paymentRequestId ?? "").trim();
  const paymentRequestId = paymentRequestIdValue
    ? id(paymentRequestIdValue, "PAYMENT_REQUEST_ID")
    : "";
  const reference = id(transaction.reference, "REFERENCE");
  const amountMinor = requirePositiveMinorUnits(transaction.amount, "amount");
  const providerFeeMinor = Number(transaction.fees ?? 0);
  if (!Number.isSafeInteger(providerFeeMinor) || providerFeeMinor < 0) {
    throw new Error("PROVIDER_FEE_INVALID");
  }
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
  const customerRef = db.doc(`users/${merchantId}/customers/${customerId}`);
  const ledgerRef = customerRef
    .collection("transactions")
    .doc(`paystack_${intentId}`);
  const settlementRef = db.doc(
    `settlements/${stableDocumentId("st", [intentId])}`,
  );
  const paymentRequestRef = paymentRequestId
    ? db.doc(`customerPaymentRequests/${paymentRequestId}`)
    : null;
  let deduped = recorded.deduped;
  let notificationId = "";
  let refundCaseId = "";
  await db.runTransaction(async (tx) => {
    const [intent, event, customer, ledger, settlement, paymentRequest] =
      await Promise.all([
        tx.get(intentRef),
        tx.get(eventRef),
        tx.get(customerRef),
        tx.get(ledgerRef),
        tx.get(settlementRef),
        paymentRequestRef ? tx.get(paymentRequestRef) : Promise.resolve(null),
      ]);
    if (!intent.exists || !event.exists || !customer.exists) {
      throw new Error("ACCOUNT_PAYMENT_CORE_MISSING");
    }
    const intentData = intent.data() ?? {};
    if (
      intentData.purpose !== purpose ||
      intentData.merchantId !== merchantId ||
      intentData.customerId !== customerId ||
      intentData.providerReference !== reference ||
      Number(intentData.expectedAmountMinor) !== amountMinor ||
      String(intentData.selectedChannel ?? "") !==
        String(transaction.channel ?? "") ||
      String(metadata.repaymentPlanId ?? "") !==
        String(intentData.repaymentPlanId ?? "") ||
      paymentRequestId !== String(intentData.paymentRequestId ?? "")
    ) {
      throw new Error("ACCOUNT_PAYMENT_BINDING_MISMATCH");
    }
    if (
      paymentRequestRef &&
      (!paymentRequest?.exists ||
        paymentRequest.get("merchantId") !== merchantId ||
        paymentRequest.get("customerId") !== customerId)
    ) {
      throw new Error("PAYMENT_REQUEST_BINDING_MISMATCH");
    }
    const applied = Array.isArray(intentData.appliedProviderEventIds)
      ? intentData.appliedProviderEventIds.map(String)
      : [];
    if (applied.includes(eventRef.id)) {
      deduped = true;
      return;
    }
    if (ledger.exists || settlement.exists) {
      throw new Error("ACCOUNT_PAYMENT_IDEMPOTENCY_COLLISION");
    }
    const currentOutstanding = accountOutstandingMinor(
      (customer.data() ?? {}).balance,
    );
    const now = FieldValue.serverTimestamp();
    if (amountMinor > currentOutstanding || currentOutstanding <= 0) {
      refundCaseId = stableDocumentId("rf", [intentId, "account_overpayment"]);
      tx.create(db.doc(`refundCases/${refundCaseId}`), {
        refundCaseId,
        intentId,
        refundAmountMinor: amountMinor,
        currency: "ZAR",
        status: "requested",
        provider: "paystack",
        providerConfirmed: false,
        providerReference: reference,
        reason: "account_balance_changed_before_payment_confirmation",
        owner: "operations",
        attemptCount: 0,
        schemaVersion: 2,
        createdAt: now,
        updatedAt: now,
      });
      tx.update(intentRef, {
        status: "refund_pending",
        requestedRefundMinor: amountMinor,
        providerAmountMinor: amountMinor,
        providerFeeMinor,
        appliedProviderEventIds: FieldValue.arrayUnion(eventRef.id),
        updatedAt: now,
      });
      tx.update(eventRef, {
        processingState: "applied_refund_pending",
        attemptCount: FieldValue.increment(1),
        processedAt: now,
        updatedAt: now,
      });
      if (paymentRequestRef && paymentRequest?.exists) {
        tx.update(paymentRequestRef, {
          status: "needs_review",
          reviewReason: "account_balance_changed_before_payment_confirmation",
          operationsOwner: "operations",
          lastPaymentIntentId: intentId,
          updatedAt: now,
        });
      }
      return;
    }
    const repaymentPlanId = String(intentData.repaymentPlanId ?? "");
    const planRef = repaymentPlanId
      ? db.doc(`repaymentPlans/${id(repaymentPlanId, "PLAN_ID")}`)
      : null;
    const plan = planRef ? await tx.get(planRef) : null;
    if (planRef && (!plan?.exists || plan.get("status") !== "active")) {
      throw new Error("REPAYMENT_PLAN_NOT_ACTIVE");
    }
    const platformFeeMinor = Number(intentData.money?.platformFeeMinor ?? 0);
    const money = buildMoneySnapshot({
      grossAmountMinor: amountMinor,
      platformFeeMinor,
      providerFeeMinor,
    });
    const customerData = customer.data() ?? {};
    const providerMode = String(
      intentData.providerMode ??
        paystackPaymentProviderMode({ merchantId, purpose }),
    );
    if (!(["test", "live"] as string[]).includes(providerMode)) {
      throw new Error("PAYSTACK_PROVIDER_DISABLED");
    }
    let planRemainingAfter: number | null = null;
    let nextPlanDueAt: Timestamp | null = null;
    if (planRef && plan) {
      const remainingBefore = requirePositiveMinorUnits(
        plan.get("remainingAmountMinor"),
        "plan_remaining",
      );
      if (amountMinor > remainingBefore) {
        throw new Error("REPAYMENT_INSTALLMENT_EXCEEDS_REMAINING");
      }
      planRemainingAfter = remainingBefore - amountMinor;
      if (planRemainingAfter > 0) {
        const cadenceDays = Number(plan.get("cadenceDays"));
        const currentDueAt = plan.get("nextDueAt") as Timestamp | undefined;
        if (
          !Number.isSafeInteger(cadenceDays) ||
          cadenceDays < 1 ||
          cadenceDays > 366 ||
          !currentDueAt
        ) {
          throw new Error("REPAYMENT_PLAN_SCHEDULE_INVALID");
        }
        nextPlanDueAt = Timestamp.fromMillis(
          Math.max(currentDueAt.toMillis(), Date.now()) +
            cadenceDays * 24 * 60 * 60 * 1000,
        );
      }
    }
    const transactionData = {
      type: "Payment",
      amount: amountMinor / 100,
      amountMinor,
      date: now,
      status: "PAID",
      remarks: "Online account payment",
      source: "paystack_v2",
      paymentIntentId: intentId,
      paymentReference: reference,
      provider: "paystack",
      providerMode,
      testOnly: providerMode === "test",
      providerReference: reference,
      schemaVersion: 2,
    };
    tx.create(ledgerRef, transactionData);
    tx.set(
      customerRef,
      {
        lastTransaction: transactionData,
        updatedAt: now,
        ...(planRemainingAfter === 0 &&
        String(customerData.activeRepaymentPlanId ?? "") === repaymentPlanId
          ? { activeRepaymentPlanId: FieldValue.delete() }
          : {}),
      },
      { merge: true },
    );
    tx.create(settlementRef, {
      settlementId: settlementRef.id,
      intentId,
      merchantId,
      customerId,
      provider: "paystack",
      purpose,
      providerMode,
      testOnly: providerMode === "test",
      activationScope: String(intentData.activationScope ?? "global"),
      subaccountCode: String(intentData.paystackSubaccountCode ?? ""),
      destination: intentData.settlementDestination ?? {},
      grossAmountMinor: amountMinor,
      platformFeeMinor,
      providerFeeMinor,
      merchantNetProceedsMinor: money.merchantNetProceedsMinor,
      status: "pending",
      currency: "ZAR",
      schemaVersion: 2,
      createdAt: now,
      updatedAt: now,
    });
    if (planRef && plan) {
      tx.update(planRef, {
        paidAmountMinor: FieldValue.increment(amountMinor),
        remainingAmountMinor: planRemainingAfter,
        completedInstallments: FieldValue.increment(1),
        status: planRemainingAfter === 0 ? "completed" : "active",
        ...(nextPlanDueAt ? { nextDueAt: nextPlanDueAt } : {}),
        lastPaymentIntentId: intentId,
        updatedAt: now,
        ...(planRemainingAfter === 0 ? { completedAt: now } : {}),
      });
    }
    tx.update(intentRef, {
      status: "paid",
      previousStatus: String(intentData.status ?? "initialized"),
      providerAmountMinor: amountMinor,
      providerFeeMinor,
      actualMoney: money,
      appliedProviderEventIds: FieldValue.arrayUnion(eventRef.id),
      paidAt: now,
      updatedAt: now,
    });
    tx.update(eventRef, {
      processingState: "applied",
      attemptCount: FieldValue.increment(1),
      processedAt: now,
      updatedAt: now,
    });
    if (paymentRequestRef && paymentRequest?.exists) {
      tx.update(paymentRequestRef, {
        status: amountMinor === currentOutstanding ? "paid" : "partially_paid",
        lastPaymentIntentId: intentId,
        paidAmountMinor: FieldValue.increment(amountMinor),
        remainingAmountMinor: currentOutstanding - amountMinor,
        paymentConfirmedAt: now,
        updatedAt: now,
      });
    }
    notificationId = enqueueCommerceOrderNotification(tx, {
      orderId: intentId,
      sellerId: merchantId,
      customerId,
      buyerName: String(customerData.name ?? "Customer"),
      buyerPhone: String(customerData.number ?? customerData.phone ?? ""),
      status: "paid",
      paymentMethod: "paystack",
      amountDueMinor: amountMinor,
      orderKind: "merchant_stock",
      noticeKind: "account_payment",
      eventKey: eventRef.id,
    });
  });
  if (refundCaseId) {
    await executePaystackRefundV2(refundCaseId).catch((error) => {
      console.error("[payments-v2] account refund submission queued", {
        refundCaseId,
        code: error instanceof Error ? error.message : "unknown",
      });
    });
  } else if (notificationId) {
    await deliverCommerceOrderNotificationOutbox(notificationId).catch(
      () => undefined,
    );
  }
  return {
    deduped,
    intentId,
    ...(refundCaseId ? {} : { transactionId: ledgerRef.id }),
  };
}

/**
 * Ends the app/bot's internal checkout session without claiming that Paystack
 * can no longer confirm a late charge. Provider truth still wins in the
 * verified webhook path above, which remains idempotent after this marker.
 */
export const expireAccountSettlementIntents = functions.pubsub
  .schedule("every 15 minutes")
  .onRun(async () => {
    const expired = await db
      .collection("paymentIntents")
      .where("expiresAt", "<=", Timestamp.now())
      .limit(100)
      .get();
    for (const intent of expired.docs) {
      const data = intent.data() ?? {};
      if (
        !["account_settlement", "repayment_installment"].includes(
          String(data.purpose ?? ""),
        ) ||
        !["created", "initialized"].includes(String(data.status ?? ""))
      ) {
        continue;
      }
      const paymentRequestId = String(data.paymentRequestId ?? "");
      await db.runTransaction(async (tx) => {
        const liveIntent = await tx.get(intent.ref);
        const liveData = liveIntent.data() ?? {};
        if (
          !liveIntent.exists ||
          !["created", "initialized"].includes(String(liveData.status ?? ""))
        ) {
          return;
        }
        const now = FieldValue.serverTimestamp();
        tx.update(intent.ref, {
          status: "expired",
          previousStatus: String(liveData.status ?? "initialized"),
          expiredAt: now,
          updatedAt: now,
        });
        if (!paymentRequestId) return;
        const requestRef = db.doc(
          `customerPaymentRequests/${paymentRequestId}`,
        );
        const request = await tx.get(requestRef);
        if (
          request.exists &&
          shouldReopenPaymentRequestAfterExpiry({
            requestStatus: request.get("status"),
            lastPaymentIntentId: request.get("lastPaymentIntentId"),
            expiredIntentId: intent.id,
          })
        ) {
          tx.update(requestRef, {
            status: "customer_engaged",
            lastExpiredPaymentIntentId: intent.id,
            updatedAt: now,
          });
        }
      });
    }
    return null;
  });

const CADENCE_DAYS = { weekly: 7, fortnightly: 14, monthly: 30 } as const;

/** Server-only foundation; exposure is independently gated by its capability. */
export const createRepaymentPlanV2 = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const merchantId = requireStoreId(
        req.body?.merchantId ?? req.body?.storeId,
      );
      const initiatedBy = await authorizeMerchantOrBot(req, res, merchantId);
      if (!initiatedBy) return;
      if (
        initiatedBy === "botpress" &&
        !(await merchantBotFeatureDecision(merchantId, "accountPayments"))
          .enabled
      ) {
        res.status(409).json({
          error:
            "This shop needs to update Spaza One before repayment plans can be used.",
          code: "MERCHANT_APP_UPDATE_REQUIRED",
        });
        return;
      }
      const readiness = await paymentReadiness({
        merchantId,
        purpose: "repayment_installment",
      });
      if (!readiness.enabled) throw new Error("PAYMENT_CAPABILITY_DISABLED");
      const customerId = id(req.body?.customerId, "CUSTOMER_ID");
      const customerRef = db.doc(`users/${merchantId}/customers/${customerId}`);
      const customer = await customerRef.get();
      if (!customer.exists) throw new Error("CUSTOMER_NOT_FOUND");
      const outstanding = accountOutstandingMinor(
        (customer.data() ?? {}).balance,
      );
      const totalAmountMinor = requirePositiveMinorUnits(
        req.body?.totalAmountMinor,
        "total_amount",
      );
      const installmentAmountMinor = requirePositiveMinorUnits(
        req.body?.installmentAmountMinor,
        "installment_amount",
      );
      if (
        totalAmountMinor > outstanding ||
        installmentAmountMinor > totalAmountMinor
      ) {
        throw new Error("REPAYMENT_PLAN_AMOUNT_INVALID");
      }
      const cadence = String(
        req.body?.cadence ?? "",
      ) as keyof typeof CADENCE_DAYS;
      if (!CADENCE_DAYS[cadence]) throw new Error("REPAYMENT_CADENCE_INVALID");
      const startAtMs = Number(req.body?.startAtMs);
      if (
        !Number.isSafeInteger(startAtMs) ||
        startAtMs < Date.now() ||
        startAtMs > Date.now() + 366 * 24 * 60 * 60 * 1000
      ) {
        throw new Error("REPAYMENT_START_INVALID");
      }
      const key = id(req.body?.idempotencyKey, "IDEMPOTENCY_KEY");
      const planId = stableDocumentId("rp", [merchantId, customerId, key]);
      const planRef = db.doc(`repaymentPlans/${planId}`);
      let deduped = false;
      await db.runTransaction(async (tx) => {
        const [existing, currentCustomer] = await Promise.all([
          tx.get(planRef),
          tx.get(customerRef),
        ]);
        if (existing.exists) {
          if (
            existing.get("merchantId") !== merchantId ||
            existing.get("customerId") !== customerId ||
            Number(existing.get("totalAmountMinor")) !== totalAmountMinor ||
            Number(existing.get("installmentAmountMinor")) !==
              installmentAmountMinor ||
            String(existing.get("cadence") ?? "") !== cadence ||
            Number(
              (
                existing.get("startAt") as Timestamp | undefined
              )?.toMillis?.() ?? 0,
            ) !== startAtMs
          ) {
            throw new Error("REPAYMENT_PLAN_IDEMPOTENCY_MISMATCH");
          }
          deduped = true;
          tx.set(
            customerRef,
            {
              activeRepaymentPlanId: planId,
              updatedAt: FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
          return;
        }
        const activePlanId = String(
          currentCustomer.get("activeRepaymentPlanId") ?? "",
        ).trim();
        if (activePlanId && activePlanId !== planId) {
          const activePlan = await tx.get(
            db.doc(`repaymentPlans/${id(activePlanId, "PLAN_ID")}`),
          );
          if (
            activePlan.exists &&
            activePlan.get("merchantId") === merchantId &&
            activePlan.get("customerId") === customerId &&
            activePlan.get("status") === "active"
          ) {
            throw new Error("REPAYMENT_PLAN_ALREADY_ACTIVE");
          }
        }
        const now = FieldValue.serverTimestamp();
        tx.create(planRef, {
          planId,
          merchantId,
          customerId,
          totalAmountMinor,
          paidAmountMinor: 0,
          remainingAmountMinor: totalAmountMinor,
          installmentAmountMinor,
          cadence,
          cadenceDays: CADENCE_DAYS[cadence],
          startAt: Timestamp.fromMillis(startAtMs),
          nextDueAt: Timestamp.fromMillis(startAtMs),
          completedInstallments: 0,
          status: "active",
          automaticDebit: false,
          savedCardCharging: false,
          interestMinor: 0,
          penaltyMinor: 0,
          initiatedBy,
          schemaVersion: 2,
          createdAt: now,
          updatedAt: now,
        });
        tx.set(
          customerRef,
          { activeRepaymentPlanId: planId, updatedAt: now },
          { merge: true },
        );
      });
      res.status(200).json({
        planId,
        status: "active",
        totalAmountMinor,
        installmentAmountMinor,
        cadence,
        deduped,
      });
    } catch (error) {
      console.error("[payments-v2] repayment plan creation failed", {
        code: error instanceof Error ? error.message : "unknown",
      });
      const response = publicError(error);
      res.status(response.status).json({ error: response.message });
    }
  });
