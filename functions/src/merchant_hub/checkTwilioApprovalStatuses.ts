import { functions, db } from "../config/main";
import axios from "axios";
import * as admin from "firebase-admin";
import { AndroidConfig } from "firebase-admin/messaging";

async function notifyMerchant(args: {
  merchantId: string;
  status: string;
  templateId: string;
  notification: { title: string; body: string };
  route: string;
}): Promise<void> {
  if (!args.merchantId.trim()) return;
  const merchantDoc = await db.collection("users").doc(args.merchantId).get();
  const token = merchantDoc.data()?.fcmToken;
  if (!token) {
    console.warn(`⚠️ No FCM token for merchant ${args.merchantId}`);
    return;
  }

  const androidConfig: AndroidConfig = {
    priority: "high",
    notification: {
      channelId: "default_channel",
      sound: "default",
    },
  };

  try {
    const sendRes = await admin.messaging().send({
      notification: args.notification,
      android: androidConfig,
      data: {
        status: args.status,
        templateId: args.templateId,
        route: args.route,
      },
      token,
    });
    console.log("📲 Notification sent:", sendRes);
  } catch (err) {
    console.error("❌ Failed to send FCM:", err);
  }
}

/**
 * Scheduled Cloud Function that checks the approval status of WhatsApp templates
 * submitted to Twilio and updates Firestore accordingly. If a template is approved
 * or rejected, it sends a push notification to the merchant using Firebase Cloud Messaging.
 *
 * Runs every 3 minutes.
 *
 * Firestore structure expected:
 * - messagingTemplates/{templateId}:
 *   - channels.whatsapp.twilioTemplateId: string
 *   - channels.whatsapp.approvalStatus: "submitted" | "pending" | "approved" | "rejected"
 *   - name: string (template name)
 *   - userId: string (merchant ID)
 *
 * - users/{merchantId}:
 *   - fcmToken: string
 */
exports.checkTwilioApprovalStatuses = functions.pubsub
  .schedule("every 3 minutes") // Based on your WhatsApp approval SLA
  .onRun(async () => {
    console.log("🔁 Checking WhatsApp template statuses...");

    const snapshot = await db
      .collection("messagingTemplates")
      .where("channels.whatsapp.approvalStatus", "in", ["pending", "submitted"])
      .get();

    if (snapshot.empty) {
      console.log("✅ No templates pending approval.");
      return;
    }

    const twilioAuth = {
      username: functions.config().twilio.sid,
      password: functions.config().twilio.token,
    };

    const updates = snapshot.docs.map(async (doc) => {
      const data = doc.data();
      const sid = data.channels?.whatsapp?.twilioTemplateId;
      const merchantId = data.userId;

      if (!sid || !merchantId) return;

      try {
        const res = await axios.get(
          `https://content.twilio.com/v1/Content/${sid}/ApprovalRequests`,
          { auth: twilioAuth },
        );

        const wa = res.data.whatsapp;
        const status = wa.status.toLowerCase(); // "approved", "rejected", "pending"

        if (status === "pending") {
          await doc.ref.update({
            "channels.whatsapp.approvalStatus": "pending",
          });
          console.log(`⏳ Updated ${sid} → pending`);
        } else if (["approved", "rejected"].includes(status)) {
          const update: any = {
            "channels.whatsapp.approvalStatus": status,
          };

          if (status === "approved") {
            update["channels.whatsapp.approved"] = true;
          }

          if (status === "rejected" && wa.rejection_reason) {
            update["channels.whatsapp.rejectionReason"] = wa.rejection_reason;
          }

          await doc.ref.update(update);
          console.log(`🔄 Updated ${sid} → ${status}`);

          const isProductPromotion =
            data.systemManaged === true &&
            data.templateKind === "product_promotion_v1";
          const notification = isProductPromotion
            ? {
                title:
                  status === "approved"
                    ? "WhatsApp promotions are ready 🎉"
                    : "WhatsApp promotion setup needs attention",
                body:
                  status === "approved"
                    ? "Choose a product and customers whenever you are ready to send."
                    : `Pasella could not finish setup. ${wa.rejection_reason || "Open Marketing to try again."}`,
              }
            : {
                title:
                  status === "approved"
                    ? "WhatsApp Template Approved 🎉"
                    : "WhatsApp Template Rejected ❌",
                body:
                  status === "approved"
                    ? `Your template "${data.name}" is now ready to go live!`
                    : `Your template "${data.name}" was rejected. Reason: ${wa.rejection_reason || "Not provided."}`,
              };

          if (isProductPromotion && data.systemScope === "global") {
            const bindings = await db
              .collection("messagingTemplates")
              .where("systemSourceTemplateId", "==", doc.id)
              .get();
            for (let start = 0; start < bindings.docs.length; start += 450) {
              const batch = db.batch();
              for (const binding of bindings.docs.slice(start, start + 450)) {
                batch.update(binding.ref, {
                  "channels.whatsapp.approvalStatus": status,
                  "channels.whatsapp.approved": status === "approved",
                  "channels.whatsapp.twilioTemplateId": sid,
                  "channels.whatsapp.rejectionReason":
                    status === "rejected"
                      ? wa.rejection_reason || "Not provided."
                      : admin.firestore.FieldValue.delete(),
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                });
              }
              await batch.commit();
            }

            await Promise.all(
              bindings.docs.map((binding) =>
                notifyMerchant({
                  merchantId: String(binding.data().userId || ""),
                  status,
                  templateId: binding.id,
                  notification,
                  route:
                    status === "approved"
                      ? "/promotionsPage?tab=promotions&action=run"
                      : "/promotionsPage?tab=promotions",
                }),
              ),
            );
            return;
          }

          await notifyMerchant({
            merchantId,
            status,
            templateId: doc.id,
            notification,
            route: isProductPromotion
              ? status === "approved"
                ? "/promotionsPage?tab=promotions&action=run"
                : "/promotionsPage?tab=promotions"
              : status === "approved"
                ? "/promotionsPage?tab=promotions&action=run"
                : `/promotionsPage?tab=templates&templateId=${doc.id}`,
          });
        }
      } catch (err) {
        console.error(`❌ Failed to fetch status for ${sid}:`, err);
      }
    });

    await Promise.all(updates);
  });
