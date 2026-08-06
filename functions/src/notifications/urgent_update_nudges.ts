import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { MulticastMessage } from "firebase-admin/messaging";
import { db, functions } from "../config/main";
import {
  canSendUrgentUpdateNudge,
  isBuildBelowTarget,
  readFcmTokens,
  urgentUpdateCopy,
} from "./urgent_update_nudge_policy";

const CONFIG_PATH = "systemConfig/urgentUpdateNudges";
const DEFAULT_TARGET_BUILD = 70;
const DEFAULT_TARGET_VERSION = "4.1.6";
const DEFAULT_MAX_PER_RUN = 500;
const DEFAULT_MAX_SENDS = 3;
// The scheduler runs once per day. Keep this below 24 hours so normal
// scheduler jitter cannot suppress the following day's reminder.
const DEFAULT_COOLDOWN_HOURS = 23;
const ONE_HOUR_MS = 60 * 60 * 1000;
const PLAY_STORE_URL =
  "https://play.google.com/store/apps/details?id=com.tsepo.pasella";
const APP_STORE_URL = "https://apps.apple.com/app/id6751821457";

type CampaignConfig = {
  enabled?: boolean;
  dryRun?: boolean;
  targetBuild?: number;
  targetVersion?: string;
  maxPerRun?: number;
  maxSendsPerUser?: number;
  cooldownHours?: number;
  title?: string;
  body?: string;
};

type StoredNudgeState = {
  targetBuild?: number;
  count?: number;
  lastSentAt?: Timestamp;
};

type CampaignResult =
  | "sent"
  | "dry_run"
  | "not_outdated"
  | "capped"
  | "no_token"
  | "failed";

/**
 * Nudges known app builds below the configured release daily at 08:00 SAST.
 *
 * The Firestore config is disabled by default. Dry-run is the safe default
 * even after enabling it, so rollout requires two deliberate switches.
 */
export const sendUrgentUpdateNudges = functions
  .runWith({ timeoutSeconds: 540, memory: "512MB" })
  .pubsub.schedule("0 8 * * *")
  .timeZone("Africa/Johannesburg")
  .onRun(async () => {
    const configRef = db.doc(CONFIG_PATH);
    const configSnap = await configRef.get();
    const rawConfig = (configSnap.data() ?? {}) as CampaignConfig;
    if (rawConfig.enabled !== true) {
      console.log("[urgent-update] disabled");
      return null;
    }

    const targetBuild = boundedInt(
      rawConfig.targetBuild,
      DEFAULT_TARGET_BUILD,
      1,
      1000000,
    );
    const targetVersion = cleanVersion(rawConfig.targetVersion);
    const maxPerRun = boundedInt(
      rawConfig.maxPerRun,
      DEFAULT_MAX_PER_RUN,
      1,
      1000,
    );
    const maxSends = boundedInt(
      rawConfig.maxSendsPerUser,
      DEFAULT_MAX_SENDS,
      1,
      5,
    );
    const cooldownHours = boundedInt(
      rawConfig.cooldownHours,
      DEFAULT_COOLDOWN_HOURS,
      6,
      168,
    );
    const dryRun = rawConfig.dryRun !== false;
    const now = Timestamp.now();
    const copy = urgentUpdateCopy(
      targetVersion,
      rawConfig.title,
      rawConfig.body,
    );
    const users = await db
      .collection("users")
      .where("buildNumber", "<", targetBuild)
      .limit(maxPerRun)
      .get();

    const counts: Record<CampaignResult, number> = {
      sent: 0,
      dry_run: 0,
      not_outdated: 0,
      capped: 0,
      no_token: 0,
      failed: 0,
    };

    for (const candidate of users.docs) {
      const result = await processCandidate({
        userRef: candidate.ref,
        targetBuild,
        targetVersion,
        maxSends,
        cooldownMs: cooldownHours * ONE_HOUR_MS,
        now,
        dryRun,
        copy,
      });
      counts[result]++;
    }

    await configRef.collection("runs").add({
      targetBuild,
      targetVersion,
      dryRun,
      evaluated: users.size,
      ...counts,
      createdAt: FieldValue.serverTimestamp(),
    });
    console.log("[urgent-update] completed", {
      targetBuild,
      targetVersion,
      dryRun,
      evaluated: users.size,
      ...counts,
    });
    return null;
  });

async function processCandidate({
  userRef,
  targetBuild,
  targetVersion,
  maxSends,
  cooldownMs,
  now,
  dryRun,
  copy,
}: {
  userRef: FirebaseFirestore.DocumentReference;
  targetBuild: number;
  targetVersion: string;
  maxSends: number;
  cooldownMs: number;
  now: Timestamp;
  dryRun: boolean;
  copy: { title: string; body: string };
}): Promise<CampaignResult> {
  // Re-read immediately before sending. A heartbeat from a newly updated app
  // can land after the initial audience query and must cancel the nudge.
  const latest = await userRef.get();
  const data = (latest.data() ?? {}) as Record<string, unknown>;
  if (!isBuildBelowTarget(data.buildNumber, targetBuild)) {
    return "not_outdated";
  }

  const tokens = readFcmTokens(data);
  if (!tokens.length) return "no_token";

  const state = readNudgeState(data);
  if (
    !canSendUrgentUpdateNudge(
      {
        targetBuild: state.targetBuild,
        count: state.count,
        lastSentAtMs: state.lastSentAt?.toMillis(),
      },
      targetBuild,
      now.toMillis(),
      maxSends,
      cooldownMs,
    )
  ) {
    return "capped";
  }

  if (dryRun) return "dry_run";

  const platform = data.platform === "ios" ? "ios" : "android";
  const collapseId = `urgent-update-${targetBuild}`;
  const message: MulticastMessage = {
    tokens,
    notification: copy,
    data: {
      type: "URGENT_APP_UPDATE",
      source: "sendUrgentUpdateNudges",
      targetBuild: String(targetBuild),
      targetVersion,
      storeUrl: platform === "ios" ? APP_STORE_URL : PLAY_STORE_URL,
    },
    android: {
      priority: "high",
      ttl: 24 * ONE_HOUR_MS,
      collapseKey: collapseId,
      notification: {
        channelId: "default_channel",
        sound: "default",
        tag: collapseId,
      },
    },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-collapse-id": collapseId,
      },
      payload: {
        aps: { sound: "default" },
      },
    },
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    const badTokens = response.responses
      .map((result, index) => ({ result, token: tokens[index] }))
      .filter(({ result }) => isInvalidTokenCode(result.error?.code))
      .map(({ token }) => token);
    if (badTokens.length) {
      await removeBadTokens(userRef, data, badTokens);
    }

    if (response.successCount === 0) return "failed";

    const previousCount =
      state.targetBuild === targetBuild ? (state.count ?? 0) : 0;
    await userRef.update({
      "notificationNudges.urgentUpdate.targetBuild": targetBuild,
      "notificationNudges.urgentUpdate.targetVersion": targetVersion,
      "notificationNudges.urgentUpdate.count": previousCount + 1,
      "notificationNudges.urgentUpdate.lastSentAt":
        FieldValue.serverTimestamp(),
      "notificationNudges.urgentUpdate.lastSuccessCount": response.successCount,
    });
    return "sent";
  } catch (error) {
    console.error("[urgent-update] send failed", {
      merchantId: userRef.id,
      code: errorCode(error),
    });
    return "failed";
  }
}

function readNudgeState(data: Record<string, unknown>): StoredNudgeState {
  const nudges = asRecord(data.notificationNudges);
  return asRecord(nudges.urgentUpdate) as StoredNudgeState;
}

async function removeBadTokens(
  userRef: FirebaseFirestore.DocumentReference,
  data: Record<string, unknown>,
  badTokens: string[],
): Promise<void> {
  const update: FirebaseFirestore.UpdateData<FirebaseFirestore.DocumentData> = {
    fcmTokens: FieldValue.arrayRemove(...badTokens),
  };
  if (typeof data.fcmToken === "string" && badTokens.includes(data.fcmToken)) {
    update.fcmToken = FieldValue.delete();
  }
  await userRef.update(update);
}

function isInvalidTokenCode(code: unknown): boolean {
  const value = String(code ?? "");
  return (
    value.includes("registration-token-not-registered") ||
    value.includes("invalid-registration-token")
  );
}

function asRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

function boundedInt(
  value: unknown,
  fallback: number,
  min: number,
  max: number,
): number {
  if (typeof value !== "number" || !Number.isInteger(value)) return fallback;
  return Math.min(max, Math.max(min, value));
}

function cleanVersion(value: unknown): string {
  if (typeof value !== "string") return DEFAULT_TARGET_VERSION;
  const cleaned = value.trim().slice(0, 32);
  return /^\d+\.\d+\.\d+$/.test(cleaned) ? cleaned : DEFAULT_TARGET_VERSION;
}

function errorCode(error: unknown): string {
  if (error && typeof error === "object" && "code" in error) {
    return String((error as { code?: unknown }).code ?? "unknown");
  }
  return "unknown";
}
