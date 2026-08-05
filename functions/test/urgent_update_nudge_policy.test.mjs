import assert from "node:assert/strict";
import test from "node:test";
import policy from "../lib/notifications/urgent_update_nudge_policy.js";

const {
  canSendUrgentUpdateNudge,
  isBuildBelowTarget,
  readFcmTokens,
  urgentUpdateCopy,
} = policy;

test("targets only known positive builds below the release", () => {
  assert.equal(isBuildBelowTarget(69, 70), true);
  assert.equal(isBuildBelowTarget(70, 70), false);
  assert.equal(isBuildBelowTarget(71, 70), false);
  assert.equal(isBuildBelowTarget(0, 70), false);
  assert.equal(isBuildBelowTarget(undefined, 70), false);
  assert.equal(isBuildBelowTarget("69", 70), false);
});

test("resets caps for a new target release", () => {
  const now = Date.UTC(2026, 6, 12, 8);
  assert.equal(
    canSendUrgentUpdateNudge(
      { targetBuild: 69, count: 3, lastSentAtMs: now },
      70,
      now,
      3,
      24 * 60 * 60 * 1000,
    ),
    true,
  );
});

test("enforces cooldown and maximum sends for the same release", () => {
  const day = 24 * 60 * 60 * 1000;
  const now = Date.UTC(2026, 6, 12, 8);
  assert.equal(
    canSendUrgentUpdateNudge(
      { targetBuild: 70, count: 1, lastSentAtMs: now - day + 1 },
      70,
      now,
      3,
      day,
    ),
    false,
  );
  assert.equal(
    canSendUrgentUpdateNudge(
      { targetBuild: 70, count: 1, lastSentAtMs: now - day },
      70,
      now,
      3,
      day,
    ),
    true,
  );
  assert.equal(
    canSendUrgentUpdateNudge({ targetBuild: 70, count: 3 }, 70, now, 3, day),
    false,
  );
});

test("deduplicates legacy and multi-device tokens", () => {
  assert.deepEqual(
    readFcmTokens({
      fcmToken: "token-a",
      fcmTokens: ["token-a", " token-b ", "", null],
    }),
    ["token-a", "token-b"],
  );
});

test("produces compelling compact copy with the target version", () => {
  const copy = urgentUpdateCopy("4.1.6");
  assert.equal(copy.title, "Urgent: update Spaza One today");
  assert.match(copy.body, /Update to 4\.1\.6 now/);
  assert.match(copy.body, /WhatsApp, SMS and conversations/);
});

test("rebrands stale operator-configured copy before sending", () => {
  const copy = urgentUpdateCopy(
    "4.1.6",
    "Urgent: update Pasella today",
    "PASELLA {version} keeps your messages working.",
  );

  assert.equal(copy.title, "Urgent: update Spaza One today");
  assert.equal(copy.body, "Spaza One 4.1.6 keeps your messages working.");
  assert.doesNotMatch(`${copy.title} ${copy.body}`, /pasella/i);
});

test("preserves explicit rebrand-announcement wording", () => {
  const copy = urgentUpdateCopy(
    "4.3.1",
    "Pasella is now SpazaOne 🎉",
    "Same app. Same account. Update to {version}.",
  );

  assert.equal(copy.title, "Pasella is now SpazaOne 🎉");
  assert.equal(copy.body, "Same app. Same account. Update to 4.3.1.");
});

test("rebrands stale tokens even when current branding is also present", () => {
  const copy = urgentUpdateCopy(
    "4.3.1",
    "Pasella users: update Spaza One now",
    "Pasella is now SpazaOne. Open Pasella and update to {version}.",
  );

  assert.equal(copy.title, "Spaza One users: update Spaza One now");
  assert.equal(
    copy.body,
    "Pasella is now SpazaOne. Open Spaza One and update to 4.3.1.",
  );
});
