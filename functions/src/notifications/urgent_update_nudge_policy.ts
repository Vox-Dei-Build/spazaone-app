export type UrgentUpdateNudgeState = {
  targetBuild?: number;
  count?: number;
  lastSentAtMs?: number;
};

export type UrgentUpdateCopy = {
  title: string;
  body: string;
};

const DEFAULT_TITLE = "Urgent: update Pasella today";
const DEFAULT_BODY =
  "Don't miss customer messages. Update to {version} now to keep " +
  "WhatsApp, SMS and conversations working reliably.";

/** Return true only for a known, positive build below the campaign target. */
export function isBuildBelowTarget(
  buildNumber: unknown,
  targetBuild: number,
): boolean {
  return (
    typeof buildNumber === "number" &&
    Number.isFinite(buildNumber) &&
    Number.isInteger(buildNumber) &&
    buildNumber > 0 &&
    buildNumber < targetBuild
  );
}

/** Enforce per-release send caps and cooldowns. */
export function canSendUrgentUpdateNudge(
  state: UrgentUpdateNudgeState | undefined,
  targetBuild: number,
  nowMs: number,
  maxSends: number,
  cooldownMs: number,
): boolean {
  if (!state || state.targetBuild !== targetBuild) return true;
  if ((state.count ?? 0) >= maxSends) return false;

  const lastSentAtMs = state.lastSentAtMs;
  if (lastSentAtMs == null) return true;
  return nowMs - lastSentAtMs >= cooldownMs;
}

/** Read and deduplicate both legacy and multi-device token fields. */
export function readFcmTokens(data: Record<string, unknown>): string[] {
  const tokens = new Set<string>();
  const multiple = data.fcmTokens;
  if (Array.isArray(multiple)) {
    for (const value of multiple) {
      const token = typeof value === "string" ? value.trim() : "";
      if (token) tokens.add(token);
    }
  }

  const legacy = typeof data.fcmToken === "string" ? data.fcmToken.trim() : "";
  if (legacy) tokens.add(legacy);
  return [...tokens].slice(0, 500);
}

/** Build compact push copy, allowing controlled Firestore overrides. */
export function urgentUpdateCopy(
  targetVersion: string,
  titleOverride?: unknown,
  bodyOverride?: unknown,
): UrgentUpdateCopy {
  const title = cleanCopy(titleOverride, 100) || DEFAULT_TITLE;
  const bodyTemplate = cleanCopy(bodyOverride, 300) || DEFAULT_BODY;
  return {
    title,
    body: bodyTemplate.replace(/\{version\}/g, targetVersion),
  };
}

function cleanCopy(value: unknown, maxLength: number): string {
  if (typeof value !== "string") return "";
  return value.trim().replace(/\s+/g, " ").slice(0, maxLength);
}
