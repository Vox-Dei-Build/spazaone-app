import { db, functions } from "../config/main";
import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

type ActivationNudgeType =
  | "add_first_customer"
  | "add_first_product"
  | "share_ordering_link"
  | "link_product_transaction"
  | "add_ten_customers";

type MerchantData = {
  fcmToken?: string;
  activationNudgesOptIn?: boolean;
  releaseChannel?: string;
  buildNumber?: number;
  activationNudges?: {
    lastSentAt?: Timestamp;
    weekKey?: string;
    sentThisWeek?: number;
    lastSentByType?: Partial<Record<ActivationNudgeType, Timestamp>>;
  };
};

type NudgeCandidate = {
  type: ActivationNudgeType;
  action: string;
  route: string;
  title: string;
  body: string;
};

type ActivationSnapshot = {
  customerCount: number;
  productCount: number;
  hasActiveOrderingLink: boolean;
  firstCustomerId?: string;
  hasProductLinkedCredit: boolean;
};

const MS_PER_DAY = 24 * 60 * 60 * 1000;
const TYPE_COOLDOWN_MS = 3 * MS_PER_DAY;

export const sendActivationNudges = functions.pubsub
  .schedule("every 24 hours")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    const enabled = process.env.ACTIVATION_NUDGES_ENABLED === "true";
    if (!enabled) {
      console.log("[activation-nudges] disabled");
      return null;
    }

    const dryRun = process.env.ACTIVATION_NUDGES_DRY_RUN !== "false";
    const maxPerRun = envInt("ACTIVATION_NUDGES_MAX_PER_RUN", 500);
    const users = await db.collection("users").limit(maxPerRun).get();
    const now = Timestamp.now();

    let evaluated = 0;
    let sent = 0;
    let dryRuns = 0;
    let skipped = 0;

    for (const userDoc of users.docs) {
      evaluated++;
      const result = await processMerchant(userDoc, now, dryRun);
      if (result === "sent") sent++;
      if (result === "dry_run") dryRuns++;
      if (result === "skipped") skipped++;
    }

    console.log("[activation-nudges] completed", {
      evaluated,
      sent,
      dryRuns,
      skipped,
      dryRun,
    });

    return null;
  });

async function processMerchant(
  userDoc: admin.firestore.QueryDocumentSnapshot,
  now: Timestamp,
  dryRun: boolean,
): Promise<"sent" | "dry_run" | "skipped"> {
  const merchantId = userDoc.id;
  const data = userDoc.data() as MerchantData;

  if (!isMerchantInAudience(data)) return "skipped";

  const snapshot = await loadActivationSnapshot(merchantId);
  const nudge = chooseNudge(snapshot);
  if (!nudge) return "skipped";

  if (!canSendNudge(data, nudge.type, now)) return "skipped";

  const userRef = db.collection("users").doc(merchantId);
  const logRef = userRef.collection("activationNudges").doc();
  await logRef.set({
    type: nudge.type,
    action: nudge.action,
    route: nudge.route,
    channel: "fcm",
    status: dryRun ? "dry_run" : "pending",
    createdAt: FieldValue.serverTimestamp(),
    customerCount: snapshot.customerCount,
    productCount: snapshot.productCount,
    hasActiveOrderingLink: snapshot.hasActiveOrderingLink,
    hasProductLinkedCredit: snapshot.hasProductLinkedCredit,
  });

  if (dryRun) {
    await userRef.update({
      "activationNudges.lastDryRunAt": FieldValue.serverTimestamp(),
      "activationNudges.lastDryRunType": nudge.type,
    });
    return "dry_run";
  }

  const token = data.fcmToken?.trim();
  if (!token) {
    await logRef.update({
      status: "skipped_no_fcm_token",
      updatedAt: FieldValue.serverTimestamp(),
    });
    return "skipped";
  }

  try {
    const messageId = await admin.messaging().send({
      token,
      notification: {
        title: nudge.title,
        body: nudge.body,
      },
      data: {
        route: nudge.route,
        activationAction: nudge.action,
        nudgeType: nudge.type,
        nudgeId: logRef.id,
      },
      android: {
        notification: {
          channelId: "default_channel",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });

    await logRef.update({
      status: "sent",
      messageId,
      sentAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    await updateSendCaps(userRef, data, nudge.type, now);
    return "sent";
  } catch (error) {
    await logRef.update({
      status: "send_failed",
      errorCode: errorCodeOf(error),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (isInvalidFcmTokenError(error)) {
      await userRef.update({ fcmToken: FieldValue.delete() });
    }
    console.error("[activation-nudges] send failed", {
      merchantId,
      type: nudge.type,
      error,
    });
    return "skipped";
  }
}

async function loadActivationSnapshot(
  merchantId: string,
): Promise<ActivationSnapshot> {
  const userRef = db.collection("users").doc(merchantId);
  const [merchantSnap, customersSnap, productsSnap] = await Promise.all([
    userRef.get(),
    userRef.collection("customers").limit(10).get(),
    userRef.collection("products").limit(1).get(),
  ]);

  const customerCount =
    customersSnap.size >= 10 ? 10 : customersSnap.docs.length;
  const firstCustomerId = customersSnap.docs[0]?.id;
  const productCount = productsSnap.empty ? 0 : 1;
  const ordering = merchantSnap.get("whatsappOrdering") as
    | { status?: string; orderingUrl?: string; code?: string }
    | undefined;
  const hasActiveOrderingLink =
    ordering?.status === "active" &&
    Boolean(ordering.orderingUrl || ordering.code);
  let hasProductLinkedCredit = false;

  for (const customerDoc of customersSnap.docs) {
    if (hasProductLinkedCredit) break;
    const txSnap = await customerDoc.ref
      .collection("transactions")
      .where("type", "==", "Credit")
      .limit(10)
      .get();

    hasProductLinkedCredit = txSnap.docs.some((txDoc) =>
      hasLinkedProducts(txDoc.data().products),
    );
  }

  return {
    customerCount,
    productCount,
    hasActiveOrderingLink,
    firstCustomerId,
    hasProductLinkedCredit,
  };
}

function chooseNudge(snapshot: ActivationSnapshot): NudgeCandidate | null {
  if (snapshot.customerCount === 0) {
    return {
      type: "add_first_customer",
      action: "add_first_customer",
      route: "/dashboard?activation=add_first_customer",
      title: "Add your first customer",
      body: "Save one customer so you can record credit, payments, and messages.",
    };
  }

  if (snapshot.productCount === 0) {
    return {
      type: "add_first_product",
      action: "add_first_product",
      route: "/dashboard?activation=add_first_product",
      title: "Add your first product",
      body: "Add one item you sell so stock and sales reports can connect.",
    };
  }

  if (!snapshot.hasActiveOrderingLink) {
    return {
      type: "share_ordering_link",
      action: "share_ordering_link",
      route: "/dashboard?activation=share_ordering_link",
      title: "Share your ordering link",
      body: "Your product is ready. Send customers your WhatsApp ordering link.",
    };
  }

  if (!snapshot.hasProductLinkedCredit && snapshot.firstCustomerId) {
    return {
      type: "link_product_transaction",
      action: "link_product_transaction",
      route:
        "/dashboard?activation=link_product_transaction" +
        `&customerId=${encodeURIComponent(snapshot.firstCustomerId)}`,
      title: "Link a product to credit",
      body: "Next credit sale: attach the product so stock and history stay connected.",
    };
  }

  if (snapshot.customerCount > 0 && snapshot.customerCount < 10) {
    return {
      type: "add_ten_customers",
      action: "add_ten_customers",
      route: "/dashboard?activation=add_ten_customers",
      title: "Build toward 10 customers",
      body: `You have ${snapshot.customerCount} saved. Add a few more regular customers.`,
    };
  }

  return null;
}

function canSendNudge(
  data: MerchantData,
  nudgeType: ActivationNudgeType,
  now: Timestamp,
): boolean {
  const state = data.activationNudges;
  if (!state) return true;

  if (state.lastSentAt && ageMs(state.lastSentAt, now) < MS_PER_DAY) {
    return false;
  }

  const maxPerWeek = envInt("ACTIVATION_NUDGES_MAX_PER_WEEK", 3);
  const weekKey = johannesburgWeekKey(now.toDate());
  if (state.weekKey === weekKey && (state.sentThisWeek ?? 0) >= maxPerWeek) {
    return false;
  }

  const lastTypeSent = state.lastSentByType?.[nudgeType];
  if (lastTypeSent && ageMs(lastTypeSent, now) < TYPE_COOLDOWN_MS) {
    return false;
  }

  return true;
}

async function updateSendCaps(
  userRef: admin.firestore.DocumentReference,
  data: MerchantData,
  nudgeType: ActivationNudgeType,
  now: Timestamp,
): Promise<void> {
  const weekKey = johannesburgWeekKey(now.toDate());
  const previousWeekKey = data.activationNudges?.weekKey;
  const sameWeek = previousWeekKey === weekKey;
  await userRef.update({
    "activationNudges.lastSentAt": FieldValue.serverTimestamp(),
    "activationNudges.lastType": nudgeType,
    "activationNudges.weekKey": weekKey,
    "activationNudges.sentThisWeek": sameWeek ? FieldValue.increment(1) : 1,
    [`activationNudges.lastSentByType.${nudgeType}`]:
      FieldValue.serverTimestamp(),
  });
}

function isMerchantInAudience(data: MerchantData): boolean {
  const minBuild = envInt("ACTIVATION_NUDGES_MIN_BUILD", 0);
  if (minBuild > 0 && (data.buildNumber ?? 0) < minBuild) return false;

  const audience = process.env.ACTIVATION_NUDGES_AUDIENCE ?? "all";
  if (audience === "all") return true;
  if (audience === "opt_in") return data.activationNudgesOptIn === true;
  if (audience === "prerelease") {
    const channel = data.releaseChannel?.toLowerCase();
    return (
      data.activationNudgesOptIn === true ||
      channel === "beta" ||
      channel === "prerelease" ||
      channel === "internal"
    );
  }
  return false;
}

function hasLinkedProducts(value: unknown): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  return Object.keys(value as Record<string, unknown>).length > 0;
}

function ageMs(then: Timestamp, now: Timestamp): number {
  return now.toMillis() - then.toMillis();
}

function johannesburgWeekKey(date: Date): string {
  const parts = new Intl.DateTimeFormat("en-ZA", {
    timeZone: "Africa/Johannesburg",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const year = parts.find((p) => p.type === "year")?.value ?? "1970";
  const month = parts.find((p) => p.type === "month")?.value ?? "01";
  const day = parts.find((p) => p.type === "day")?.value ?? "01";
  const localDate = new Date(`${year}-${month}-${day}T00:00:00.000Z`);
  const firstDay = new Date(Date.UTC(localDate.getUTCFullYear(), 0, 1));
  const dayOfYear =
    Math.floor((localDate.getTime() - firstDay.getTime()) / MS_PER_DAY) + 1;
  const week = Math.ceil(dayOfYear / 7)
    .toString()
    .padStart(2, "0");
  return `${year}-W${week}`;
}

function envInt(key: string, fallback: number): number {
  const raw = process.env[key];
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function errorCodeOf(error: unknown): string {
  if (typeof error === "object" && error !== null && "code" in error) {
    return String((error as { code?: unknown }).code ?? "unknown");
  }
  return "unknown";
}

function isInvalidFcmTokenError(error: unknown): boolean {
  const code = errorCodeOf(error);
  return (
    code === "messaging/registration-token-not-registered" ||
    code === "messaging/invalid-registration-token"
  );
}
