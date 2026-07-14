import { functions, db } from "../config/main";
import axios, { AxiosError } from "axios";

async function resolveOwnedTwilioTemplateId(
  uid: string,
  templateId: string,
  twilioTemplateId: string,
): Promise<string> {
  if (templateId) {
    const snap = await db
      .collection("messagingTemplates")
      .doc(templateId)
      .get();
    if (!snap.exists) {
      throw new functions.https.HttpsError("not-found", "Template not found.");
    }

    const data = snap.data();
    if (!data) {
      throw new functions.https.HttpsError("not-found", "Template not found.");
    }
    if (data.userId !== uid) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Template does not belong to the signed-in merchant.",
      );
    }
    if (data.systemManaged === true) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "SpazaOne-managed templates cannot be deleted.",
      );
    }

    const storedTwilioTemplateId =
      data.channels?.whatsapp?.twilioTemplateId ?? "";
    if (!storedTwilioTemplateId) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Template has no Twilio template ID.",
      );
    }

    if (twilioTemplateId && twilioTemplateId !== storedTwilioTemplateId) {
      throw new functions.https.HttpsError(
        "permission-denied",
        "Twilio template ID does not match the merchant template.",
      );
    }

    return storedTwilioTemplateId;
  }

  if (!twilioTemplateId) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Template ID or Twilio template ID is required.",
    );
  }

  const snapshot = await db
    .collection("messagingTemplates")
    .where("channels.whatsapp.twilioTemplateId", "==", twilioTemplateId)
    .limit(1)
    .get();

  if (snapshot.empty) {
    throw new functions.https.HttpsError("not-found", "Template not found.");
  }

  const data = snapshot.docs[0].data();
  if (data.systemManaged === true) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "SpazaOne-managed templates cannot be deleted.",
    );
  }
  if (data.userId !== uid) {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Template does not belong to the signed-in merchant.",
    );
  }

  return twilioTemplateId;
}

/**
 * Cloud Function to delete Twilio WhatsApp templates.
 * Triggered via an HTTPS callable request.
 *
 * @param {functions.https.Request} req - Twilio template ID passed in data.
 * @param {functions.Response} res - HTTP response.
 */
export const deleteTwilioTemplate = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be signed in.",
      );
    }

    const templateId =
      typeof data?.templateId === "string" ? data.templateId.trim() : "";
    const requestedTwilioTemplateId =
      typeof data?.twilioTemplateId === "string"
        ? data.twilioTemplateId.trim()
        : "";

    const twilioTemplateId = await resolveOwnedTwilioTemplateId(
      context.auth.uid,
      templateId,
      requestedTwilioTemplateId,
    );

    const twilioAuth = {
      username: functions.config().twilio.sid,
      password: functions.config().twilio.token,
    };

    try {
      await axios.delete(
        `https://content.twilio.com/v1/Content/${twilioTemplateId}`,
        {
          auth: twilioAuth,
        },
      );

      console.log(`✅ Deleted Twilio template: ${twilioTemplateId}`);
      return { success: true };
    } catch (error) {
      const err = error as AxiosError;
      if (err.response?.status === 404) {
        console.warn(`Twilio template already missing: ${twilioTemplateId}`);
        return { success: true, alreadyDeleted: true };
      }

      console.error(`❌ Failed to delete Twilio template: ${error}`);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to delete Twilio template.",
      );
    }
  },
);
