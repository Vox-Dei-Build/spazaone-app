#!/usr/bin/env node

"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const {execFileSync} = require("child_process");

const PROJECT_ID = "pasella-ledger";
const DATABASE_ID = "(default)";
const CAMPAIGN_ID = "merchant-r15-messaging-gift-2026-06";
const GIFT_AMOUNT_ZAR = 15;
const WALLET_SIGNUP_WINDOW_MS = 5 * 60 * 1000;
const WALLET_MIGRATION_STARTED_AT = new Date("2025-03-22T18:52:00Z");
const FIRST_CONFIRMED_PRODUCTION_RELEASE_AT =
  new Date("2025-03-27T00:00:00+02:00");

function firebaseToolsModule(modulePath) {
  const globalRoot = execFileSync("npm", ["root", "-g"], {
    encoding: "utf8",
  }).trim();
  return require(path.join(globalRoot, "firebase-tools", "lib", modulePath));
}

function fieldValue(value) {
  if (!value) return null;
  if (Object.prototype.hasOwnProperty.call(value, "doubleValue")) {
    return Number(value.doubleValue);
  }
  if (Object.prototype.hasOwnProperty.call(value, "integerValue")) {
    return Number(value.integerValue);
  }
  if (Object.prototype.hasOwnProperty.call(value, "stringValue")) {
    return value.stringValue;
  }
  if (Object.prototype.hasOwnProperty.call(value, "timestampValue")) {
    return value.timestampValue;
  }
  if (Object.prototype.hasOwnProperty.call(value, "booleanValue")) {
    return value.booleanValue;
  }
  if (Object.prototype.hasOwnProperty.call(value, "arrayValue")) {
    return (value.arrayValue.values || []).map(fieldValue);
  }
  return null;
}

function hasPushToken(fields) {
  return ["fcmToken", "fcmTokens", "pushToken", "deviceToken"].some(
    (key) => {
      const value = fieldValue(fields[key]);
      return Array.isArray(value) ? value.length > 0 : Boolean(value);
    },
  );
}

function parseArgs() {
  const outputArg = process.argv.find((arg) => arg.startsWith("--output="));
  const defaultName =
    `pasella-${CAMPAIGN_ID}-dry-run-${new Date().toISOString()
      .replace(/[:.]/g, "-")}.json`;
  return {
    outputPath: outputArg ?
      path.resolve(outputArg.slice("--output=".length)) :
      path.join(os.tmpdir(), defaultName),
  };
}

async function firebaseAccessToken() {
  const api = firebaseToolsModule("apiv2.js");
  const {configstore} = firebaseToolsModule("configstore.js");
  const refreshToken = configstore.get("tokens")?.refresh_token;
  if (!refreshToken) {
    throw new Error(
      "Firebase CLI is not authenticated. Run `firebase login` first.",
    );
  }
  api.setRefreshToken(refreshToken);
  return api.getAccessToken();
}

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  const body = await response.json();
  if (!response.ok) {
    throw new Error(
      `Firestore request failed (${response.status}): ${JSON.stringify(body)}`,
    );
  }
  return body;
}

async function listUsers(headers) {
  const users = [];
  let pageToken = "";

  do {
    const url = new URL(
      `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}` +
      `/databases/${encodeURIComponent(DATABASE_ID)}/documents/users`,
    );
    url.searchParams.set("pageSize", "1000");
    if (pageToken) url.searchParams.set("pageToken", pageToken);

    const body = await fetchJson(url, {headers});
    users.push(...(body.documents || []));
    pageToken = body.nextPageToken || "";
  } while (pageToken);

  return users;
}

async function fetchWallets(users, headers) {
  const wallets = new Map();
  const endpoint =
    `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}` +
    `/databases/${encodeURIComponent(DATABASE_ID)}/documents:batchGet`;

  for (let offset = 0; offset < users.length; offset += 100) {
    const documents = users.slice(offset, offset + 100)
      .map((user) => `${user.name}/wallet/current`);
    const rows = await fetchJson(endpoint, {
      method: "POST",
      headers,
      body: JSON.stringify({documents}),
    });

    for (const row of rows) {
      if (row.found) wallets.set(row.found.name, row.found);
      if (row.missing) wallets.set(row.missing, null);
    }
  }

  return wallets;
}

function classifyUser(user, wallet) {
  const fields = user.fields || {};
  const walletFields = wallet?.fields || {};
  const userCreatedAt = new Date(user.createTime);
  const walletCreatedAt = wallet ? new Date(wallet.createTime) : null;
  const walletCreatedWithAccount = walletCreatedAt ?
    Math.abs(walletCreatedAt - userCreatedAt) <= WALLET_SIGNUP_WINDOW_MS :
    false;
  const createdAfterConfirmedRelease =
    userCreatedAt >= FIRST_CONFIRMED_PRODUCTION_RELEASE_AT;
  const migratedLegacyWallet = walletCreatedAt ?
    walletCreatedAt >= WALLET_MIGRATION_STARTED_AT &&
      !walletCreatedWithAccount &&
      userCreatedAt < FIRST_CONFIRMED_PRODUCTION_RELEASE_AT :
    false;
  const walletBalance = wallet ?
    fieldValue(walletFields.virtualBalance) :
    null;
  const receivedSignupGift =
    walletCreatedWithAccount && walletBalance === GIFT_AMOUNT_ZAR;

  let eligible = false;
  let reason;

  if (receivedSignupGift) {
    reason = "wallet_created_at_signup_with_r15";
  } else if (createdAfterConfirmedRelease) {
    reason = "account_created_after_signup_gift_release";
  } else if (migratedLegacyWallet) {
    eligible = true;
    reason = "legacy_wallet_bulk_migrated_without_signup_gift";
  } else if (!wallet) {
    eligible = true;
    reason = "legacy_account_missing_wallet";
  } else {
    reason = "manual_review_unclassified_wallet_history";
  }

  return {
    uid: user.name.split("/").pop(),
    merchantName: fieldValue(fields.name),
    shopName: fieldValue(fields.shopName),
    mobileNumber: fieldValue(fields.mobileNumber),
    userCreatedAt: user.createTime,
    walletCreatedAt: wallet?.createTime || null,
    walletBalance,
    hasPushToken: hasPushToken(fields),
    profileComplete: Boolean(
      fieldValue(fields.mobileNumber) &&
      fieldValue(fields.shopName),
    ),
    eligible,
    reason,
  };
}

async function main() {
  const {outputPath} = parseArgs();
  const token = await firebaseAccessToken();
  const headers = {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };
  const users = await listUsers(headers);
  const wallets = await fetchWallets(users, headers);
  const classified = users.map((user) =>
    classifyUser(user, wallets.get(`${user.name}/wallet/current`)),
  );
  const recipients = classified
    .filter((user) => user.eligible)
    .sort((a, b) => a.userCreatedAt.localeCompare(b.userCreatedAt));
  const excluded = classified
    .filter((user) => !user.eligible)
    .sort((a, b) => a.userCreatedAt.localeCompare(b.userCreatedAt));
  const manualReview = excluded.filter((user) =>
    user.reason === "manual_review_unclassified_wallet_history",
  );

  const manifest = {
    metadata: {
      campaignId: CAMPAIGN_ID,
      generatedAt: new Date().toISOString(),
      projectId: PROJECT_ID,
      giftAmountZar: GIFT_AMOUNT_ZAR,
      noWritesPerformed: true,
      eligibility:
        "Legacy accounts whose wallet was bulk-migrated rather than " +
        "created at signup, plus legacy accounts with no wallet.",
      exclusion:
        "Accounts with an R15 wallet created at signup, and accounts " +
        "created after the first confirmed production release.",
    },
    summary: {
      usersReviewed: classified.length,
      eligibleRecipients: recipients.length,
      excludedRecipients: excluded.length,
      manualReviewRequired: manualReview.length,
      pushReachable: recipients.filter((user) => user.hasPushToken).length,
      noPushToken: recipients.filter((user) => !user.hasPushToken).length,
      completeProfiles: recipients.filter((user) => user.profileComplete)
        .length,
      incompleteProfiles: recipients.filter((user) => !user.profileComplete)
        .length,
      walletsToIncrement: recipients.filter((user) =>
        user.walletCreatedAt !== null,
      ).length,
      walletsToCreate: recipients.filter((user) =>
        user.walletCreatedAt === null,
      ).length,
      totalGiftLiabilityZar: recipients.length * GIFT_AMOUNT_ZAR,
    },
    recipients,
    excluded,
  };

  fs.mkdirSync(path.dirname(outputPath), {recursive: true});
  fs.writeFileSync(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, {
    mode: 0o600,
  });

  console.log(JSON.stringify({
    outputPath,
    ...manifest.summary,
    noWritesPerformed: true,
  }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
