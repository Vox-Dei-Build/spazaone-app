import { db, functions } from "../config/main"; // Firebase or GCP cloud function import
import moment from "moment"; // To calculate dates
import { formatPhoneNumber, normalizePhoneNumber } from "../utils/phoneUtils";
import { fetchWhatsAppCapability } from "../utils/whatsappCapability";
import {
  calculateSmsSegments,
  DEFAULT_CATALOG_EMPTY_SMS,
  DEFAULT_CATALOG_READY_SMS,
  renderOrderingCampaignSms,
} from "../utils/customerOrderingCampaignSms";
import twilio from "twilio";
import { createHash } from "crypto";

type MerchantActivity = "active" | "inactive" | "all";

function isWhatsAppListed(data: FirebaseFirestore.DocumentData): boolean {
  return (
    data.whatsappListed === true ||
    data.whatsappEnabled === true ||
    data.availableOnWhatsApp === true
  );
}

async function merchantHasWhatsAppProducts(
  merchantId: string,
): Promise<boolean> {
  const productsSnapshot = await db
    .collection("users")
    .doc(merchantId)
    .collection("products")
    .get();

  return productsSnapshot.docs.some((doc) => isWhatsAppListed(doc.data()));
}

/**
 * Sends a WhatsApp ordering campaign to customers grouped by merchant activity.
 *
 * Use separate approved Twilio templates for:
 * - catalogReadyTemplateId: invites the customer to order from their merchant
 *   on WhatsApp.
 * - catalogEmptyTemplateId: invites the customer to try WhatsApp ordering and
 *   ask their merchant to add products to Pasella if none are shown.
 *
 * `templateId` remains as a backwards-compatible fallback for both states.
 * Test mode prevents actual sends.
 */
exports.sendPromoToActiveCustomers = functions
  .runWith({ timeoutSeconds: 540, memory: "512MB" })
  .https.onRequest(async (req, res) => {
    const {
      templateId,
      merchantId: requestedMerchantId,
      catalogReadyTemplateId,
      catalogEmptyTemplateId,
      smsFallbackEnabled = false,
      smsOrderingUrl,
      smsCatalogReadyBody = DEFAULT_CATALOG_READY_SMS,
      smsCatalogEmptyBody = DEFAULT_CATALOG_EMPTY_SMS,
      merchantActivity = "active",
      includedMerchantIds = [],
      maxRecipients,
      campaignId,
      testMode = true,
      excludedMerchantNumbers = [],
      excludedCustomerNumbers = [],
    } = req.body as {
      templateId?: string;
      merchantId?: string;
      catalogReadyTemplateId?: string;
      catalogEmptyTemplateId?: string;
      smsFallbackEnabled?: boolean;
      smsOrderingUrl?: string;
      smsCatalogReadyBody?: string;
      smsCatalogEmptyBody?: string;
      merchantActivity?: MerchantActivity;
      includedMerchantIds?: string[];
      maxRecipients?: number;
      campaignId?: string;
      testMode?: boolean;
      excludedMerchantNumbers?: string[];
      excludedCustomerNumbers?: string[];
    };

    if (!["active", "inactive", "all"].includes(merchantActivity)) {
      res.status(400).json({
        error: "merchantActivity must be active, inactive, or all",
      });
      return;
    }

    if (!templateId && !catalogReadyTemplateId && !catalogEmptyTemplateId) {
      res.status(400).json({
        error: "Provide templateId or catalog-specific WhatsApp template IDs.",
      });
      return;
    }

    if (!testMode) {
      const expectedSecret = functions.config().campaigns?.secret;
      const providedSecret = req.get("x-pasella-campaign-secret");
      if (!expectedSecret || providedSecret !== expectedSecret) {
        res.status(403).json({ error: "Invalid campaign authorization." });
        return;
      }
      if (!includedMerchantIds.length) {
        res.status(400).json({
          error:
            "Live sends require a non-empty includedMerchantIds allowlist.",
        });
        return;
      }
      if (!Number.isInteger(maxRecipients) || (maxRecipients ?? 0) <= 0) {
        res.status(400).json({
          error: "Live sends require a positive integer maxRecipients.",
        });
        return;
      }
      if (!campaignId?.trim()) {
        res.status(400).json({
          error: "Live sends require a campaignId.",
        });
        return;
      }
    }

    if (smsFallbackEnabled && smsOrderingUrl) {
      try {
        const orderingUrl = new URL(smsOrderingUrl ?? "");
        if (orderingUrl.protocol !== "https:") {
          throw new Error("Ordering URL must use HTTPS.");
        }
      } catch {
        res.status(400).json({
          error:
            "smsOrderingUrl must be a valid HTTPS URL when SMS fallback is enabled.",
        });
        return;
      }
    }

    try {
      const usersRef = db.collection("users");
      const includedMerchantIdSet = new Set(includedMerchantIds);
      const selectedCustomerNumbers = new Set<string>();
      const normalizedExcludedMerchants = new Set(
        excludedMerchantNumbers.map(normalizePhoneNumber).filter(Boolean),
      );
      const normalizedExcludedCustomers = new Set(
        excludedCustomerNumbers.map(normalizePhoneNumber).filter(Boolean),
      );
      let merchantsMatched = 0;
      let customersPrepared = 0;
      let customersSent = 0;
      let customersExcluded = 0;
      let customersInvalidNumber = 0;
      let customersWhatsApp = 0;
      let customersSms = 0;
      let customersUnknown = 0;
      let customersSkippedNoSmsFallback = 0;
      let customersSmsSent = 0;
      let customersSmsFailed = 0;
      let customersDuplicate = 0;
      let customersSkippedAtCap = 0;
      let customersAlreadyProcessed = 0;
      let smsSegmentsPrepared = 0;
      let smsClient: ReturnType<typeof twilio> | null = null;
      let whatsappClient: ReturnType<typeof twilio> | null = null;

      const sendSms = async (to: string, body: string): Promise<void> => {
        if (!smsClient) {
          const twilioConfig = functions.config().twilio;
          smsClient = twilio(twilioConfig.sid, twilioConfig.token);
        }
        const smsNumber = functions.config().twilio.number;
        if (!smsNumber) {
          throw new Error("Twilio SMS sender number is not configured.");
        }
        await smsClient.messages.create({
          to,
          from: smsNumber,
          body,
        });
      };

      const sendWhatsAppTemplate = async (
        to: string,
        contentSid: string,
        contentVariables: Record<string, string | undefined>,
      ): Promise<string> => {
        if (!whatsappClient) {
          const twilioConfig = functions.config().twilio;
          whatsappClient = twilio(twilioConfig.sid, twilioConfig.token);
        }
        const messagingServiceSid =
          functions.config().twilio.customer_messaging_service_sid;
        if (!messagingServiceSid) {
          throw new Error(
            "Twilio customer messaging service SID is not configured.",
          );
        }
        const message = await whatsappClient.messages.create({
          to,
          messagingServiceSid,
          contentSid,
          contentVariables: JSON.stringify(contentVariables),
        });
        return message.sid;
      };

      const reserveCampaignRecipient = async (
        recipientNumber: string,
        merchantId: string,
        customerId: string,
      ): Promise<FirebaseFirestore.DocumentReference | null> => {
        if (testMode || !campaignId) return null;
        const recipientKey = createHash("sha256")
          .update(recipientNumber)
          .digest("hex");
        const recipientRef = db
          .collection("campaignSends")
          .doc(campaignId)
          .collection("recipients")
          .doc(recipientKey);
        const reserved = await db.runTransaction(async (transaction) => {
          const existing = await transaction.get(recipientRef);
          if (existing.exists) return false;
          transaction.create(recipientRef, {
            campaignId,
            merchantId,
            customerId,
            recipientNumber,
            status: "sending",
            createdAt: new Date().toISOString(),
          });
          return true;
        });
        return reserved ? recipientRef : null;
      };

      const candidateTemplateIds = [
        templateId,
        catalogReadyTemplateId,
        catalogEmptyTemplateId,
      ]
        .filter((value): value is string => typeof value === "string")
        .map((value) => value.trim())
        .filter(Boolean);
      const uniqueTemplateIds = [...new Set(candidateTemplateIds)];
      const templateSnaps = await Promise.all(
        uniqueTemplateIds.map((id) =>
          db.collection("messagingTemplates").doc(id).get(),
        ),
      );
      if (templateSnaps.some((snapshot) => !snapshot.exists)) {
        res.status(404).send("Template not found");
        return;
      }

      const templateMerchantIds = new Set(
        templateSnaps
          .map((snapshot) => snapshot.data()?.userId)
          .filter((value): value is string => typeof value === "string")
          .map((value) => value.trim())
          .filter(Boolean),
      );
      if (templateMerchantIds.size !== 1) {
        res.status(400).send("Templates must share one valid merchant owner");
        return;
      }
      const templateMerchantId = [...templateMerchantIds][0];

      const requestedMerchant =
        typeof requestedMerchantId === "string"
          ? requestedMerchantId.trim()
          : "";
      if (requestedMerchant && requestedMerchant !== templateMerchantId) {
        res.status(403).send("Template does not belong to merchant");
        return;
      }

      const targetMerchantId = requestedMerchant || templateMerchantId;
      const targetMerchantDoc = await usersRef.doc(targetMerchantId).get();
      if (!targetMerchantDoc.exists) {
        res.status(404).send("Merchant not found");
        return;
      }

      // Process only the merchant that owns this template. The previous
      // implementation iterated every merchant with the same templateId,
      // which could send another merchant's promo copy to unrelated accounts.
      const promises = [targetMerchantDoc].map(async (userDoc) => {
        const userData = userDoc.data();
        if (!userData) {
          return;
        }
        const balanceData = userData.balanceData;
        const userPhoneNumber = userData.mobileNumber;

        if (
          includedMerchantIdSet.size > 0 &&
          !includedMerchantIdSet.has(userDoc.id)
        ) {
          return;
        }

        // Skip merchants that are in the exclusion list
        const normalizedMerchantNumber = normalizePhoneNumber(userPhoneNumber);
        if (
          normalizedMerchantNumber &&
          normalizedExcludedMerchants.has(normalizedMerchantNumber)
        ) {
          console.log(`Skipping merchant with phone number ${userPhoneNumber}`);
          return;
        }

        const lastUpdated = balanceData?.lastUpdated?.toDate?.();
        const oneMonthAgo = moment().subtract(1, "month");
        const isActive = lastUpdated
          ? moment(lastUpdated).isAfter(oneMonthAgo)
          : false;
        const activityMatches =
          merchantActivity === "all" ||
          (merchantActivity === "active" && isActive) ||
          (merchantActivity === "inactive" && !isActive);

        if (activityMatches) {
          merchantsMatched++;
          const hasWhatsAppProducts = await merchantHasWhatsAppProducts(
            userDoc.id,
          );
          const merchantOrderingUrl = String(
            smsOrderingUrl || userData.whatsappOrdering?.orderingUrl || "",
          ).trim();
          const selectedTemplateId = hasWhatsAppProducts
            ? catalogReadyTemplateId || templateId
            : catalogEmptyTemplateId || templateId;
          const selectedSmsBody = hasWhatsAppProducts
            ? smsCatalogReadyBody
            : smsCatalogEmptyBody;

          if (!selectedTemplateId) {
            console.log(
              `Skipping merchant ${userDoc.id}: no template for catalog state`,
            );
            return;
          }
          if (smsFallbackEnabled) {
            try {
              const orderingUrl = new URL(merchantOrderingUrl);
              if (orderingUrl.protocol !== "https:") {
                throw new Error("Ordering URL must use HTTPS.");
              }
            } catch {
              console.log(
                `Skipping merchant ${userDoc.id}: missing valid ordering URL`,
              );
              return;
            }
          }

          console.log("=====================================");
          console.log(`${isActive ? "Active" : "Inactive"} merchant`);
          console.log(userData.name);
          console.log(userData.shopName);
          console.log(userData.mobileNumber);
          console.log(balanceData?.totalCustomers);
          console.log(
            `WhatsApp products listed: ${hasWhatsAppProducts ? "yes" : "no"}`,
          );
          const customersRef = usersRef.doc(userDoc.id).collection("customers");
          const customersSnapshot = await customersRef.get();

          // Process each customer
          const messagePromises = customersSnapshot.docs.map(
            async (customerDoc) => {
              const customerData = customerDoc.data();
              const phoneNumber = customerData.number;

              if (!phoneNumber) {
                console.log(`No phone number for customer ${customerDoc.id}`);
                return; // Skip if no phone number
              }

              const normalizedNumber = normalizePhoneNumber(phoneNumber);
              if (
                normalizedNumber &&
                normalizedExcludedCustomers.has(normalizedNumber)
              ) {
                console.log(
                  `Skipping customer with phone number ${phoneNumber}`,
                );
                customersExcluded++;
                return;
              }

              const e164Number = formatPhoneNumber(phoneNumber);
              if (!e164Number) {
                console.log(
                  `Skipping customer ${customerDoc.id}: invalid SA number ${phoneNumber}`,
                );
                customersInvalidNumber++;
                return;
              }

              if (selectedCustomerNumbers.has(e164Number)) {
                customersDuplicate++;
                return;
              }
              if (
                maxRecipients !== undefined &&
                customersPrepared >= maxRecipients
              ) {
                customersSkippedAtCap++;
                return;
              }
              selectedCustomerNumbers.add(e164Number);
              customersPrepared++;

              const campaignRecipientRef = await reserveCampaignRecipient(
                e164Number,
                userDoc.id,
                customerDoc.id,
              );
              if (!testMode && !campaignRecipientRef) {
                customersAlreadyProcessed++;
                return;
              }

              const capability = await fetchWhatsAppCapability(e164Number);
              if (capability === "whatsapp") {
                customersWhatsApp++;
              } else if (capability === "sms") {
                customersSms++;
              } else {
                customersUnknown++;
              }

              const templateParams = {
                merchant_name: userData.name, // Merchant name from user data
                shop_name: userData.shopName, // Shop name from user data
                ordering_url: merchantOrderingUrl,
              };
              let renderedSmsBody: string | null = null;

              if (smsFallbackEnabled) {
                try {
                  renderedSmsBody = renderOrderingCampaignSms(selectedSmsBody, {
                    merchantName: userData.name ?? "",
                    shopName: userData.shopName ?? "",
                    orderingUrl: merchantOrderingUrl,
                  });
                  if (capability === "sms") {
                    smsSegmentsPrepared +=
                      calculateSmsSegments(renderedSmsBody);
                  }
                } catch (error) {
                  customersSmsFailed++;
                  console.error(
                    `Unable to prepare SMS for ${customerDoc.id}:`,
                    error,
                  );
                  return;
                }
              }

              // Logging details for debugging
              console.log(
                `Prepared ${capability} message route for ${e164Number} for customer ${customerDoc.id}`,
              );
              console.log(`Template Params:`, templateParams);

              if (capability === "sms" && !smsFallbackEnabled) {
                customersSkippedNoSmsFallback++;
                await campaignRecipientRef?.set(
                  {
                    status: "skipped_no_sms_fallback",
                    channel: "sms",
                    completedAt: new Date().toISOString(),
                  },
                  { merge: true },
                );
                console.log(
                  `Skipping ${e164Number}: known SMS route but SMS fallback is disabled.`,
                );
              } else if (testMode) {
                console.log(
                  capability === "sms"
                    ? `[TEST MODE] SMS to ${e164Number}: ${renderedSmsBody}`
                    : `[TEST MODE] WhatsApp would be attempted for ${e164Number}.`,
                );
              } else if (capability === "sms" && renderedSmsBody) {
                try {
                  await sendSms(e164Number, renderedSmsBody);
                  customersSent++;
                  customersSmsSent++;
                  await campaignRecipientRef?.set(
                    {
                      status: "sent",
                      channel: "sms",
                      completedAt: new Date().toISOString(),
                    },
                    { merge: true },
                  );
                  console.log(`Successfully sent SMS to ${e164Number}.`);
                } catch (error) {
                  customersSmsFailed++;
                  await campaignRecipientRef?.set(
                    {
                      status: "failed",
                      channel: "sms",
                      completedAt: new Date().toISOString(),
                    },
                    { merge: true },
                  );
                  console.error(`Failed to send SMS to ${e164Number}:`, error);
                }
              } else {
                const whatsappNumber = `whatsapp:${e164Number}`;

                try {
                  const twilioSid = await sendWhatsAppTemplate(
                    whatsappNumber,
                    selectedTemplateId,
                    templateParams,
                  );

                  console.log(
                    `Successfully sent message to via sendTwilioMessage ${whatsappNumber}:`,
                    twilioSid,
                  );
                  customersSent++;
                  await campaignRecipientRef?.set(
                    {
                      status: "sent",
                      channel: "whatsapp",
                      twilioSid,
                      completedAt: new Date().toISOString(),
                    },
                    { merge: true },
                  );
                } catch (err) {
                  console.error(
                    `Failed to send message to ${whatsappNumber}:`,
                    err,
                  );
                  if (smsFallbackEnabled && renderedSmsBody) {
                    try {
                      await sendSms(e164Number, renderedSmsBody);
                      customersSent++;
                      customersSmsSent++;
                      await campaignRecipientRef?.set(
                        {
                          status: "sent",
                          channel: "sms_fallback",
                          completedAt: new Date().toISOString(),
                        },
                        { merge: true },
                      );
                      console.log(
                        `WhatsApp failed; sent SMS fallback to ${e164Number}.`,
                      );
                    } catch (smsError) {
                      customersSmsFailed++;
                      await campaignRecipientRef?.set(
                        {
                          status: "failed",
                          channel: "whatsapp_and_sms",
                          completedAt: new Date().toISOString(),
                        },
                        { merge: true },
                      );
                      console.error(
                        `WhatsApp and SMS fallback failed for ${e164Number}:`,
                        smsError,
                      );
                    }
                  } else {
                    await campaignRecipientRef?.set(
                      {
                        status: "failed",
                        channel: "whatsapp",
                        completedAt: new Date().toISOString(),
                      },
                      { merge: true },
                    );
                  }
                }
              }
            },
          );

          // Wait for all customer messages to be processed
          await Promise.all(messagePromises);
        } else {
          console.log(
            `Skipping user ${userDoc.id}: activity does not match ${merchantActivity}.`,
          );
        }
      });

      // Wait for all users to be processed
      await Promise.all(promises);

      res.status(200).json({
        message: "WhatsApp ordering campaign processed successfully.",
        merchantActivity,
        testMode,
        merchantsMatched,
        customersPrepared,
        customersSent,
        channelReadiness: {
          whatsapp: customersWhatsApp,
          sms: customersSms,
          unknown: customersUnknown,
        },
        customersExcluded,
        customersInvalidNumber,
        customersDuplicate,
        customersSkippedAtCap,
        customersAlreadyProcessed,
        customersSkippedNoSmsFallback,
        customersSmsSent,
        customersSmsFailed,
        smsSegmentsPrepared,
      });
    } catch (error) {
      console.error("Error processing promotional messages:", error);
      res.status(500).send("Failed to process promotional messages");
    }
  });
