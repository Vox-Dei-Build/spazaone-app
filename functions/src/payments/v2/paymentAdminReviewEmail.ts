import { createHash } from "crypto";
import axios from "axios";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import nodemailer from "nodemailer";
import { db, functions } from "../../config/main";

const REVIEW_EMAIL = "tsepo.ntsaba@thedelta.io";
const OUTBOX_COLLECTION = "paymentAdminReviewEmailOutbox";
const DELIVERY_LEASE_MS = 60_000;
const MAX_DELIVERIES_PER_RUN = 100;

type DocumentData = Record<string, unknown>;

function asRecord(value: unknown): DocumentData {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as DocumentData;
}

function cleanIdentifier(value: unknown): string {
  const parsed = String(value ?? "").trim();
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(parsed)) {
    throw new Error("MERCHANT_ID_INVALID");
  }
  return parsed;
}

function cleanFingerprint(value: unknown): string {
  const parsed = String(value ?? "")
    .trim()
    .toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(parsed)) {
    throw new Error("ACCOUNT_FINGERPRINT_INVALID");
  }
  return parsed;
}

function errorCode(error: unknown): string {
  if (error && typeof error === "object" && "code" in error) {
    return String((error as { code?: unknown }).code ?? "unknown");
  }
  return error instanceof Error ? error.message : "unknown";
}

function alreadyExistsError(error: unknown): boolean {
  const code = errorCode(error).toLowerCase();
  return code === "6" || code.includes("already-exists");
}

function retryAt(attemptCount: number): Timestamp {
  const exponent = Math.min(8, Math.max(0, attemptCount));
  const delayMinutes = Math.min(24 * 60, Math.max(5, 2 ** exponent * 5));
  return Timestamp.fromMillis(Date.now() + delayMinutes * 60_000);
}

function htmlEscape(value: unknown): string {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export function paymentAdminReviewEmailId(input: {
  merchantId: unknown;
  accountFingerprint: unknown;
}): string {
  const merchantId = cleanIdentifier(input.merchantId);
  const fingerprint = cleanFingerprint(input.accountFingerprint);
  return createHash("sha256")
    .update(`settlement-review-email\u0000${merchantId}\u0000${fingerprint}`)
    .digest("hex");
}

export function pendingSettlementFingerprint(profile: unknown): string {
  const value = asRecord(profile);
  if (String(value.status ?? "") !== "pending_review") return "";
  const pending = asRecord(value.pendingSettlement);
  const fingerprint = String(pending.accountFingerprint ?? "")
    .trim()
    .toLowerCase();
  return /^[a-f0-9]{64}$/.test(fingerprint) ? fingerprint : "";
}

export function shouldSendPaymentAdminReviewEmail(
  before: unknown,
  after: unknown,
): boolean {
  const next = pendingSettlementFingerprint(after);
  return next.length > 0 && next !== pendingSettlementFingerprint(before);
}

export function paymentAdminReviewEmailProjection(input: {
  merchantId: unknown;
  merchantName: unknown;
  profile: unknown;
}): DocumentData {
  const merchantId = cleanIdentifier(input.merchantId);
  const profile = asRecord(input.profile);
  const pending = asRecord(profile.pendingSettlement);
  const accountFingerprint = cleanFingerprint(pending.accountFingerprint);
  const accountLast4 = String(pending.accountLast4 ?? "").replace(/\D/g, "");
  if (!/^\d{4}$/.test(accountLast4)) {
    throw new Error("ACCOUNT_LAST4_INVALID");
  }
  const merchantName =
    String(input.merchantName ?? "")
      .trim()
      .slice(0, 100) || "Merchant";
  const bankName = String(pending.bankName ?? "")
    .trim()
    .slice(0, 100);
  return {
    emailId: paymentAdminReviewEmailId({ merchantId, accountFingerprint }),
    merchantId,
    merchantName,
    bankName,
    maskedAccount: `•••• ${accountLast4}`,
    accountFingerprint,
    recipient: REVIEW_EMAIL,
    deliveryStatus: "pending",
    schemaVersion: 1,
  };
}

export function paymentAdminReviewEmailContent(input: {
  emailId: string;
  merchantName: string;
  bankName: string;
  maskedAccount: string;
}): { subject: string; text: string; html: string } {
  const subject = `SpazaOne payment review: ${input.merchantName}`;
  const text = [
    "A merchant settlement account is waiting for SpazaOne review.",
    "",
    `Shop: ${input.merchantName}`,
    `Bank: ${input.bankName || "Not supplied"}`,
    `Account: ${input.maskedAccount}`,
    `Review reference: ${input.emailId}`,
    "",
    "Open the SpazaOne payment administration records and approve or reject the pending request with an audit reason.",
    "Do not approve it unless the masked destination matches the submitted evidence.",
  ].join("\n");
  const html = [
    "<p>A merchant settlement account is waiting for SpazaOne review.</p>",
    "<ul>",
    `<li><strong>Shop:</strong> ${htmlEscape(input.merchantName)}</li>`,
    `<li><strong>Bank:</strong> ${htmlEscape(input.bankName || "Not supplied")}</li>`,
    `<li><strong>Account:</strong> ${htmlEscape(input.maskedAccount)}</li>`,
    `<li><strong>Review reference:</strong> ${htmlEscape(input.emailId)}</li>`,
    "</ul>",
    "<p>Open the SpazaOne payment administration records and approve or reject the pending request with an audit reason.</p>",
    "<p>Do not approve it unless the masked destination matches the submitted evidence.</p>",
  ].join("");
  return { subject, text, html };
}

function mailCredentials(): { login: string; password: string } {
  const login = String(process.env.EMAIL_ADMINLOGIN ?? "").trim();
  const password = String(process.env.EMAIL_ADMINPASS ?? "").trim();
  if (!login || !password) throw new Error("ADMIN_EMAIL_NOT_CONFIGURED");
  return { login, password };
}

async function sendReviewEmail(input: {
  emailId: string;
  recipient: string;
  merchantName: string;
  bankName: string;
  maskedAccount: string;
}): Promise<void> {
  const credentials = mailCredentials();
  const content = paymentAdminReviewEmailContent(input);
  const messageId = `<payment-review-${input.emailId}@spazaone.com>`;
  if (credentials.login.includes("@")) {
    const transport = nodemailer.createTransport({
      host: String(process.env.EMAIL_SMTP_HOST ?? "smtp.mailgun.org"),
      port: Number(process.env.EMAIL_SMTP_PORT ?? 587),
      secure: String(process.env.EMAIL_SMTP_SECURE ?? "false") === "true",
      auth: { user: credentials.login, pass: credentials.password },
      tls: { minVersion: "TLSv1.2" },
    });
    await transport.sendMail({
      from: `SpazaOne Payments <${credentials.login}>`,
      to: input.recipient,
      subject: content.subject,
      text: content.text,
      html: content.html,
      messageId,
    });
    return;
  }

  const domain = String(
    process.env.EMAIL_MAILGUN_DOMAIN ?? "spazaone.com",
  ).trim();
  if (!/^[A-Za-z0-9.-]+$/.test(domain)) {
    throw new Error("MAILGUN_DOMAIN_INVALID");
  }
  const baseUrl = String(
    process.env.EMAIL_MAILGUN_BASE_URL ?? "https://api.mailgun.net",
  ).replace(/\/$/, "");
  if (
    !["https://api.mailgun.net", "https://api.eu.mailgun.net"].includes(baseUrl)
  ) {
    throw new Error("MAILGUN_BASE_URL_INVALID");
  }
  const fromAddress = String(
    process.env.EMAIL_FROM_ADDRESS ?? `postmaster@${domain}`,
  ).trim();
  if (!/^[^\s@]+@[^\s@]+$/.test(fromAddress)) {
    throw new Error("EMAIL_FROM_ADDRESS_INVALID");
  }
  const form = new URLSearchParams({
    from: `SpazaOne Payments <${fromAddress}>`,
    to: input.recipient,
    subject: content.subject,
    text: content.text,
    html: content.html,
    "h:Message-Id": messageId,
  });
  await axios.post(`${baseUrl}/v3/${domain}/messages`, form.toString(), {
    auth: {
      username: credentials.login,
      password: credentials.password,
    },
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    timeout: 20_000,
  });
}

async function enqueueReviewEmail(
  merchantId: string,
  profile: DocumentData,
): Promise<string> {
  const merchant = await db.doc(`users/${merchantId}`).get();
  const merchantData = merchant.data() ?? {};
  const projection = paymentAdminReviewEmailProjection({
    merchantId,
    merchantName:
      merchantData.shopName ??
      merchantData.businessName ??
      merchantData.name ??
      "Merchant",
    profile,
  });
  const emailId = String(projection.emailId);
  const outboxRef = db.doc(`${OUTBOX_COLLECTION}/${emailId}`);
  await outboxRef
    .create({
      ...projection,
      attemptCount: 0,
      nextAttemptAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    })
    .catch((error: unknown) => {
      if (alreadyExistsError(error)) return;
      throw error;
    });
  return emailId;
}

async function claimDelivery(emailId: string): Promise<DocumentData | null> {
  const outboxRef = db.doc(`${OUTBOX_COLLECTION}/${emailId}`);
  let claimed: DocumentData | null = null;
  await db.runTransaction(async (tx) => {
    const outbox = await tx.get(outboxRef);
    if (!outbox.exists) return;
    const value = outbox.data() ?? {};
    if (value.deliveryStatus === "delivered") return;
    if (
      value.deliveryStatus === "processing" &&
      Number(value.leaseUntilMs ?? 0) > Date.now()
    ) {
      return;
    }
    const attemptCount = Number(value.attemptCount ?? 0) + 1;
    claimed = { ...value, attemptCount };
    tx.update(outboxRef, {
      deliveryStatus: "processing",
      attemptCount,
      leaseUntilMs: Date.now() + DELIVERY_LEASE_MS,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return claimed;
}

export async function deliverPaymentAdminReviewEmail(
  emailId: string,
): Promise<boolean> {
  const cleanEmailId = cleanFingerprint(emailId);
  const claimed = await claimDelivery(cleanEmailId);
  if (!claimed) return false;
  const outboxRef = db.doc(`${OUTBOX_COLLECTION}/${cleanEmailId}`);
  const attemptCount = Number(claimed.attemptCount ?? 1);
  try {
    await sendReviewEmail({
      emailId: cleanEmailId,
      recipient: String(claimed.recipient ?? REVIEW_EMAIL),
      merchantName: String(claimed.merchantName ?? "Merchant"),
      bankName: String(claimed.bankName ?? ""),
      maskedAccount: String(claimed.maskedAccount ?? ""),
    });
    await outboxRef.update({
      deliveryStatus: "delivered",
      deliveredAt: FieldValue.serverTimestamp(),
      leaseUntilMs: 0,
      lastFailureCode: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  } catch (error) {
    await outboxRef.update({
      deliveryStatus: "retry",
      nextAttemptAt: retryAt(attemptCount),
      leaseUntilMs: 0,
      lastFailureCode: errorCode(error).slice(0, 120),
      updatedAt: FieldValue.serverTimestamp(),
    });
    console.error("[payment-admin] review email delivery failed", {
      emailId: cleanEmailId,
      code: errorCode(error),
    });
    return false;
  }
}

export const onMerchantSettlementReviewEmail = functions
  .runWith({ failurePolicy: true, secrets: ["EMAIL_ADMINPASS"] })
  .firestore.document("merchantPaymentProfiles/{merchantId}")
  .onWrite(async (change, context) => {
    const before = change.before.data() ?? {};
    const after = change.after.data() ?? {};
    if (!shouldSendPaymentAdminReviewEmail(before, after)) return;
    const emailId = await enqueueReviewEmail(
      cleanIdentifier(context.params.merchantId),
      after,
    );
    await deliverPaymentAdminReviewEmail(emailId);
  });

export const retryPaymentAdminReviewEmails = functions
  .runWith({
    timeoutSeconds: 300,
    memory: "256MB",
    secrets: ["EMAIL_ADMINPASS"],
  })
  .pubsub.schedule("every 15 minutes")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    // Backfill requests that predate this trigger or whose original trigger
    // failed before an outbox document was created. Deterministic email IDs
    // make the scan safe to repeat without sending another delivered email.
    const pendingProfiles = await db
      .collection("merchantPaymentProfiles")
      .where("status", "==", "pending_review")
      .limit(MAX_DELIVERIES_PER_RUN)
      .get();
    for (const profile of pendingProfiles.docs) {
      const fingerprint = pendingSettlementFingerprint(profile.data());
      if (!fingerprint) continue;
      const emailId = await enqueueReviewEmail(profile.id, profile.data());
      await deliverPaymentAdminReviewEmail(emailId);
    }

    const outbox = await db
      .collection(OUTBOX_COLLECTION)
      .where("deliveryStatus", "in", ["pending", "retry"])
      .limit(MAX_DELIVERIES_PER_RUN)
      .get();
    const now = Date.now();
    for (const item of outbox.docs) {
      const nextAttemptAt = item.get("nextAttemptAt");
      if (
        nextAttemptAt instanceof Timestamp &&
        nextAttemptAt.toMillis() > now
      ) {
        continue;
      }
      await deliverPaymentAdminReviewEmail(item.id);
    }
    return null;
  });
