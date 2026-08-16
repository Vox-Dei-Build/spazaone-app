import { createHash, createHmac, timingSafeEqual } from "crypto";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import twilio from "twilio/lib/index";
import { db, functions } from "../../config/main";
import { appendTruthSurfaceMessage } from "../../notifications/unreadCounts";
import {
  authenticateFirebaseRequest,
  requireBotRequest,
} from "../../security/requestAuth";
import { DynamicPricingService } from "../../services/dynamic_pricing_service";
import { assertStoreAccess, requireStoreId } from "../../stores/storeAccess";
import { calculateSmsSegments } from "../../utils/customerOrderingCampaignSms";
import {
  fetchWhatsAppCapability,
  storeWhatsAppCapability,
  WhatsAppCapability,
} from "../../utils/whatsappCapability";
import {
  formatPhoneNumber,
  normalizePhoneNumber,
} from "../../utils/phoneUtils";
import {
  campaignWalletContextFromCharge,
  campaignWalletRef,
  mutateCampaignCredits,
  resolveCampaignWallet,
} from "../../wallet/campaignCredits";
import { stableDocumentId } from "./domain";
import { paymentReadiness } from "./readiness";

const REQUEST_ID_PATTERN = /^[A-Za-z0-9:_-]{1,200}$/;
const COOLDOWN_MS = 24 * 60 * 60 * 1000;
const RESERVATION_TTL_MS = 30 * 60 * 1000;
const MAX_ATTEMPTS = 3;

export function paymentRequestCooldownEndsAtMs(acceptedAtMs: number): number {
  if (!Number.isSafeInteger(acceptedAtMs) || acceptedAtMs <= 0) {
    throw new Error("ACCEPTED_AT_INVALID");
  }
  return acceptedAtMs + COOLDOWN_MS;
}

export type CustomerPaymentRequestMode =
  | "whatsapp_online"
  | "whatsapp_reminder"
  | "sms_reminder";

export type CustomerPaymentRequestStatus =
  | "queued"
  | "dispatching"
  | "sent"
  | "customer_engaged"
  | "link_created"
  | "partially_paid"
  | "paid"
  | "not_deliverable"
  | "failed"
  | "needs_review";

type RequestQuote = {
  merchantId: string;
  customerId: string;
  customerName: string;
  shopName: string;
  deliveryPhone: string;
  phoneLast4: string;
  phoneFingerprint: string;
  outstandingAmountMinor: number;
  mode: CustomerPaymentRequestMode;
  expectedChannel: "whatsapp" | "sms";
  messageCostMinor: number;
  whatsappCostMinor: number;
  smsCostMinor: number;
  reservationAmountMinor: number;
  walletBalanceMinor: number;
  onlinePaymentsReady: boolean;
  messagePreview: string;
  smsPreview: string;
  quoteKey: string;
  pricingVersion: string;
  canRequest: boolean;
  reason:
    | "ready"
    | "settled"
    | "phone_missing"
    | "cooldown_active"
    | "wallet_insufficient"
    | "pricing_unavailable"
    | "temporarily_unavailable";
  cooldownEndsAtMs: number;
  lastRequest: Record<string, unknown> | null;
};

function requestId(value: unknown, field: string): string {
  const parsed = String(value ?? "").trim();
  if (!REQUEST_ID_PATTERN.test(parsed)) throw new Error(`${field}_INVALID`);
  return parsed;
}

function providerMessageId(value: unknown): string {
  const parsed = String(value ?? "").trim();
  if (!/^[A-Za-z0-9._:-]{1,200}$/.test(parsed)) {
    throw new Error("PROVIDER_MESSAGE_ID_INVALID");
  }
  return parsed;
}

function cents(value: number): number {
  const rounded = Math.round(value);
  if (!Number.isSafeInteger(rounded) || rounded < 0) {
    throw new Error("MONEY_VALUE_INVALID");
  }
  return rounded;
}

function moneyZar(valueMinor: number): string {
  const fixed = (valueMinor / 100).toFixed(2).replace(".", ",");
  const [whole, decimal] = fixed.split(",");
  return `R${whole?.replace(/\B(?=(\d{3})+(?!\d))/g, " ")},${decimal}`;
}

function phoneHash(phone: string): string {
  return createHash("sha256").update(phone).digest("hex");
}

function stateRef(merchantId: string, customerId: string) {
  return db.doc(
    `customerPaymentRequestState/${stableDocumentId("cprs", [merchantId, customerId])}`,
  );
}

function reservationRef(id: string) {
  return db.doc(
    `paymentRequestWalletReservations/${requestId(id, "REQUEST_ID")}`,
  );
}

function featureEnabled(config: FirebaseFirestore.DocumentData): boolean {
  return (
    String(process.env.CUSTOMER_PAYMENT_REQUESTS_ENABLED ?? "")
      .trim()
      .toLowerCase() === "true" &&
    config.customerPaymentRequestsEnabled === true
  );
}

function providerMode(name: string): string {
  return String(process.env[name] ?? "disabled")
    .trim()
    .toLowerCase();
}

export function twilioPaymentRequestReady(): boolean {
  const mode = providerMode("TWILIO_PROVIDER_MODE");
  if (mode === "stub") return true;
  const config = (functions.config().twilio ?? {}) as Record<string, unknown>;
  return (
    ["test", "live"].includes(mode) &&
    Boolean(
      process.env.TWILIO_ACCOUNT_SID ?? process.env.TWILIO_SID ?? config.sid,
    ) &&
    Boolean(
      process.env.TWILIO_AUTH_TOKEN ?? process.env.TWILIO_TOKEN ?? config.token,
    ) &&
    Boolean(
      process.env.TWILIO_CUSTOMER_MESSAGING_SERVICE_SID ??
        config.customer_messaging_service_sid,
    ) &&
    Boolean(process.env.TWILIO_PAYMENT_REQUEST_CONTENT_SID)
  );
}

function smsReady(): boolean {
  const mode = providerMode("TWILIO_PROVIDER_MODE");
  if (mode === "stub") return true;
  const config = (functions.config().twilio ?? {}) as Record<string, unknown>;
  return (
    ["test", "live"].includes(mode) &&
    Boolean(process.env.TWILIO_ACCOUNT_SID ?? config.sid) &&
    Boolean(process.env.TWILIO_AUTH_TOKEN ?? config.token) &&
    Boolean(process.env.TWILIO_SMS_NUMBER ?? config.number)
  );
}

export function selectCustomerPaymentRequestMode(input: {
  whatsappCapability: WhatsAppCapability;
  onlinePaymentsReady: boolean;
  whatsappTemplateReady: boolean;
  smsReady: boolean;
}): CustomerPaymentRequestMode | null {
  if (input.whatsappCapability !== "sms" && input.whatsappTemplateReady) {
    return input.onlinePaymentsReady ? "whatsapp_online" : "whatsapp_reminder";
  }
  return input.smsReady ? "sms_reminder" : null;
}

function messageText(input: {
  customerName: string;
  shopName: string;
  amountMinor: number;
  online: boolean;
}): string {
  const firstName = input.customerName.trim().split(/\s+/)[0] || "there";
  return input.online
    ? `Hi ${firstName}, your balance at ${input.shopName} is ${moneyZar(input.amountMinor)}. You can pay securely here, or contact the shop if you've already paid.`
    : `Hi ${firstName}, your ${input.shopName} balance is ${moneyZar(input.amountMinor)}. Please pay the shop or contact them if you've already paid. - SpazaOne`;
}

function safeLastRequest(
  value: FirebaseFirestore.DocumentData | undefined,
): Record<string, unknown> | null {
  if (!value) return null;
  const timestampMs = (field: string) => {
    const raw = value[field] as { toMillis?: () => number } | undefined;
    return Number(raw?.toMillis?.() ?? 0);
  };
  return {
    requestId: String(value.requestId ?? ""),
    status: String(value.status ?? "failed"),
    expectedChannel: String(value.expectedChannel ?? "sms"),
    sentAtMs: timestampMs("sentAt"),
    updatedAtMs: timestampMs("updatedAt"),
    cooldownEndsAtMs: timestampMs("cooldownEndsAt"),
  };
}

async function buildQuote(
  merchantId: string,
  customerId: string,
): Promise<RequestQuote> {
  const customerRef = db.doc(`users/${merchantId}/customers/${customerId}`);
  const [merchant, customer, config, profile, state, pricing, readiness] =
    await Promise.all([
      db.doc(`users/${merchantId}`).get(),
      customerRef.get(),
      db.doc("paymentConfiguration/global").get(),
      db.doc(`merchantPaymentProfiles/${merchantId}`).get(),
      stateRef(merchantId, customerId).get(),
      DynamicPricingService.initialize().catch(() => null),
      paymentReadiness({ merchantId, purpose: "account_settlement" }),
    ]);
  if (!merchant.exists) throw new Error("MERCHANT_NOT_FOUND");
  if (!customer.exists) throw new Error("CUSTOMER_NOT_FOUND");
  const customerData = customer.data() ?? {};
  const merchantData = merchant.data() ?? {};
  const normalized = normalizePhoneNumber(
    String(customerData.number ?? customerData.phone ?? ""),
  );
  const deliveryPhone = formatPhoneNumber(normalized);
  const outstandingAmountMinor = cents(
    Math.max(0, -Number(customerData.balance ?? 0)) * 100,
  );
  const profileData = profile.data() ?? {};
  const onlinePaymentsReady =
    readiness.enabled &&
    profileData.bankVerificationStatus === "approved" &&
    /^ACCT_[A-Za-z0-9]+$/.test(
      String(profileData.paystackSubaccountCode ?? ""),
    );
  const capability: WhatsAppCapability = deliveryPhone
    ? await fetchWhatsAppCapability(deliveryPhone)
    : "unknown";
  const canUseWhatsAppTemplate = twilioPaymentRequestReady();
  const canUseSms = smsReady();
  const selectedMode = selectCustomerPaymentRequestMode({
    whatsappCapability: capability,
    onlinePaymentsReady,
    whatsappTemplateReady: canUseWhatsAppTemplate,
    smsReady: canUseSms,
  });
  const mode: CustomerPaymentRequestMode = selectedMode ?? "sms_reminder";
  const shopName = String(
    merchantData.shopName ?? merchantData.name ?? "SpazaOne",
  ).trim();
  const customerName = String(customerData.name ?? "Customer").trim();
  const whatsappText = messageText({
    customerName,
    shopName,
    amountMinor: outstandingAmountMinor,
    online: mode === "whatsapp_online",
  });
  const smsPreview = messageText({
    customerName,
    shopName,
    amountMinor: outstandingAmountMinor,
    online: false,
  });
  const snapshot = pricing?.buyerSafeSnapshot ?? null;
  const smsCostMinor = cents(
    (snapshot?.smsCustomerMinor ?? 0) * calculateSmsSegments(smsPreview),
  );
  const messageCostMinor =
    mode === "sms_reminder"
      ? smsCostMinor
      : (snapshot?.whatsappUtilityMinor ?? 0);
  const reservationAmountMinor =
    mode === "sms_reminder" || !canUseSms
      ? messageCostMinor
      : Math.max(messageCostMinor, smsCostMinor);
  const walletContext = await resolveCampaignWallet(merchantId);
  const wallet = await campaignWalletRef(walletContext.walletStoreId).get();
  const walletBalanceMinor = cents(
    Number(wallet.data()?.virtualBalance ?? 0) * 100,
  );
  const stateData = state.data() ?? {};
  const cooldownEndsAtMs = Number(
    (
      stateData.cooldownEndsAt as { toMillis?: () => number } | undefined
    )?.toMillis?.() ?? 0,
  );
  const lastRequestId = String(stateData.latestRequestId ?? "");
  const lastRequest = lastRequestId
    ? await db.doc(`customerPaymentRequests/${lastRequestId}`).get()
    : null;
  const lastRequestStatus = String(lastRequest?.get("status") ?? "");
  let reason: RequestQuote["reason"] = "ready";
  if (!featureEnabled(config.data() ?? {})) reason = "temporarily_unavailable";
  else if (outstandingAmountMinor <= 0) reason = "settled";
  else if (!deliveryPhone) reason = "phone_missing";
  else if (cooldownEndsAtMs > Date.now()) reason = "cooldown_active";
  else if (
    ["queued", "dispatching", "needs_review"].includes(lastRequestStatus)
  )
    reason = "temporarily_unavailable";
  else if (!snapshot) reason = "pricing_unavailable";
  else if (!selectedMode) reason = "temporarily_unavailable";
  else if (walletBalanceMinor < reservationAmountMinor)
    reason = "wallet_insufficient";
  const quoteKey = createHash("sha256")
    .update(
      [
        merchantId,
        customerId,
        outstandingAmountMinor,
        mode,
        messageCostMinor,
        reservationAmountMinor,
        snapshot?.schemaVersion ?? 0,
        snapshot?.smsCustomerMinor ?? 0,
        snapshot?.whatsappUtilityMinor ?? 0,
        phoneHash(deliveryPhone),
      ].join("\u001f"),
    )
    .digest("hex");
  return {
    merchantId,
    customerId,
    customerName,
    shopName,
    deliveryPhone,
    phoneLast4: normalized.slice(-4),
    phoneFingerprint: phoneHash(deliveryPhone),
    outstandingAmountMinor,
    mode,
    expectedChannel: mode === "sms_reminder" ? "sms" : "whatsapp",
    messageCostMinor,
    whatsappCostMinor: snapshot?.whatsappUtilityMinor ?? 0,
    smsCostMinor,
    reservationAmountMinor,
    walletBalanceMinor,
    onlinePaymentsReady,
    messagePreview: mode === "sms_reminder" ? smsPreview : whatsappText,
    smsPreview,
    quoteKey,
    pricingVersion: createHash("sha256")
      .update(
        [
          snapshot?.schemaVersion ?? 0,
          snapshot?.smsCustomerMinor ?? 0,
          snapshot?.whatsappUtilityMinor ?? 0,
        ].join(":"),
      )
      .digest("hex"),
    canRequest: reason === "ready",
    reason,
    cooldownEndsAtMs,
    lastRequest: safeLastRequest(lastRequest?.data()),
  };
}

function publicQuote(quote: RequestQuote) {
  return {
    schemaVersion: 1,
    merchantId: quote.merchantId,
    customerId: quote.customerId,
    outstandingAmountMinor: quote.outstandingAmountMinor,
    mode: quote.mode,
    expectedChannel: quote.expectedChannel,
    messageCostMinor: quote.messageCostMinor,
    fallbackMessageCostMinor:
      quote.expectedChannel === "whatsapp" && quote.smsCostMinor > 0
        ? quote.smsCostMinor
        : null,
    walletBalanceMinor: quote.walletBalanceMinor,
    walletBalanceAfterMinor: quote.walletBalanceMinor - quote.messageCostMinor,
    onlinePaymentsReady: quote.onlinePaymentsReady,
    messagePreview: quote.messagePreview,
    quoteKey: quote.quoteKey,
    pricingVersion: quote.pricingVersion,
    canRequest: quote.canRequest,
    reason: quote.reason,
    cooldownEndsAtMs: quote.cooldownEndsAtMs,
    lastRequest: quote.lastRequest,
  };
}

function publicError(error: unknown): { status: number; message: string } {
  const code = error instanceof Error ? error.message : "";
  const known: Record<string, [number, string]> = {
    MERCHANT_NOT_FOUND: [404, "Shop not found."],
    CUSTOMER_NOT_FOUND: [404, "Customer not found."],
    CUSTOMER_ACCOUNT_SETTLED: [409, "This account is already settled."],
    PHONE_MISSING: [409, "Add a valid customer phone number first."],
    COOLDOWN_ACTIVE: [409, "A payment request was sent in the last 24 hours."],
    INSUFFICIENT_CAMPAIGN_CREDITS: [
      409,
      "Add money to your SpazaOne balance before sending this request.",
    ],
    QUOTE_CHANGED: [
      409,
      "Payment request details changed. Please review them again.",
    ],
    REQUEST_TEMPORARILY_UNAVAILABLE: [
      503,
      "Payment requests are temporarily unavailable.",
    ],
    REQUEST_NOT_FOUND: [404, "Payment request not found."],
    REQUEST_BINDING_MISMATCH: [403, "Payment request access denied."],
    REQUEST_IN_PROGRESS: [
      409,
      "A payment request is already being sent for this customer.",
    ],
  };
  const mapped = known[code];
  if (mapped) return { status: mapped[0], message: mapped[1] };
  if (error instanceof functions.https.HttpsError) {
    return {
      status: error.code === "permission-denied" ? 403 : 400,
      message: error.message,
    };
  }
  return {
    status: 500,
    message: "Payment requests are temporarily unavailable.",
  };
}

async function authenticateMerchant(
  req: functions.https.Request,
  res: functions.Response,
  merchantId: string,
): Promise<string | null> {
  const uid = await authenticateFirebaseRequest(req, res, {
    requireAppCheck: true,
  });
  if (!uid) return null;
  await assertStoreAccess(uid, merchantId);
  return uid;
}

export const getCustomerPaymentRequestOverviewV1 = functions.https.onRequest(
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const merchantId = requireStoreId(
        req.body?.merchantId ?? req.body?.storeId,
      );
      if (!(await authenticateMerchant(req, res, merchantId))) return;
      const customerId = requestId(req.body?.customerId, "CUSTOMER_ID");
      res
        .status(200)
        .json(publicQuote(await buildQuote(merchantId, customerId)));
    } catch (error) {
      const response = publicError(error);
      res.status(response.status).json({ error: response.message });
    }
  },
);

export async function reserveCustomerPaymentRequest(args: {
  quote: RequestQuote;
  idempotencyKey: string;
  initiatedBy: string;
}): Promise<{ requestId: string; deduped: boolean }> {
  const key = requestId(args.idempotencyKey, "IDEMPOTENCY_KEY");
  const id = stableDocumentId("cpr", [
    args.quote.merchantId,
    args.quote.customerId,
    key,
  ]);
  const ref = db.doc(`customerPaymentRequests/${id}`);
  const customerRef = db.doc(
    `users/${args.quote.merchantId}/customers/${args.quote.customerId}`,
  );
  const requestStateRef = stateRef(
    args.quote.merchantId,
    args.quote.customerId,
  );
  const walletContext = await resolveCampaignWallet(args.quote.merchantId);
  let deduped = false;
  await db.runTransaction(async (tx) => {
    const [existing, customer, state] = await Promise.all([
      tx.get(ref),
      tx.get(customerRef),
      tx.get(requestStateRef),
    ]);
    if (existing.exists) {
      if (
        existing.get("merchantId") !== args.quote.merchantId ||
        existing.get("customerId") !== args.quote.customerId ||
        existing.get("quoteKey") !== args.quote.quoteKey
      ) {
        throw new Error("QUOTE_CHANGED");
      }
      deduped = true;
      return;
    }
    const activeRequestId = String(state.get("activeRequestId") ?? "");
    if (activeRequestId && activeRequestId !== id) {
      const activeRequest = await tx.get(
        db.doc(
          `customerPaymentRequests/${requestId(activeRequestId, "ACTIVE_REQUEST_ID")}`,
        ),
      );
      if (
        activeRequest.exists &&
        ["queued", "dispatching", "needs_review"].includes(
          String(activeRequest.get("status") ?? ""),
        )
      ) {
        throw new Error("REQUEST_IN_PROGRESS");
      }
    }
    if (!customer.exists) throw new Error("CUSTOMER_NOT_FOUND");
    const liveOutstanding = cents(
      Math.max(0, -Number(customer.get("balance") ?? 0)) * 100,
    );
    const livePhone = formatPhoneNumber(
      normalizePhoneNumber(String(customer.get("number") ?? "")),
    );
    if (
      liveOutstanding !== args.quote.outstandingAmountMinor ||
      phoneHash(livePhone) !== args.quote.phoneFingerprint
    ) {
      throw new Error("QUOTE_CHANGED");
    }
    if (liveOutstanding <= 0) throw new Error("CUSTOMER_ACCOUNT_SETTLED");
    if (!livePhone) throw new Error("PHONE_MISSING");
    const cooldownEndsAt = state.get("cooldownEndsAt") as
      | { toMillis?: () => number }
      | undefined;
    if (Number(cooldownEndsAt?.toMillis?.() ?? 0) > Date.now()) {
      throw new Error("COOLDOWN_ACTIVE");
    }
    await mutateCampaignCredits(
      tx,
      walletContext,
      -(args.quote.reservationAmountMinor / 100),
      {
        id: `request-reserve:${id}`,
        kind: "payment-request-reservation",
        initiatedBy: args.initiatedBy,
        metadata: {
          requestId: id,
          customerId: args.quote.customerId,
          reservedMinor: args.quote.reservationAmountMinor,
        },
      },
    );
    const now = FieldValue.serverTimestamp();
    tx.create(reservationRef(id), {
      reservationId: id,
      requestId: id,
      storeId: walletContext.storeId,
      walletStoreId: walletContext.walletStoreId,
      shared: walletContext.shared,
      reservedMinor: args.quote.reservationAmountMinor,
      spentMinor: 0,
      status: "active",
      expiresAt: Timestamp.fromMillis(Date.now() + RESERVATION_TTL_MS),
      createdAt: now,
      updatedAt: now,
    });
    tx.create(ref, {
      schemaVersion: 1,
      requestId: id,
      merchantId: args.quote.merchantId,
      customerId: args.quote.customerId,
      customerName: args.quote.customerName,
      shopName: args.quote.shopName,
      deliveryPhone: args.quote.deliveryPhone,
      phoneLast4: args.quote.phoneLast4,
      phoneFingerprint: args.quote.phoneFingerprint,
      outstandingSnapshotMinor: args.quote.outstandingAmountMinor,
      mode: args.quote.mode,
      expectedChannel: args.quote.expectedChannel,
      onlinePaymentsReady: args.quote.onlinePaymentsReady,
      messagePreview: args.quote.messagePreview,
      smsPreview: args.quote.smsPreview,
      quotedMessageCostMinor: args.quote.messageCostMinor,
      whatsappCostMinor: args.quote.whatsappCostMinor,
      smsCostMinor: args.quote.smsCostMinor,
      reservedMessageCostMinor: args.quote.reservationAmountMinor,
      actualMessageCostMinor: 0,
      quoteKey: args.quote.quoteKey,
      pricingVersion: args.quote.pricingVersion,
      idempotencyKey: key,
      status: "queued" satisfies CustomerPaymentRequestStatus,
      deliveryAttemptCount: 0,
      linkedPaymentIntentIds: [],
      initiatedBy: args.initiatedBy,
      operationsOwner: null,
      createdAt: now,
      updatedAt: now,
    });
    tx.set(
      requestStateRef,
      {
        merchantId: args.quote.merchantId,
        customerId: args.quote.customerId,
        latestRequestId: id,
        activeRequestId: id,
        updatedAt: now,
      },
      { merge: true },
    );
  });
  return { requestId: id, deduped };
}

export const sendCustomerPaymentRequestV1 = functions
  .runWith({
    secrets: ["TWILIO_AUTH_TOKEN"],
  })
  .https.onRequest(async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const merchantId = requireStoreId(
        req.body?.merchantId ?? req.body?.storeId,
      );
      const initiatedBy = await authenticateMerchant(req, res, merchantId);
      if (!initiatedBy) return;
      const customerId = requestId(req.body?.customerId, "CUSTOMER_ID");
      const quote = await buildQuote(merchantId, customerId);
      if (!quote.canRequest) {
        if (quote.reason === "settled")
          throw new Error("CUSTOMER_ACCOUNT_SETTLED");
        if (quote.reason === "phone_missing") throw new Error("PHONE_MISSING");
        if (quote.reason === "cooldown_active")
          throw new Error("COOLDOWN_ACTIVE");
        if (quote.reason === "wallet_insufficient")
          throw new Error("INSUFFICIENT_CAMPAIGN_CREDITS");
        throw new Error("REQUEST_TEMPORARILY_UNAVAILABLE");
      }
      if (String(req.body?.quoteKey ?? "") !== quote.quoteKey) {
        throw new Error("QUOTE_CHANGED");
      }
      if (String(req.body?.pricingVersion ?? "") !== quote.pricingVersion) {
        throw new Error("QUOTE_CHANGED");
      }
      const reserved = await reserveCustomerPaymentRequest({
        quote,
        idempotencyKey: req.body?.idempotencyKey,
        initiatedBy,
      });
      if (!reserved.deduped) {
        await dispatchCustomerPaymentRequest(reserved.requestId).catch(
          (error) => {
            console.error("[payment-request] immediate dispatch failed", {
              requestId: reserved.requestId,
              code: error instanceof Error ? error.message : "unknown",
            });
          },
        );
      }
      const current = await db
        .doc(`customerPaymentRequests/${reserved.requestId}`)
        .get();
      res.status(202).json({
        schemaVersion: 1,
        requestId: reserved.requestId,
        status: String(current.get("status") ?? "queued"),
        mode: quote.mode,
        expectedChannel: quote.expectedChannel,
        deduped: reserved.deduped,
      });
    } catch (error) {
      const response = publicError(error);
      res.status(response.status).json({ error: response.message });
    }
  });

async function settleReservation(args: {
  requestId: string;
  actualCostMinor: number;
  outcome: "settled" | "released" | "recovered";
}): Promise<void> {
  const ref = reservationRef(args.requestId);
  await db.runTransaction(async (tx) => {
    const reservation = await tx.get(ref);
    if (!reservation.exists || reservation.get("status") !== "active") return;
    const reservedMinor = cents(Number(reservation.get("reservedMinor") ?? 0));
    const actualMinor = cents(args.actualCostMinor);
    if (actualMinor > reservedMinor) throw new Error("REQUEST_COST_EXCEEDED");
    const refundMinor = reservedMinor - actualMinor;
    const walletContext = campaignWalletContextFromCharge(
      reservation.get("storeId"),
      reservation.get("walletStoreId"),
      reservation.get("shared") === true,
    );
    if (refundMinor > 0) {
      await mutateCampaignCredits(tx, walletContext, refundMinor / 100, {
        id: `${args.outcome}:${args.requestId}`,
        kind:
          args.outcome === "settled"
            ? "payment-request-settlement"
            : args.outcome === "recovered"
              ? "payment-request-recovery"
              : "payment-request-release",
        metadata: {
          requestId: args.requestId,
          reservedMinor,
          actualMinor,
        },
      });
    }
    tx.update(ref, {
      status: args.outcome,
      spentMinor: actualMinor,
      refundedMinor: refundMinor,
      expiresAt: FieldValue.delete(),
      settledAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

export async function recordAcceptedCustomerPaymentRequest(args: {
  requestId: string;
  channel: "whatsapp" | "sms";
  providerMessageId: string;
}): Promise<void> {
  const ref = db.doc(`customerPaymentRequests/${args.requestId}`);
  let truth: FirebaseFirestore.DocumentData | null = null;
  await db.runTransaction(async (tx) => {
    const request = await tx.get(ref);
    if (!request.exists) throw new Error("REQUEST_NOT_FOUND");
    const data = request.data() ?? {};
    if (
      [
        "sent",
        "customer_engaged",
        "link_created",
        "partially_paid",
        "paid",
      ].includes(String(data.status))
    ) {
      truth = {
        ...data,
        actualCostMinor: cents(Number(data.actualMessageCostMinor ?? 0)),
        sentAt: data.sentAt,
      };
      return;
    }
    if (
      !["queued", "dispatching", "needs_review"].includes(String(data.status))
    ) {
      throw new Error("REQUEST_DELIVERY_STATE_INVALID");
    }
    const actualCostMinor =
      args.channel === "sms"
        ? cents(Number(data.smsCostMinor ?? data.quotedMessageCostMinor ?? 0))
        : cents(
            Number(data.whatsappCostMinor ?? data.quotedMessageCostMinor ?? 0),
          );
    const sentAt = Timestamp.now();
    const cooldownEndsAt = Timestamp.fromMillis(
      paymentRequestCooldownEndsAtMs(sentAt.toMillis()),
    );
    tx.update(ref, {
      status: "sent" satisfies CustomerPaymentRequestStatus,
      deliveredChannel: args.channel,
      providerMessageId: args.providerMessageId.slice(0, 200),
      actualMessageCostMinor: actualCostMinor,
      sentAt,
      cooldownEndsAt,
      dispatchLeaseUntil: FieldValue.delete(),
      smsFallbackStatus: args.channel === "sms" ? "accepted" : null,
      smsFallbackLeaseUntil: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(
      stateRef(String(data.merchantId), String(data.customerId)),
      {
        merchantId: data.merchantId,
        customerId: data.customerId,
        latestRequestId: args.requestId,
        lastSentRequestId: args.requestId,
        activeRequestId: FieldValue.delete(),
        sentAt,
        cooldownEndsAt,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    tx.set(
      db.doc(`users/${data.merchantId}/customers/${data.customerId}`),
      { lastReminderSent: sentAt, updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    truth = { ...data, actualCostMinor, sentAt };
  });
  if (!truth) return;
  const data = truth as FirebaseFirestore.DocumentData;
  const actualMinor = cents(Number(data.actualCostMinor ?? 0));
  await settleReservation({
    requestId: args.requestId,
    actualCostMinor: actualMinor,
    outcome: "settled",
  });
  const renderedMessage =
    args.channel === "sms"
      ? String(data.smsPreview ?? data.messagePreview ?? "Payment request sent")
      : String(data.messagePreview ?? "Payment request sent");
  await appendTruthSurfaceMessage({
    merchantId: String(data.merchantId),
    externalId: `payment-request:${args.requestId}`,
    messageEntry: {
      message: renderedMessage,
      customerNumber: normalizePhoneNumber(String(data.deliveryPhone ?? "")),
      direction: "outbound",
      senderRole: "merchant",
      channel: args.channel,
      kind:
        args.channel === "whatsapp" && data.mode === "whatsapp_online"
          ? "choices"
          : "text",
      externalId: `payment-request:${args.requestId}`,
      timestamp: new Date().toISOString(),
      isRead: true,
      presentation:
        args.channel === "whatsapp" && data.mode === "whatsapp_online"
          ? {
              schemaVersion: 1,
              type: "choices",
              text: renderedMessage,
              options: [{ label: "Pay securely" }],
            }
          : {
              schemaVersion: 1,
              type: "text",
              text: renderedMessage,
            },
    },
  }).catch(() => undefined);
}

async function markFailed(
  id: string,
  status: "failed" | "not_deliverable",
  code: string,
  reservationOutcome: "released" | "recovered" = "released",
  requireNeedsReview = false,
): Promise<void> {
  const ref = db.doc(`customerPaymentRequests/${id}`);
  let changed = false;
  await db.runTransaction(async (tx) => {
    const request = await tx.get(ref);
    if (!request.exists) throw new Error("REQUEST_NOT_FOUND");
    const currentStatus = String(request.get("status") ?? "");
    if (
      requireNeedsReview &&
      currentStatus !== "needs_review" &&
      currentStatus !== status
    ) {
      throw new Error("REQUEST_REVIEW_STATE_INVALID");
    }
    if (currentStatus === status) {
      changed = true;
      return;
    }
    if (!["queued", "dispatching", "needs_review"].includes(currentStatus))
      return;
    const customerStateRef = stateRef(
      String(request.get("merchantId") ?? ""),
      String(request.get("customerId") ?? ""),
    );
    const customerState = await tx.get(customerStateRef);
    const now = FieldValue.serverTimestamp();
    tx.update(ref, {
      status,
      failureCode: code.slice(0, 100),
      dispatchLeaseUntil: FieldValue.delete(),
      smsFallbackLeaseUntil: FieldValue.delete(),
      failedAt: now,
      updatedAt: now,
    });
    if (customerState.get("activeRequestId") === id) {
      tx.set(
        customerStateRef,
        { activeRequestId: FieldValue.delete(), updatedAt: now },
        { merge: true },
      );
    }
    changed = true;
  });
  if (!changed) return;
  await settleReservation({
    requestId: id,
    actualCostMinor: 0,
    outcome: reservationOutcome,
  });
}

/**
 * Operations-only release for a delivery that has been proven not to have
 * reached the provider. The authenticated, audited command lives in admin.ts;
 * keeping the reservation mutation here ensures normal and reviewed failures
 * use the exact same cent-safe runner.
 */
export async function releaseReviewedCustomerPaymentRequest(
  id: string,
  evidenceCode: string,
): Promise<void> {
  const safeCode = String(evidenceCode ?? "")
    .trim()
    .slice(0, 100);
  if (!safeCode) throw new Error("DELIVERY_EVIDENCE_REQUIRED");
  await markFailed(id, "failed", safeCode, "released", true);
}

async function markNeedsReview(id: string, code: string): Promise<void> {
  const ref = db.doc(`customerPaymentRequests/${id}`);
  let changed = false;
  await db.runTransaction(async (tx) => {
    const request = await tx.get(ref);
    if (!request.exists) throw new Error("REQUEST_NOT_FOUND");
    if (
      !["queued", "dispatching", "needs_review"].includes(
        String(request.get("status") ?? ""),
      )
    )
      return;
    tx.update(ref, {
      status: "needs_review" satisfies CustomerPaymentRequestStatus,
      reviewReason: code.slice(0, 100),
      operationsOwner: "operations",
      dispatchLeaseUntil: FieldValue.delete(),
      smsFallbackLeaseUntil: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    changed = true;
  });
  if (!changed) return;
  await reservationRef(id).set(
    { expiresAt: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
}

async function queueRetryOrReview(id: string, code: string): Promise<void> {
  const ref = db.doc(`customerPaymentRequests/${id}`);
  let review = false;
  await db.runTransaction(async (tx) => {
    const request = await tx.get(ref);
    if (!request.exists) throw new Error("REQUEST_NOT_FOUND");
    const status = String(request.get("status") ?? "");
    if (
      [
        "sent",
        "customer_engaged",
        "link_created",
        "partially_paid",
        "paid",
        "failed",
        "not_deliverable",
      ].includes(status)
    )
      return;
    const attempts = Number(request.get("deliveryAttemptCount") ?? 0);
    if (attempts >= MAX_ATTEMPTS) {
      review = true;
      return;
    }
    tx.update(ref, {
      status: "queued" satisfies CustomerPaymentRequestStatus,
      lastRetryReason: code.slice(0, 100),
      dispatchLeaseUntil: FieldValue.delete(),
      nextDeliveryAttemptAt: Timestamp.fromMillis(Date.now() + 60_000),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  if (review) await markNeedsReview(id, code);
}

function twilioClient() {
  const config = (functions.config().twilio ?? {}) as Record<string, unknown>;
  const accountSid = String(
    process.env.TWILIO_ACCOUNT_SID ??
      process.env.TWILIO_SID ??
      config.sid ??
      "",
  ).trim();
  const authToken = String(
    process.env.TWILIO_AUTH_TOKEN ??
      process.env.TWILIO_TOKEN ??
      config.token ??
      "",
  ).trim();
  if (!accountSid || !authToken) {
    throw new Error("TWILIO_CONFIGURATION_MISSING");
  }
  return twilio(accountSid, authToken);
}

function twilioSmsRuntime() {
  const config = (functions.config().twilio ?? {}) as Record<string, unknown>;
  const smsNumber = String(
    process.env.TWILIO_SMS_NUMBER ??
      process.env.TWILIO_NUMBER ??
      config.number ??
      "",
  ).trim();
  if (!smsNumber) {
    throw new Error("SMS_CONFIGURATION_MISSING");
  }
  return { client: twilioClient(), smsNumber };
}

function twilioPaymentRequestRuntime() {
  const config = (functions.config().twilio ?? {}) as Record<string, unknown>;
  const messagingServiceSid = String(
    process.env.TWILIO_CUSTOMER_MESSAGING_SERVICE_SID ??
      config.customer_messaging_service_sid ??
      "",
  ).trim();
  const contentSid = String(
    process.env.TWILIO_PAYMENT_REQUEST_CONTENT_SID ?? "",
  ).trim();
  if (!/^MG[A-Za-z0-9]{32}$/.test(messagingServiceSid)) {
    throw new Error("TWILIO_CUSTOMER_MESSAGING_SERVICE_INVALID");
  }
  if (!/^HX[A-Za-z0-9]{32}$/.test(contentSid)) {
    throw new Error("TWILIO_PAYMENT_REQUEST_CONTENT_INVALID");
  }
  return { client: twilioClient(), messagingServiceSid, contentSid };
}

async function sendSmsFallback(id: string): Promise<void> {
  const ref = db.doc(`customerPaymentRequests/${id}`);
  let claimed = false;
  await db.runTransaction(async (tx) => {
    const request = await tx.get(ref);
    if (!request.exists) throw new Error("REQUEST_NOT_FOUND");
    if (
      [
        "sent",
        "customer_engaged",
        "link_created",
        "partially_paid",
        "paid",
        "failed",
        "not_deliverable",
      ].includes(String(request.get("status") ?? ""))
    )
      return;
    if (request.get("smsFallbackStatus") === "accepted") return;
    const lease = request.get("smsFallbackLeaseUntil") as
      | { toMillis?: () => number }
      | undefined;
    if (
      request.get("smsFallbackStatus") === "dispatching" &&
      Number(lease?.toMillis?.() ?? 0) > Date.now()
    ) {
      return;
    }
    tx.update(ref, {
      smsFallbackStatus: "dispatching",
      smsFallbackAttemptCount: FieldValue.increment(1),
      smsFallbackLeaseUntil: Timestamp.fromMillis(Date.now() + 60_000),
      updatedAt: FieldValue.serverTimestamp(),
    });
    claimed = true;
  });
  if (!claimed) return;
  const request = await ref.get();
  if (!request.exists) throw new Error("REQUEST_NOT_FOUND");
  const data = request.data() ?? {};
  try {
    const mode = providerMode("TWILIO_PROVIDER_MODE");
    let providerMessageId = `stub-sms-${id}`;
    if (mode !== "stub") {
      const runtime = twilioSmsRuntime();
      providerMessageId = String(
        (
          await runtime.client.messages.create({
            to: String(data.deliveryPhone),
            from: runtime.smsNumber,
            body: String(data.smsPreview),
          })
        ).sid ?? "",
      );
    }
    if (!providerMessageId) throw new Error("SMS_ACCEPTANCE_MISSING");
    await recordAcceptedCustomerPaymentRequest({
      requestId: id,
      channel: "sms",
      providerMessageId,
    });
  } catch (error) {
    const code = error instanceof Error ? error.message : "SMS_SEND_FAILED";
    const statusCode = Number(
      (error as { status?: unknown; statusCode?: unknown })?.status ??
        (error as { statusCode?: unknown })?.statusCode,
    );
    if (Number.isInteger(statusCode) && statusCode >= 400 && statusCode < 500) {
      await markFailed(id, "not_deliverable", code);
    } else {
      await markNeedsReview(id, code || "SMS_DELIVERY_AMBIGUOUS");
    }
  }
}

export async function dispatchCustomerPaymentRequest(
  id: string,
): Promise<void> {
  const ref = db.doc(`customerPaymentRequests/${requestId(id, "REQUEST_ID")}`);
  let claimed = false;
  await db.runTransaction(async (tx) => {
    const request = await tx.get(ref);
    if (!request.exists) throw new Error("REQUEST_NOT_FOUND");
    const status = String(request.get("status") ?? "");
    if (status !== "queued") return;
    const attempts = Number(request.get("deliveryAttemptCount") ?? 0);
    if (attempts >= MAX_ATTEMPTS) return;
    tx.update(ref, {
      status: "dispatching" satisfies CustomerPaymentRequestStatus,
      deliveryAttemptCount: FieldValue.increment(1),
      dispatchLeaseUntil: Timestamp.fromMillis(Date.now() + 60_000),
      updatedAt: FieldValue.serverTimestamp(),
    });
    claimed = true;
  });
  if (!claimed) return;
  const request = await ref.get();
  const data = request.data() ?? {};
  if (data.expectedChannel === "sms") {
    await sendSmsFallback(id);
    return;
  }
  try {
    if (providerMode("TWILIO_PROVIDER_MODE") === "stub") {
      await recordAcceptedCustomerPaymentRequest({
        requestId: id,
        channel: "whatsapp",
        providerMessageId: `stub-twilio-wa-${id}`,
      });
      return;
    }
    const runtime = twilioPaymentRequestRuntime();
    const message = await runtime.client.messages.create({
      to: `whatsapp:${formatPhoneNumber(String(data.deliveryPhone))}`,
      messagingServiceSid: runtime.messagingServiceSid,
      contentSid: runtime.contentSid,
      contentVariables: JSON.stringify({
        customerName: String(data.customerName ?? "Customer"),
        shopName: String(data.shopName ?? "SpazaOne"),
        amount: moneyZar(Number(data.outstandingSnapshotMinor ?? 0)),
        requestId: id,
      }),
    });
    const acceptedMessageId = String(message.sid ?? "").trim();
    if (!acceptedMessageId) throw new Error("TWILIO_ACCEPTANCE_MISSING");
    await recordAcceptedCustomerPaymentRequest({
      requestId: id,
      channel: "whatsapp",
      providerMessageId: acceptedMessageId,
    });
  } catch (error) {
    await queueRetryOrReview(
      id,
      error instanceof Error ? error.message : "TWILIO_DISPATCH_AMBIGUOUS",
    );
  }
}

export const claimCustomerPaymentRequestDeliveryV1BotHttp = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const id = requestId(req.body?.requestId, "REQUEST_ID");
      const ref = db.doc(`customerPaymentRequests/${id}`);
      let claimed = false;
      let status = "failed";
      await db.runTransaction(async (tx) => {
        const request = await tx.get(ref);
        if (!request.exists) throw new Error("REQUEST_NOT_FOUND");
        status = String(request.get("status") ?? "failed");
        if (
          [
            "sent",
            "customer_engaged",
            "link_created",
            "partially_paid",
            "paid",
          ].includes(status) ||
          request.get("proactiveDeliveryClaimedAt")
        ) {
          return;
        }
        if (!["queued", "dispatching", "needs_review"].includes(status)) {
          return;
        }
        tx.update(ref, {
          proactiveDeliveryClaimId: `botpress:${id}`,
          proactiveDeliveryClaimedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        claimed = true;
      });
      res
        .status(200)
        .json({ schemaVersion: 1, requestId: id, claimed, status });
    } catch (error) {
      const response = publicError(error);
      res.status(response.status).json({ error: response.message });
    }
  });

export const recordCustomerPaymentRequestDeliveryV1BotHttp = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN", "TWILIO_AUTH_TOKEN"] })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const id = requestId(req.body?.requestId, "REQUEST_ID");
      const status = String(req.body?.status ?? "");
      const channel = req.body?.channel === "sms" ? "sms" : "whatsapp";
      if (status === "accepted") {
        await recordAcceptedCustomerPaymentRequest({
          requestId: id,
          channel,
          providerMessageId: providerMessageId(req.body?.providerMessageId),
        });
      } else if (status === "undeliverable" && channel === "whatsapp") {
        const request = await db.doc(`customerPaymentRequests/${id}`).get();
        if (!request.exists) throw new Error("REQUEST_NOT_FOUND");
        await storeWhatsAppCapability(
          String(request.get("deliveryPhone") ?? ""),
          false,
        );
        await sendSmsFallback(id);
      } else if (status === "failed" || status === "undeliverable") {
        await markFailed(id, "not_deliverable", "PROVIDER_NOT_DELIVERABLE");
      } else {
        await markNeedsReview(id, "PROVIDER_DELIVERY_AMBIGUOUS");
      }
      res.status(200).json({ success: true });
    } catch (error) {
      const response = publicError(error);
      res.status(response.status).json({ error: response.message });
    }
  });

export const getCustomerPaymentRequestStatusV1 = functions.https.onRequest(
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const id = requestId(req.body?.requestId, "REQUEST_ID");
      const request = await db.doc(`customerPaymentRequests/${id}`).get();
      if (!request.exists) throw new Error("REQUEST_NOT_FOUND");
      const merchantId = requireStoreId(request.get("merchantId"));
      if (!(await authenticateMerchant(req, res, merchantId))) return;
      const data = request.data() ?? {};
      res.status(200).json({
        schemaVersion: 1,
        requestId: id,
        status: String(data.status ?? "failed"),
        expectedChannel: String(data.expectedChannel ?? "sms"),
        outstandingSnapshotMinor: Number(data.outstandingSnapshotMinor ?? 0),
        actualMessageCostMinor: Number(data.actualMessageCostMinor ?? 0),
        sentAtMs: Number(
          (
            data.sentAt as { toMillis?: () => number } | undefined
          )?.toMillis?.() ?? 0,
        ),
        cooldownEndsAtMs: Number(
          (
            data.cooldownEndsAt as { toMillis?: () => number } | undefined
          )?.toMillis?.() ?? 0,
        ),
      });
    } catch (error) {
      const response = publicError(error);
      res.status(response.status).json({ error: response.message });
    }
  },
);

export const getCustomerPaymentRequestContextV1BotHttp = functions
  .runWith({ secrets: ["PASELLA_BOT_TOKEN"] })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const merchantId = requireStoreId(req.body?.merchantId);
      const customerId = requestId(req.body?.customerId, "CUSTOMER_ID");
      const customer = await db
        .doc(`users/${merchantId}/customers/${customerId}`)
        .get();
      if (!customer.exists) throw new Error("CUSTOMER_NOT_FOUND");
      const storedPhone = normalizePhoneNumber(
        String(customer.get("number") ?? ""),
      );
      const claimedPhone = normalizePhoneNumber(
        String(req.body?.customerPhone ?? "").replace("whatsapp:", ""),
      );
      if (!storedPhone || storedPhone !== claimedPhone) {
        throw new Error("REQUEST_BINDING_MISMATCH");
      }
      const suppliedRequestId = String(req.body?.paymentRequestId ?? "").trim();
      if (suppliedRequestId) {
        const request = await db
          .doc(
            `customerPaymentRequests/${requestId(suppliedRequestId, "REQUEST_ID")}`,
          )
          .get();
        if (
          !request.exists ||
          request.get("merchantId") !== merchantId ||
          request.get("customerId") !== customerId ||
          request.get("phoneFingerprint") !==
            phoneHash(formatPhoneNumber(storedPhone))
        ) {
          throw new Error("REQUEST_BINDING_MISMATCH");
        }
        await request.ref.set(
          {
            status:
              String(request.get("status")) === "sent"
                ? "customer_engaged"
                : request.get("status"),
            customerEngagedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      const readiness = await paymentReadiness({
        merchantId,
        purpose: "account_settlement",
      });
      res.status(200).json({
        schemaVersion: 1,
        merchantId,
        customerId,
        paymentRequestId: suppliedRequestId || null,
        outstandingAmountMinor: cents(
          Math.max(0, -Number(customer.get("balance") ?? 0)) * 100,
        ),
        ready: readiness.enabled,
        reason: readiness.reason,
        channels: readiness.enabled ? ["card", "eft", "capitec_pay", "qr"] : [],
      });
    } catch (error) {
      const response = publicError(error);
      res.status(response.status).json({ error: response.message });
    }
  });

export const retryCustomerPaymentRequestDeliveries = functions
  .runWith({
    secrets: ["TWILIO_AUTH_TOKEN"],
  })
  .pubsub.schedule("every 5 minutes")
  .onRun(async () => {
    const queued = await db
      .collection("customerPaymentRequests")
      .where("status", "==", "queued")
      .limit(50)
      .get();
    for (const request of queued.docs) {
      await dispatchCustomerPaymentRequest(request.id).catch(() => undefined);
    }
    const dispatching = await db
      .collection("customerPaymentRequests")
      .where("status", "==", "dispatching")
      .limit(50)
      .get();
    for (const request of dispatching.docs) {
      const lease = request.get("dispatchLeaseUntil") as
        | { toMillis?: () => number }
        | undefined;
      if (Number(lease?.toMillis?.() ?? 0) <= Date.now()) {
        await markNeedsReview(request.id, "DISPATCH_RESULT_UNKNOWN");
      }
    }
    return null;
  });

export const recoverExpiredPaymentRequestReservations = functions.pubsub
  .schedule("every 15 minutes")
  .onRun(async () => {
    const expired = await db
      .collection("paymentRequestWalletReservations")
      .where("expiresAt", "<=", Timestamp.now())
      .limit(100)
      .get();
    for (const reservation of expired.docs) {
      if (reservation.get("status") !== "active") continue;
      const id = String(reservation.get("requestId") ?? reservation.id);
      const request = await db.doc(`customerPaymentRequests/${id}`).get();
      if (request.get("status") === "needs_review") continue;
      await markFailed(
        id,
        "failed",
        "DELIVERY_RESERVATION_EXPIRED",
        "recovered",
      );
    }
    return null;
  });

export function verifyPaymentRequestWebhookSignature(args: {
  payload: string;
  signature: string;
  secret: string;
}): boolean {
  const expected = createHmac("sha256", args.secret)
    .update(args.payload)
    .digest("hex");
  const left = Buffer.from(expected);
  const right = Buffer.from(args.signature);
  return left.length === right.length && timingSafeEqual(left, right);
}
