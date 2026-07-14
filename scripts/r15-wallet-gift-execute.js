#!/usr/bin/env node

"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const {execFileSync} = require("child_process");

const PROJECT_ID = "pasella-ledger";
const DATABASE_ID = "(default)";
const CAMPAIGN_ID = "merchant-r15-messaging-gift-2026-06";
const GIFT_AMOUNT_ZAR = 15;
const EXPECTED_RECIPIENTS = 149;
const EXPECTED_LIABILITY_ZAR = 2235;
const EXPECTED_MANIFEST_DIGEST =
  "c6c2d711c9ae021e533fb00705fc0d72651440861eaab219c3b9844cc50b6e90";
const PUSH_TITLE = "R15 added to your SpazaOne wallet";
const PUSH_BODY =
  "We’ve added R15 for messaging customers. Open SpazaOne to use it.";
const WALLET_ROUTE = "/walletPage";
const MAX_TRANSACTION_ATTEMPTS = 5;

function parseArgs() {
  const manifestArg = process.argv.find((arg) =>
    arg.startsWith("--manifest="),
  );
  return {
    commit: process.argv.includes("--commit"),
    manifestPath: manifestArg ?
      path.resolve(manifestArg.slice("--manifest=".length)) :
      null,
    skipPush: process.argv.includes("--skip-push"),
  };
}

function firebaseToolsModule(modulePath) {
  const globalRoot = execFileSync("npm", ["root", "-g"], {
    encoding: "utf8",
  }).trim();
  return require(path.join(globalRoot, "firebase-tools", "lib", modulePath));
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

function manifestDigest(manifest) {
  const payload = {
    campaignId: manifest.metadata?.campaignId,
    giftAmountZar: manifest.metadata?.giftAmountZar,
    summary: manifest.summary,
    recipients: manifest.recipients
      .map((recipient) => ({
        uid: recipient.uid,
        userCreatedAt: recipient.userCreatedAt,
        walletCreatedAt: recipient.walletCreatedAt,
        walletBalance: recipient.walletBalance,
        reason: recipient.reason,
      }))
      .sort((a, b) => a.uid.localeCompare(b.uid)),
  };
  return crypto
    .createHash("sha256")
    .update(JSON.stringify(payload))
    .digest("hex");
}

function validateManifest(manifest) {
  const recipients = manifest.recipients || [];
  const uniqueUids = new Set(recipients.map((recipient) => recipient.uid));
  const digest = manifestDigest(manifest);
  const errors = [];

  if (manifest.metadata?.campaignId !== CAMPAIGN_ID) {
    errors.push(`campaignId must be ${CAMPAIGN_ID}`);
  }
  if (manifest.metadata?.giftAmountZar !== GIFT_AMOUNT_ZAR) {
    errors.push(`gift amount must be R${GIFT_AMOUNT_ZAR}`);
  }
  if (recipients.length !== EXPECTED_RECIPIENTS) {
    errors.push(`recipient count must be ${EXPECTED_RECIPIENTS}`);
  }
  if (uniqueUids.size !== recipients.length) {
    errors.push("recipient UIDs are not unique");
  }
  if (manifest.summary?.manualReviewRequired !== 0) {
    errors.push("manifest still contains manual-review recipients");
  }
  if (manifest.summary?.totalGiftLiabilityZar !== EXPECTED_LIABILITY_ZAR) {
    errors.push(`liability must be R${EXPECTED_LIABILITY_ZAR}`);
  }
  if (digest !== EXPECTED_MANIFEST_DIGEST) {
    errors.push(`manifest digest mismatch: ${digest}`);
  }
  if (recipients.some((recipient) => recipient.eligible !== true)) {
    errors.push("manifest contains an ineligible recipient");
  }

  if (errors.length) {
    throw new Error(`Manifest validation failed:\n- ${errors.join("\n- ")}`);
  }

  return digest;
}

function documentName(relativePath) {
  return `projects/${PROJECT_ID}/databases/${DATABASE_ID}/documents/` +
    relativePath;
}

function documentsUrl(suffix = "") {
  return `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}` +
    `/databases/${encodeURIComponent(DATABASE_ID)}/documents${suffix}`;
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, options);
  const text = await response.text();
  const body = text ? JSON.parse(text) : {};
  if (!response.ok) {
    const error = new Error(
      `${options.method || "GET"} ${url} failed (${response.status}): ` +
      JSON.stringify(body),
    );
    error.status = response.status;
    error.body = body;
    throw error;
  }
  return body;
}

function valueOf(value) {
  if (!value) return null;
  if ("nullValue" in value) return null;
  if ("booleanValue" in value) return value.booleanValue;
  if ("integerValue" in value) return Number(value.integerValue);
  if ("doubleValue" in value) return Number(value.doubleValue);
  if ("timestampValue" in value) return value.timestampValue;
  if ("stringValue" in value) return value.stringValue;
  if ("arrayValue" in value) {
    return (value.arrayValue.values || []).map(valueOf);
  }
  if ("mapValue" in value) {
    return Object.fromEntries(
      Object.entries(value.mapValue.fields || {}).map(([key, child]) =>
        [key, valueOf(child)],
      ),
    );
  }
  return null;
}

function fieldsToObject(fields = {}) {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, valueOf(value)]),
  );
}

function firestoreValue(value) {
  if (value === null || value === undefined) {
    return {nullValue: null};
  }
  if (typeof value === "boolean") return {booleanValue: value};
  if (typeof value === "number") return {doubleValue: value};
  if (typeof value === "string") return {stringValue: value};
  if (Array.isArray(value)) {
    return {arrayValue: {values: value.map(firestoreValue)}};
  }
  if (value instanceof Date) {
    return {timestampValue: value.toISOString()};
  }
  if (typeof value === "object") {
    return {
      mapValue: {
        fields: Object.fromEntries(
          Object.entries(value).map(([key, child]) =>
            [key, firestoreValue(child)],
          ),
        ),
      },
    };
  }
  throw new Error(`Unsupported Firestore value type: ${typeof value}`);
}

function objectToFields(object) {
  return Object.fromEntries(
    Object.entries(object).map(([key, value]) =>
      [key, firestoreValue(value)],
    ),
  );
}

async function beginTransaction(headers) {
  const body = await requestJson(documentsUrl(":beginTransaction"), {
    method: "POST",
    headers,
    body: JSON.stringify({
      options: {readWrite: {}},
    }),
  });
  return body.transaction;
}

async function rollbackTransaction(headers, transaction) {
  await requestJson(documentsUrl(":rollback"), {
    method: "POST",
    headers,
    body: JSON.stringify({transaction}),
  });
}

async function transactionBatchGet(headers, transaction, names) {
  const rows = await requestJson(documentsUrl(":batchGet"), {
    method: "POST",
    headers,
    body: JSON.stringify({documents: names, transaction}),
  });
  const results = new Map();
  for (const row of rows) {
    if (row.found) results.set(row.found.name, row.found);
    if (row.missing) results.set(row.missing, null);
  }
  return results;
}

function defaultWalletFields(balance) {
  return objectToFields({
    virtualBalance: balance,
    cashAdvanceBalance: 0,
    salesVirtualBalance: 0,
    cashAdvanceWithdrawn: 0,
    cashAdvanceDueDate: null,
    penaltyFee: 0,
    accountSuspended: false,
    totalCashAdvanceGiven: 0,
    totalCashAdvanceRepaid: 0,
    repaymentHistory: [{
      date: new Date().toISOString(),
      amount: 0,
      method: "N/A",
      status: "N/A",
      reference: "N/A",
    }],
  });
}

function creditWrites(recipient, walletDoc, markerName) {
  const creditedAt = new Date();
  const previousBalance = walletDoc ?
    Number(valueOf(walletDoc.fields?.virtualBalance) || 0) :
    0;
  const newBalance = previousBalance + GIFT_AMOUNT_ZAR;
  const walletName = documentName(`users/${recipient.uid}/wallet/current`);
  const pushStatus = recipient.hasPushToken ? "pending" : "no_tokens";

  const walletWrite = walletDoc ? {
    update: {
      name: walletName,
      fields: {
        virtualBalance: firestoreValue(newBalance),
      },
    },
    updateMask: {fieldPaths: ["virtualBalance"]},
    currentDocument: {exists: true},
  } : {
    update: {
      name: walletName,
      fields: defaultWalletFields(newBalance),
    },
    currentDocument: {exists: false},
  };

  const markerWrite = {
    update: {
      name: markerName,
      fields: objectToFields({
        campaignId: CAMPAIGN_ID,
        uid: recipient.uid,
        amountZar: GIFT_AMOUNT_ZAR,
        previousBalance,
        newBalance,
        eligibilityReason: recipient.reason,
        walletCreated: !walletDoc,
        creditedAt,
        pushStatus,
        manifestDigest: EXPECTED_MANIFEST_DIGEST,
      }),
    },
    currentDocument: {exists: false},
  };

  return {writes: [walletWrite, markerWrite], previousBalance, newBalance};
}

function isRetryableTransactionError(error) {
  const status = String(error.body?.error?.status || "");
  return status === "ABORTED" || status === "FAILED_PRECONDITION";
}

async function creditRecipient(headers, recipient) {
  const walletName = documentName(`users/${recipient.uid}/wallet/current`);
  const markerName = documentName(
    `adminCampaigns/${CAMPAIGN_ID}/recipients/${recipient.uid}`,
  );

  for (let attempt = 1; attempt <= MAX_TRANSACTION_ATTEMPTS; attempt++) {
    const transaction = await beginTransaction(headers);
    try {
      const docs = await transactionBatchGet(
        headers,
        transaction,
        [walletName, markerName],
      );
      const markerDoc = docs.get(markerName);
      if (markerDoc) {
        await rollbackTransaction(headers, transaction);
        return {
          status: "already_credited",
          marker: fieldsToObject(markerDoc.fields),
        };
      }

      const walletDoc = docs.get(walletName);
      const credit = creditWrites(
        recipient,
        walletDoc,
        markerName,
      );
      await requestJson(documentsUrl(":commit"), {
        method: "POST",
        headers,
        body: JSON.stringify({
          transaction,
          writes: credit.writes,
        }),
      });
      return {
        status: "credited",
        previousBalance: credit.previousBalance,
        newBalance: credit.newBalance,
        walletCreated: !walletDoc,
      };
    } catch (error) {
      try {
        await rollbackTransaction(headers, transaction);
      } catch (_) {
        // The transaction may already have been committed or aborted.
      }
      if (
        attempt < MAX_TRANSACTION_ATTEMPTS &&
        isRetryableTransactionError(error)
      ) {
        await new Promise((resolve) => setTimeout(resolve, attempt * 250));
        continue;
      }
      throw error;
    }
  }
  throw new Error(`Transaction attempts exhausted for ${recipient.uid}`);
}

async function batchGetDocuments(headers, names) {
  const result = new Map();
  for (let offset = 0; offset < names.length; offset += 100) {
    const rows = await requestJson(documentsUrl(":batchGet"), {
      method: "POST",
      headers,
      body: JSON.stringify({documents: names.slice(offset, offset + 100)}),
    });
    for (const row of rows) {
      if (row.found) result.set(row.found.name, row.found);
      if (row.missing) result.set(row.missing, null);
    }
  }
  return result;
}

function readPushTokens(userDoc) {
  if (!userDoc) return [];
  const user = fieldsToObject(userDoc.fields);
  const tokens = new Set();
  for (const field of ["fcmTokens", "fcmToken", "pushToken", "deviceToken"]) {
    const value = user[field];
    if (Array.isArray(value)) {
      for (const token of value) {
        if (token) tokens.add(String(token));
      }
    } else if (value) {
      tokens.add(String(value));
    }
  }
  return [...tokens];
}

async function patchMarker(headers, uid, fields) {
  const url = new URL(
    documentsUrl(
      `/adminCampaigns/${CAMPAIGN_ID}/recipients/${uid}`,
    ),
  );
  for (const fieldPath of Object.keys(fields)) {
    url.searchParams.append("updateMask.fieldPaths", fieldPath);
  }
  url.searchParams.set("currentDocument.exists", "true");
  return requestJson(url.toString(), {
    method: "PATCH",
    headers,
    body: JSON.stringify({fields: objectToFields(fields)}),
  });
}

async function sendFcm(headers, token, uid) {
  const url =
    `https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send`;
  return requestJson(url, {
    method: "POST",
    headers,
    body: JSON.stringify({
      message: {
        token,
        notification: {
          title: PUSH_TITLE,
          body: PUSH_BODY,
        },
        android: {
          priority: "HIGH",
          notification: {
            channel_id: "default_channel",
            sound: "default",
          },
        },
        data: {
          type: "WALLET_GIFT",
          route: WALLET_ROUTE,
          amountZar: String(GIFT_AMOUNT_ZAR),
          campaignId: CAMPAIGN_ID,
          merchantId: uid,
          source: "r15-wallet-gift-execute",
        },
      },
    }),
  });
}

function fcmErrorCode(error) {
  return String(
    error.body?.error?.details?.find((detail) => detail.errorCode)
      ?.errorCode ||
    error.body?.error?.status ||
    error.status ||
    "UNKNOWN",
  );
}

async function notifyRecipient(headers, recipient, userDoc, markerDoc) {
  const marker = fieldsToObject(markerDoc?.fields);
  if (!markerDoc) return {status: "missing_credit_marker"};
  if (["sent", "no_tokens", "sending"].includes(marker.pushStatus)) {
    return {status: `already_${marker.pushStatus}`};
  }

  const tokens = readPushTokens(userDoc);
  if (!tokens.length) {
    await patchMarker(headers, recipient.uid, {
      pushStatus: "no_tokens",
      pushTokenCount: 0,
      pushCompletedAt: new Date(),
    });
    return {status: "no_tokens"};
  }

  await patchMarker(headers, recipient.uid, {
    pushStatus: "sending",
    pushAttemptedAt: new Date(),
    pushTokenCount: tokens.length,
  });

  let successCount = 0;
  const errorCodes = [];
  for (const token of tokens) {
    try {
      await sendFcm(headers, token, recipient.uid);
      successCount++;
    } catch (error) {
      errorCodes.push(fcmErrorCode(error));
    }
  }

  const status = successCount > 0 ? "sent" : "failed";
  await patchMarker(headers, recipient.uid, {
    pushStatus: status,
    pushSuccessCount: successCount,
    pushFailureCount: tokens.length - successCount,
    pushErrorCodes: [...new Set(errorCodes)].slice(0, 10),
    pushCompletedAt: new Date(),
  });
  return {
    status,
    successCount,
    failureCount: tokens.length - successCount,
  };
}

async function writeCampaignSummary(headers, summary) {
  const url = new URL(documentsUrl(`/adminCampaigns/${CAMPAIGN_ID}`));
  return requestJson(url.toString(), {
    method: "PATCH",
    headers,
    body: JSON.stringify({
      fields: objectToFields({
        campaignId: CAMPAIGN_ID,
        amountPerMerchantZar: GIFT_AMOUNT_ZAR,
        expectedRecipients: EXPECTED_RECIPIENTS,
        expectedLiabilityZar: EXPECTED_LIABILITY_ZAR,
        manifestDigest: EXPECTED_MANIFEST_DIGEST,
        updatedAt: new Date(),
        ...summary,
      }),
    }),
  });
}

function incrementCount(counts, status) {
  counts[status] = (counts[status] || 0) + 1;
}

async function main() {
  const args = parseArgs();
  if (!args.manifestPath) {
    throw new Error("Required argument: --manifest=/absolute/path/to/file");
  }
  const manifest = JSON.parse(fs.readFileSync(args.manifestPath, "utf8"));
  const digest = validateManifest(manifest);

  console.log(JSON.stringify({
    mode: args.commit ? "commit" : "preflight",
    projectId: PROJECT_ID,
    campaignId: CAMPAIGN_ID,
    manifestDigest: digest,
    recipients: manifest.recipients.length,
    liabilityZar: EXPECTED_LIABILITY_ZAR,
    pushReachableAtDryRun: manifest.summary.pushReachable,
  }, null, 2));

  if (!args.commit) {
    console.log("Preflight passed. No writes performed.");
    return;
  }

  const token = await firebaseAccessToken();
  const headers = {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };

  const creditCounts = {};
  const creditFailures = [];
  for (let index = 0; index < manifest.recipients.length; index++) {
    const recipient = manifest.recipients[index];
    try {
      const result = await creditRecipient(headers, recipient);
      incrementCount(creditCounts, result.status);
    } catch (error) {
      creditFailures.push({
        uid: recipient.uid,
        error: String(error.message || error),
      });
    }
    if ((index + 1) % 25 === 0 || index + 1 === manifest.recipients.length) {
      console.log(
        `Wallet phase: ${index + 1}/${manifest.recipients.length}`,
      );
    }
  }

  const pushCounts = {};
  const pushFailures = [];
  if (!args.skipPush) {
    const userNames = manifest.recipients.map((recipient) =>
      documentName(`users/${recipient.uid}`),
    );
    const markerNames = manifest.recipients.map((recipient) =>
      documentName(
        `adminCampaigns/${CAMPAIGN_ID}/recipients/${recipient.uid}`,
      ),
    );
    const [users, markers] = await Promise.all([
      batchGetDocuments(headers, userNames),
      batchGetDocuments(headers, markerNames),
    ]);

    for (let index = 0; index < manifest.recipients.length; index++) {
      const recipient = manifest.recipients[index];
      try {
        const result = await notifyRecipient(
          headers,
          recipient,
          users.get(documentName(`users/${recipient.uid}`)),
          markers.get(documentName(
            `adminCampaigns/${CAMPAIGN_ID}/recipients/${recipient.uid}`,
          )),
        );
        incrementCount(pushCounts, result.status);
      } catch (error) {
        pushFailures.push({
          uid: recipient.uid,
          error: String(error.message || error),
        });
      }
      if (
        (index + 1) % 25 === 0 ||
        index + 1 === manifest.recipients.length
      ) {
        console.log(
          `Push phase: ${index + 1}/${manifest.recipients.length}`,
        );
      }
    }
  }

  const summary = {
    creditCounts,
    creditFailureCount: creditFailures.length,
    pushCounts,
    pushFailureCount: pushFailures.length,
    completedAt: new Date(),
  };
  await writeCampaignSummary(headers, summary);

  console.log(JSON.stringify({
    ...summary,
    creditFailures,
    pushFailures,
  }, null, 2));

  if (creditFailures.length || pushFailures.length) {
    process.exitCode = 2;
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
