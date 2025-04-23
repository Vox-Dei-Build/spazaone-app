import { functions, db } from "../config/main";
import axios from "axios";
import * as admin from "firebase-admin";
import { AndroidConfig } from "firebase-admin/messaging";

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

        if (["approved", "rejected"].includes(status)) {
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

          // 🔔 Push notification logic
          const merchantDoc = await db
            .collection("users")
            .doc(merchantId)
            .get();
          const token = merchantDoc.data()?.fcmToken;

          if (!token) {
            console.warn(`⚠️ No FCM token for merchant ${merchantId}`);
            return;
          }

          const notification = {
            title:
              status === "approved"
                ? "WhatsApp Template Approved 🎉"
                : "WhatsApp Template Rejected ❌",
            body:
              status === "approved"
                ? `Your template "${data.name}" is now ready to go live!`
                : `Your template "${data.name}" was rejected. Reason: ${wa.rejection_reason || "Not provided."}`,
          };

          const androidConfig: AndroidConfig = {
            priority: "high",
            notification: {
              channelId: "default_channel", // ✅ Correct key for channel ID
              sound: "default",
            },
          };

          const payload = {
            notification,
            android: androidConfig,
            data: {
              status,
              templateId: doc.id,
            },
            token,
          };

          try {
            const sendRes = await admin.messaging().send(payload);
            console.log("📲 Notification sent:", sendRes);
          } catch (err) {
            console.error("❌ Failed to send FCM:", err);
          }
        }
      } catch (err) {
        console.error(`❌ Failed to fetch status for ${sid}:`, err);
      }
    });

    await Promise.all(updates);
  });
