import { FieldValue } from "firebase-admin/firestore";
import { db, functions } from "../config/main";
import {
  whatsappCatalogMerchantAllowed,
  whatsappCatalogRuntimeConfig,
} from "./catalogConfig";
import {
  MerchantCatalogDecision,
  buildMerchantCatalogDecision,
} from "./catalogProjection";

export const WHATSAPP_CATALOG_OUTBOX = "whatsappCatalogOutbox";
export const WHATSAPP_CATALOG_MAPPINGS = "whatsappCatalogMappings";

type OutboxDocument = {
  status?: unknown;
  lastErrorCode?: unknown;
  desiredRevision?: unknown;
  processingRevision?: unknown;
  lastAppliedRevision?: unknown;
  batchHandle?: unknown;
};

function decisionFields(decision: MerchantCatalogDecision) {
  return {
    desiredRevision: decision.revision,
    desiredAction: decision.action,
    desiredProjection: decision.projection,
    desiredReasons: decision.reasons,
    desiredPolicyReviewReasons: decision.policyReviewReasons,
  };
}

function providerMayContainItem(
  mapping: FirebaseFirestore.DocumentSnapshot,
  outbox: FirebaseFirestore.DocumentSnapshot,
): boolean {
  const mappingData = mapping.data() ?? {};
  const outboxData = outbox.data() as OutboxDocument | undefined;
  return Boolean(
    mappingData.lastSubmittedRevision ||
      mappingData.lastAppliedRevision ||
      outboxData?.processingRevision ||
      outboxData?.batchHandle,
  );
}

function inFlight(value: OutboxDocument | undefined): boolean {
  return ["processing", "submitted"].includes(String(value?.status ?? ""));
}

/**
 * Re-reads current product state inside the transaction. This makes unordered,
 * at-least-once Firestore events converge on the newest document revision.
 */
export async function enqueueMerchantProductCatalogSync(input: {
  merchantId: string;
  productId: string;
  triggerEventId?: string;
}): Promise<"queued" | "blocked" | "unchanged" | "skipped"> {
  const merchantId = input.merchantId.trim();
  const productId = input.productId.trim();
  if (!merchantId || !productId) return "skipped";
  const productRef = db.doc(`users/${merchantId}/products/${productId}`);

  return db.runTransaction(async (tx) => {
    const [product, merchant] = await Promise.all([
      tx.get(productRef),
      tx.get(db.doc(`users/${merchantId}`)),
    ]);
    const decision = buildMerchantCatalogDecision({
      merchantId,
      productId,
      product: product.exists ? product.data() : undefined,
      merchant: merchant.data(),
    });
    const outboxRef = db.doc(
      `${WHATSAPP_CATALOG_OUTBOX}/${decision.retailerId}`,
    );
    const mappingRef = db.doc(
      `${WHATSAPP_CATALOG_MAPPINGS}/${decision.retailerId}`,
    );
    const [outbox, mapping] = await Promise.all([
      tx.get(outboxRef),
      tx.get(mappingRef),
    ]);
    const outboxValue = outbox.data() as OutboxDocument | undefined;
    const mappingValue = mapping.data();
    const now = FieldValue.serverTimestamp();

    // A prior release rejected valid JPEG bytes when an origin used the
    // common image/jpg alias or a generic binary header. Reconciliation may
    // revalidate only that exact terminal failure; every other unchanged
    // revision remains idempotent and untouched.
    const revalidatableImageHeaderBlock =
      decision.action === "upsert" &&
      outboxValue?.status === "blocked" &&
      outboxValue?.lastErrorCode === "IMAGE_CONTENT_TYPE_UNSUPPORTED" &&
      mappingValue?.status === "blocked" &&
      mappingValue?.lastErrorCode === "IMAGE_CONTENT_TYPE_UNSUPPORTED";

    // A locally ineligible product has no provider mutation and therefore may
    // correctly have no outbox document. Treat its exact terminal mapping as
    // unchanged; otherwise every reconciliation pass rewrites the mapping and
    // makes the production stability barrier impossible to satisfy.
    const unchangedLocalTerminalMapping =
      decision.action === "delete" &&
      !outbox.exists &&
      mappingValue?.desiredRevision === decision.revision &&
      mappingValue?.status === (product.exists ? "blocked" : "deleted") &&
      !providerMayContainItem(mapping, outbox);

    if (!product.exists && !mapping.exists && !outbox.exists) return "skipped";
    if (
      (outboxValue?.desiredRevision === decision.revision &&
        mappingValue?.desiredRevision === decision.revision &&
        !revalidatableImageHeaderBlock) ||
      unchangedLocalTerminalMapping
    ) {
      return "unchanged";
    }

    const shouldDeleteFromProvider =
      decision.action === "delete" && providerMayContainItem(mapping, outbox);
    const shouldQueue =
      decision.action === "upsert" || shouldDeleteFromProvider;
    const mappingStatus = shouldQueue
      ? decision.action === "upsert"
        ? "pending"
        : "pending_delete"
      : product.exists
        ? "blocked"
        : "deleted";
    tx.set(
      mappingRef,
      {
        merchantId,
        productId,
        retailerId: decision.retailerId,
        desiredRevision: decision.revision,
        desiredAction: decision.action,
        eligible: decision.eligible,
        eligibilityReasons: decision.reasons,
        policyReviewReasons: decision.policyReviewReasons,
        popularityScore: decision.projection?.popularityScore ?? 0,
        status: mappingStatus,
        sourcePath: productRef.path,
        schemaVersion: 1,
        updatedAt: now,
        updatedAtMs: Date.now(),
        ...(!mapping.exists ? { createdAt: now } : {}),
      },
      { merge: true },
    );

    if (!shouldQueue) {
      if (outbox.exists && !inFlight(outboxValue)) {
        tx.set(
          outboxRef,
          {
            ...decisionFields(decision),
            status: mappingStatus,
            availableAtMs: 0,
            attempts: 0,
            updatedAt: now,
            updatedAtMs: Date.now(),
          },
          { merge: true },
        );
      }
      return "blocked";
    }

    const desired = {
      merchantId,
      productId,
      retailerId: decision.retailerId,
      ...decisionFields(decision),
      triggerEventId: input.triggerEventId ?? null,
      schemaVersion: 1,
      updatedAt: now,
      updatedAtMs: Date.now(),
      ...(!outbox.exists ? { createdAt: now } : {}),
    };
    if (inFlight(outboxValue)) {
      tx.set(outboxRef, desired, { merge: true });
    } else {
      tx.set(
        outboxRef,
        {
          ...desired,
          status: "pending",
          attempts: 0,
          availableAtMs: 0,
          claimToken: null,
          leaseUntilMs: 0,
          batchHandle: null,
          nextCheckAtMs: 0,
          lastErrorCode: null,
        },
        { merge: true },
      );
    }
    return "queued";
  });
}

export const onMerchantProductCatalogChange = functions
  .runWith({ timeoutSeconds: 30, memory: "256MB", maxInstances: 10 })
  .firestore.document("users/{merchantId}/products/{productId}")
  .onWrite(async (_change, context) => {
    const config = whatsappCatalogRuntimeConfig();
    if (!config.queueEnabled) return null;
    const merchantId = String(context.params.merchantId);
    if (!whatsappCatalogMerchantAllowed(config, merchantId)) return null;
    await enqueueMerchantProductCatalogSync({
      merchantId,
      productId: String(context.params.productId),
      triggerEventId: context.eventId,
    });
    return null;
  });
