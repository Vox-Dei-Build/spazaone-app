#!/usr/bin/env node

import process from "node:process";
import { pathToFileURL } from "node:url";
import { applicationDefault, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const DEVELOPMENT_PROJECTS = new Set(["spazaone-dev", "spazaone-dev-za"]);
// The catalogue seed predates merchant-facing share links. Its stable code is
// an intentional bot QA fixture, not an orphan created by the callable.
const DEVELOPMENT_SYNTHETIC_LINKS = new Set(["dev-seed-merchant:U84BCC"]);

function argsMap(argv) {
  const result = new Map();
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (!value.startsWith("--")) continue;
    const [key, inline] = value.slice(2).split("=", 2);
    const next = argv[index + 1];
    if (inline != null) result.set(key, inline);
    else if (next && !next.startsWith("--")) {
      result.set(key, next);
      index += 1;
    } else result.set(key, true);
  }
  return result;
}

export function validateOrderingLinkAuditOptions(argv) {
  const args = argsMap(argv);
  const projectId = String(args.get("project") ?? "").trim();
  const execute = args.get("execute") === true;
  const runId = String(args.get("run-id") ?? "").trim();
  if (!DEVELOPMENT_PROJECTS.has(projectId)) {
    throw new Error("ORDERING_LINK_AUDIT_DEVELOPMENT_PROJECT_REQUIRED");
  }
  if (execute && !/^[A-Za-z0-9:_-]{1,120}$/.test(runId)) {
    throw new Error("ORDERING_LINK_AUDIT_RUN_ID_REQUIRED");
  }
  return {
    projectId,
    execute,
    runId: runId || `ordering-link-audit-dry-${Date.now()}`,
  };
}

function orphanReason(referral, merchant) {
  if (!merchant.exists) return "merchant_missing";
  const binding = `${String(referral.get("merchantId") ?? "").trim()}:${referral.id}`;
  if (DEVELOPMENT_SYNTHETIC_LINKS.has(binding)) return null;
  if (
    referral.get("synthetic") === true &&
    merchant.get("synthetic") === true &&
    merchant.get("whatsappEligibleOverride") === true
  ) {
    return null;
  }
  const ordering = merchant.get("whatsappOrdering");
  if (!ordering || typeof ordering !== "object") return "merchant_link_missing";
  if (ordering.status !== "active") return "merchant_link_inactive";
  if (ordering.code !== referral.id) return "merchant_link_mismatch";
  return null;
}

async function audit(options) {
  initializeApp({
    credential: applicationDefault(),
    projectId: options.projectId,
  });
  const db = getFirestore();
  const referrals = await db
    .collection("merchant_referrals")
    .where("status", "==", "active")
    .get();
  const orderingReferrals = referrals.docs.filter(
    (doc) => doc.get("type") === "whatsapp_ordering",
  );
  const inspected = await Promise.all(
    orderingReferrals.map(async (referral) => {
      const merchantId = String(referral.get("merchantId") ?? "").trim();
      if (!merchantId) {
        return { referral, merchantId, reason: "merchant_id_missing" };
      }
      const merchant = await db.doc(`users/${merchantId}`).get();
      return {
        referral,
        merchantId,
        reason: orphanReason(referral, merchant),
      };
    }),
  );
  const orphans = inspected.filter((item) => item.reason != null);

  if (options.execute) {
    for (const orphan of orphans) {
      await db.runTransaction(async (tx) => {
        const currentReferral = await tx.get(orphan.referral.ref);
        if (
          !currentReferral.exists ||
          currentReferral.get("status") !== "active" ||
          currentReferral.get("type") !== "whatsapp_ordering"
        ) {
          return;
        }
        // Synthetic catalog codes are bound by the seed-run record rather
        // than a merchant-facing share link. Keep them out of repair writes.
        const currentBinding = `${String(
          currentReferral.get("merchantId") ?? "",
        ).trim()}:${currentReferral.id}`;
        if (
          currentReferral.get("synthetic") === true ||
          DEVELOPMENT_SYNTHETIC_LINKS.has(currentBinding)
        ) {
          return;
        }
        const currentMerchantId = String(
          currentReferral.get("merchantId") ?? "",
        ).trim();
        const currentMerchant = currentMerchantId
          ? await tx.get(db.doc(`users/${currentMerchantId}`))
          : null;
        const reason = currentMerchantId
          ? orphanReason(currentReferral, currentMerchant)
          : "merchant_id_missing";
        if (!reason) return;
        tx.set(
          currentReferral.ref,
          {
            status: "revoked",
            revokedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
            repair: {
              reason,
              runId: options.runId,
              repairedAt: FieldValue.serverTimestamp(),
            },
          },
          { merge: true },
        );
      });
    }
  }

  console.log(
    JSON.stringify(
      {
        projectId: options.projectId,
        mode: options.execute ? "execute" : "dry-run",
        runId: options.runId,
        activeOrderingLinks: orderingReferrals.length,
        confirmedOrphans: orphans.length,
        orphans: orphans.map(({ referral, merchantId, reason }) => ({
          code: referral.id,
          merchantId,
          reason,
          useCount: Number(referral.get("useCount") ?? 0),
        })),
      },
      null,
      2,
    ),
  );
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const options = validateOrderingLinkAuditOptions(process.argv.slice(2));
  await audit(options);
}
