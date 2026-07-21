#!/usr/bin/env node

import {readFile} from "node:fs/promises";
import process from "node:process";
import {applicationDefault, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";

const args = new Map();
for (let index = 2; index < process.argv.length; index += 1) {
  const value = process.argv[index];
  if (!value.startsWith("--")) continue;
  const [key, inline] = value.slice(2).split("=", 2);
  const next = process.argv[index + 1];
  if (inline != null) args.set(key, inline);
  else if (next && !next.startsWith("--")) {
    args.set(key, next);
    index += 1;
  } else args.set(key, true);
}

const projectId = String(args.get("project") ?? "").trim();
const productionProject = "pasella-ledger";
if (!projectId) throw new Error("Pass --project <firebase-project>.");
if (
  projectId === productionProject &&
  process.env.MULTISTORE_PRODUCTION_CONFIRM !== productionProject
) {
  throw new Error(
    "Production smoke blocked. Set MULTISTORE_PRODUCTION_CONFIRM=pasella-ledger.",
  );
}

const googleServicesPath = new URL(
  "../../android/app/google-services.json",
  import.meta.url,
);
const googleServices = JSON.parse(await readFile(googleServicesPath, "utf8"));
const androidClient = googleServices.client.find(
  (client) =>
    client.client_info?.android_client_info?.package_name ===
    "com.tsepo.pasella",
);
const apiKey = androidClient?.api_key?.[0]?.current_key;
const bucketName = googleServices.project_info?.storage_bucket;
if (!apiKey || !bucketName) {
  throw new Error("Android Firebase configuration is incomplete.");
}

const app = initializeApp({
  projectId,
  credential: applicationDefault(),
  storageBucket: bucketName,
  serviceAccountId: `${projectId}@appspot.gserviceaccount.com`,
});
const auth = getAuth(app);
const db = getFirestore(app);
const bucket = getStorage(app).bucket();
const suffix = Date.now().toString(36);
const uid = `rules-smoke-${suffix}`;
const otherStoreId = `rules-smoke-other-${suffix}`;
const ownUpload = `whatsapp_media/${uid}/rules-smoke.txt`;
const legacyUpload = `whatsapp_media/rules-smoke-${suffix}.txt`;
const deniedUpload = `whatsapp_media/${otherStoreId}/rules-smoke.txt`;
const results = [];

function record(name, actual, expected) {
  results.push({name, actual, expected, passed: actual === expected});
}

async function request(name, url, options, expected) {
  const response = await fetch(url, options);
  record(name, response.status, expected);
  // Consume the response without printing production document contents.
  await response.arrayBuffer();
}

function documentUrl(path) {
  return `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path}`;
}

function authHeaders(idToken, contentType = "application/json") {
  return {
    authorization: `Bearer ${idToken}`,
    "content-type": contentType,
  };
}

try {
  await auth.createUser({uid, displayName: "Rules smoke test"});
  const now = Timestamp.now();
  const batch = db.batch();
  batch.set(db.doc(`users/${uid}`), {
    name: "Rules smoke test",
    shopName: "Rules smoke store",
  });
  batch.set(db.doc(`users/${uid}/customers/customer-1`), {
    name: "Rules smoke customer",
    balance: -1,
  });
  batch.set(
    db.doc(`users/${uid}/customers/customer-1/transactions/transaction-1`),
    {amount: 1, date: now, type: "Credit", status: "DUE"},
  );
  batch.set(db.doc(`stores/${uid}`), {
    name: "Rules smoke store",
    ownerUid: uid,
    status: "active",
    schemaVersion: 2,
  });
  const membership = {
    storeId: uid,
    uid,
    role: "owner",
    status: "active",
    storeName: "Rules smoke store",
  };
  batch.set(db.doc(`stores/${uid}/operators/${uid}`), membership);
  batch.set(db.doc(`operators/${uid}/stores/${uid}`), membership);
  batch.set(db.doc(`users/${otherStoreId}`), {
    name: "Other rules smoke store",
  });
  batch.set(db.doc(`users/${otherStoreId}/customers/customer-1`), {
    name: "Denied rules smoke customer",
  });
  await batch.commit();

  const customToken = await auth.createCustomToken(uid);
  const tokenResponse = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${encodeURIComponent(apiKey)}`,
    {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({token: customToken, returnSecureToken: true}),
    },
  );
  const tokenBody = await tokenResponse.json();
  if (!tokenResponse.ok || !tokenBody.idToken) {
    throw new Error(
      `Could not exchange the temporary custom token (${tokenResponse.status}: ${String(tokenBody.error?.message ?? "unknown")}).`,
    );
  }
  const idToken = tokenBody.idToken;

  await request(
    "unauthenticated nested read denied",
    documentUrl(`users/${uid}/customers/customer-1`),
    {},
    403,
  );
  await request(
    "legacy owner nested read allowed",
    documentUrl(`users/${uid}/customers/customer-1`),
    {headers: authHeaders(idToken)},
    200,
  );
  await request(
    "cross-store nested read denied",
    documentUrl(`users/${otherStoreId}/customers/customer-1`),
    {headers: authHeaders(idToken)},
    403,
  );
  await request(
    "transitional root profile read allowed",
    documentUrl(`users/${otherStoreId}`),
    {},
    200,
  );
  await request(
    "own membership read allowed",
    documentUrl(`operators/${uid}/stores/${uid}`),
    {headers: authHeaders(idToken)},
    200,
  );

  await request(
    "legacy owner nested write allowed",
    documentUrl(`users/${uid}/customers/customer-1/transactions/client-write`),
    {
      method: "PATCH",
      headers: authHeaders(idToken),
      body: JSON.stringify({
        fields: {
          amount: {integerValue: "1"},
          type: {stringValue: "Payment"},
          status: {stringValue: "PAID"},
          date: {timestampValue: new Date().toISOString()},
        },
      }),
    },
    200,
  );
  await request(
    "cross-store nested write denied",
    documentUrl(
      `users/${otherStoreId}/customers/customer-1/transactions/client-write`,
    ),
    {
      method: "PATCH",
      headers: authHeaders(idToken),
      body: JSON.stringify({fields: {amount: {integerValue: "1"}}}),
    },
    403,
  );

  const start = new Date(now.toMillis() - 60_000).toISOString();
  const end = new Date(now.toMillis() + 60_000).toISOString();
  await request(
    "released-app transaction collection-group query allowed",
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:runQuery`,
    {
      method: "POST",
      headers: authHeaders(idToken),
      body: JSON.stringify({
        structuredQuery: {
          from: [{collectionId: "transactions", allDescendants: true}],
          where: {
            compositeFilter: {
              op: "AND",
              filters: [
                {
                  fieldFilter: {
                    field: {fieldPath: "date"},
                    op: "GREATER_THAN_OR_EQUAL",
                    value: {timestampValue: start},
                  },
                },
                {
                  fieldFilter: {
                    field: {fieldPath: "date"},
                    op: "LESS_THAN_OR_EQUAL",
                    value: {timestampValue: end},
                  },
                },
                {
                  fieldFilter: {
                    field: {fieldPath: "type"},
                    op: "EQUAL",
                    value: {stringValue: "Credit"},
                  },
                },
                {
                  fieldFilter: {
                    field: {fieldPath: "status"},
                    op: "EQUAL",
                    value: {stringValue: "DUE"},
                  },
                },
              ],
            },
          },
          limit: 1,
        },
      }),
    },
    200,
  );

  async function upload(name, objectName, expected) {
    const url = new URL(
      `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o`,
    );
    url.searchParams.set("uploadType", "media");
    url.searchParams.set("name", objectName);
    await request(
      name,
      url,
      {
        method: "POST",
        headers: authHeaders(idToken, "text/plain"),
        body: "rules smoke test",
      },
      expected,
    );
  }

  await upload("store-scoped upload allowed", ownUpload, 200);
  await upload("released-app legacy upload allowed", legacyUpload, 200);
  await upload("cross-store upload denied", deniedUpload, 403);

  const failed = results.filter((result) => !result.passed);
  console.log(
    JSON.stringify({
      projectId,
      passed: results.length - failed.length,
      total: results.length,
      failures: failed,
    }),
  );
  if (failed.length) process.exitCode = 1;
} finally {
  const cleanupBatch = db.batch();
  for (const path of [
    `users/${uid}/customers/customer-1/transactions/transaction-1`,
    `users/${uid}/customers/customer-1/transactions/client-write`,
    `users/${uid}/customers/customer-1`,
    `users/${uid}`,
    `users/${otherStoreId}/customers/customer-1/transactions/client-write`,
    `users/${otherStoreId}/customers/customer-1`,
    `users/${otherStoreId}`,
    `stores/${uid}/operators/${uid}`,
    `stores/${uid}`,
    `operators/${uid}/stores/${uid}`,
    `operators/${uid}`,
  ]) {
    cleanupBatch.delete(db.doc(path));
  }
  const cleanupTasks = [
    () => auth.deleteUser(uid),
    () => cleanupBatch.commit(),
    () => bucket.file(ownUpload).delete({ignoreNotFound: true}),
    () => bucket.file(legacyUpload).delete({ignoreNotFound: true}),
    () => bucket.file(deniedUpload).delete({ignoreNotFound: true}),
  ];
  let cleanupFailures = 0;
  for (const cleanupTask of cleanupTasks) {
    try {
      await cleanupTask();
    } catch {
      cleanupFailures += 1;
    }
  }
  // Auth provisioning can finish after the initial batch. Sweep the isolated
  // roots once more after deleting the temporary Auth user.
  await new Promise((resolve) => setTimeout(resolve, 2_000));
  for (const path of [
    `users/${uid}`,
    `users/${otherStoreId}`,
    `stores/${uid}`,
    `operators/${uid}`,
  ]) {
    try {
      await db.recursiveDelete(db.doc(path), db.bulkWriter());
    } catch {
      cleanupFailures += 1;
    }
  }
  if (cleanupFailures) {
    console.error(`Rules smoke cleanup failures: ${cleanupFailures}`);
    process.exitCode = 1;
  }
}
