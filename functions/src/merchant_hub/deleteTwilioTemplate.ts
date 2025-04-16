import { functions } from "../config/main";
import axios from "axios";

/**
 * Cloud Function to delete Twilio WhatsApp templates.
 * Triggered via an HTTPS callable request.
 *
 * @param {functions.https.Request} req - Twilio template ID passed in data.
 * @param {functions.Response} res - HTTP response.
 */
export const deleteTwilioTemplate = functions.https.onCall(
  async (data, context) => {
    const { twilioTemplateId } = data;

    if (!twilioTemplateId) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Twilio template ID is required.",
      );
    }

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
      console.error(`❌ Failed to delete Twilio template: ${error}`);
      throw new functions.https.HttpsError(
        "internal",
        "Failed to delete Twilio template.",
      );
    }
  },
);
