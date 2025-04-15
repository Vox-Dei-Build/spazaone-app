import { functions, db } from "../config/main";
/**
 * Webhook endpoint for Twilio to notify template approval/rejection events.
 * Listens to content status updates and updates Firestore accordingly.
 */
exports.twilioTemplateWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const payload = req.body;
  console.log("Received Twilio webhook:", JSON.stringify(payload));

  const twilioTemplateId = payload.sid;
  const status = payload.status; // "approved" | "rejected"
  const reason = payload.rejection_reason || null;

  if (!twilioTemplateId || !status) {
    res.status(400).send("Missing sid or status");
    return;
  }

  try {
    const querySnapshot = await db
      .collection("messagingTemplates")
      .where("channels.whatsapp.twilioTemplateId", "==", twilioTemplateId)
      .limit(1)
      .get();

    if (querySnapshot.empty) {
      console.warn(`No template found for Twilio SID ${twilioTemplateId}`);
      res.status(404).send("Template not found");
      return;
    }

    const docRef = querySnapshot.docs[0].ref;

    const updateData: any = {
      "channels.whatsapp.approvalStatus": status,
    };

    if (status === "rejected" && reason) {
      updateData["channels.whatsapp.rejectionReason"] = reason;
    }

    await docRef.update(updateData);
    res.status(200).send("Updated template status");
  } catch (error) {
    console.error("Error processing Twilio webhook:", error);
    res.status(500).send("Internal Server Error");
  }
});
