import { firestore } from "firebase-admin";
import { db, functions } from "../config/main";
import { ensureMerchantOrderingLink } from "../ecommerce/getMerchantOrderingLink";
import { submitWhatsAppTemplateDocument } from "./submitWhatsAppTemplate";
import { assertCallableStoreAccess } from "../stores/storeAccess";

export const PRODUCT_PROMOTION_TEMPLATE_KIND = "product_promotion_v1";
export const PRODUCT_PROMOTION_BODY =
  "Hi {{customerName}}, a fresh offer from {{shopName}} is ready: " +
  "{{productName}} is available for {{productPrice}}. " +
  "Tap below to start your order.";
export const GLOBAL_PRODUCT_PROMOTION_TEMPLATE_ID =
  "system_product_promotion_v1_global";
const PRODUCT_PROMOTION_PROVIDER_NAME = "spazaone_product_promotion_v1";

type EnsureRequest = { retry?: boolean; storeId?: string } | undefined;

function templateDocumentId(merchantId: string): string {
  return `system_product_promotion_v1_${merchantId}`;
}

function merchantApprovalStatus(globalStatus: string): string {
  if (
    globalStatus === "approved" ||
    globalStatus === "rejected" ||
    globalStatus === "submission_failed"
  ) {
    return globalStatus;
  }
  // Merchant bindings deliberately stay out of the scheduled provider-status
  // query. Only the single global document polls Twilio; the status checker
  // fans the result out to every merchant binding once.
  return "system_pending";
}

function configuredProductPromotionContentSid(): string | null {
  const rawValue =
    process.env.PRODUCT_PROMOTION_CONTENT_SID ||
    functions.config().twilio?.product_promotion_content_sid ||
    "";
  const value = String(rawValue).trim();

  if (!value) return null;
  if (!/^HX[0-9a-fA-F]{32}$/.test(value)) {
    throw new functions.https.HttpsError(
      "internal",
      "The shared product promotion template is misconfigured.",
    );
  }
  return value;
}

/**
 * Idempotently prepares one SpazaOne-owned product promotion template and a
 * lightweight merchant binding to it. The app calls this on entry to
 * Marketing and from the product-level Promote action. Meta reviews the global
 * template once; merchants never compose or submit templates themselves.
 */
export const ensureProductPromotionTemplate = functions.https.onCall(
  async (data: EnsureRequest, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in before preparing WhatsApp promotions.",
      );
    }
    const merchantId = String(data?.storeId ?? context.auth.uid).trim();
    await assertCallableStoreAccess(context, merchantId);

    // The card button needs an active shop code. Create it silently when this
    // is the merchant's first WhatsApp selling action.
    await ensureMerchantOrderingLink(merchantId);

    const retry = data?.retry === true;
    const configuredContentSid = configuredProductPromotionContentSid();
    const templateId = templateDocumentId(merchantId);
    const globalRef = db
      .collection("messagingTemplates")
      .doc(GLOBAL_PRODUCT_PROMOTION_TEMPLATE_ID);
    const merchantRef = db.collection("messagingTemplates").doc(templateId);
    let shouldSubmit = false;

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(globalRef);
      const current = snap.data();
      const whatsapp = current?.channels?.whatsapp;
      const status = String(whatsapp?.approvalStatus || "draft").toLowerCase();
      const startedAt = whatsapp?.submissionStartedAt as
        | firestore.Timestamp
        | undefined;
      const leaseIsFresh =
        startedAt != null && Date.now() - startedAt.toMillis() < 5 * 60 * 1000;

      // SpazaOne's shared template was submitted manually in Twilio so its
      // card layout and approval samples could be reviewed before release.
      // Treat the configured Content SID as authoritative and materialize it
      // into Firestore on the first merchant visit. This avoids creating a
      // second provider template while keeping merchant bindings automatic.
      if (configuredContentSid) {
        const alreadyConfigured =
          status === "approved" &&
          whatsapp?.twilioTemplateId === configuredContentSid;
        if (alreadyConfigured) return;

        const now = firestore.FieldValue.serverTimestamp();
        const approvedTemplate = {
          userId: "__pasella_system__",
          name: "Product promotion",
          displayName: "Product promotion",
          systemManaged: true,
          systemScope: "global",
          templateKind: PRODUCT_PROMOTION_TEMPLATE_KIND,
          submissionManagedBy: "product_promotion_provisioner",
          providerNameSeed: PRODUCT_PROMOTION_PROVIDER_NAME,
          updatedAt: now,
          channels: {
            whatsapp: {
              templateContent: PRODUCT_PROMOTION_BODY,
              approvalStatus: "approved",
              approved: true,
              contentType: "twilio/card",
              buttonText: "Order on WhatsApp",
              providerTemplateName: PRODUCT_PROMOTION_PROVIDER_NAME,
              twilioTemplateId: configuredContentSid,
              submissionStartedAt: null,
              submissionError: null,
              rejectionReason: null,
              submittedAt: now,
              configuredAt: now,
            },
          },
        };

        if (snap.exists) {
          tx.set(globalRef, approvedTemplate, { merge: true });
        } else {
          tx.create(globalRef, {
            ...approvedTemplate,
            createdAt: now,
          });
        }
        return;
      }

      if (
        status === "approved" ||
        status === "pending" ||
        status === "submitted"
      ) {
        return;
      }
      if (status === "submitting" && leaseIsFresh) {
        return;
      }
      if ((status === "rejected" || status === "submission_failed") && !retry) {
        return;
      }

      const attempt = Number(current?.submissionAttempt || 0) + 1;
      const now = firestore.FieldValue.serverTimestamp();
      const base = {
        userId: "__pasella_system__",
        name: "Product promotion",
        displayName: "Product promotion",
        systemManaged: true,
        systemScope: "global",
        templateKind: PRODUCT_PROMOTION_TEMPLATE_KIND,
        submissionManagedBy: "product_promotion_provisioner",
        providerNameSeed: `product_promotion_v1_${attempt}`,
        submissionAttempt: attempt,
        updatedAt: now,
        channels: {
          whatsapp: {
            templateContent: PRODUCT_PROMOTION_BODY,
            approvalStatus: "submitting",
            approved: false,
            contentType: "twilio/card",
            buttonText: "Order on WhatsApp",
            submissionStartedAt: now,
            submissionError: null,
            rejectionReason: null,
          },
        },
      };

      if (snap.exists) {
        tx.set(globalRef, base, { merge: true });
      } else {
        tx.create(globalRef, {
          ...base,
          createdAt: now,
        });
      }
      shouldSubmit = true;
    });

    if (shouldSubmit) {
      const snap = await globalRef.get();
      await submitWhatsAppTemplateDocument(
        globalRef,
        snap.data() || {},
        GLOBAL_PRODUCT_PROMOTION_TEMPLATE_ID,
      );
    }

    const latest = await globalRef.get();
    const latestData = latest.data();
    if (!latest.exists || !latestData) {
      throw new functions.https.HttpsError(
        "internal",
        "Spaza One could not prepare the promotion message.",
      );
    }
    const whatsapp = latestData.channels?.whatsapp || {};
    const approvalStatus = merchantApprovalStatus(
      String(whatsapp.approvalStatus || "draft").toLowerCase(),
    );
    const merchantBindingExists = (await merchantRef.get()).exists;
    await merchantRef.set(
      {
        userId: merchantId,
        name: "Product promotion",
        displayName: "Product promotion",
        systemManaged: true,
        systemScope: "merchant_binding",
        systemSourceTemplateId: GLOBAL_PRODUCT_PROMOTION_TEMPLATE_ID,
        submissionManagedBy: "global_product_promotion_binding",
        templateKind: PRODUCT_PROMOTION_TEMPLATE_KIND,
        updatedAt: firestore.FieldValue.serverTimestamp(),
        ...(!merchantBindingExists && {
          createdAt: firestore.FieldValue.serverTimestamp(),
        }),
        channels: {
          whatsapp: {
            ...whatsapp,
            approvalStatus,
            approved: approvalStatus === "approved",
          },
        },
      },
      { merge: true },
    );

    return {
      templateId,
      status: approvalStatus,
      failureReason:
        whatsapp.rejectionReason || whatsapp.submissionError || null,
    };
  },
);
