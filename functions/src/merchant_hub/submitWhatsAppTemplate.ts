import { functions, db } from "../config/main";
import axios, { AxiosError } from "axios";
import { firestore } from "firebase-admin";

/**
 * Converts named template placeholders (e.g. `{{customerName}}`) into Twilio-compliant
 * numbered placeholders (e.g. `{{1}}`, `{{2}}`). This is required because the Twilio Content API
 * and WhatsApp only support numeric placeholders.
 *
 * Also returns a mapping of original variable names to their assigned placeholder numbers.
 *
 * @param {string} template - The original message template string containing named placeholders.
 * @return {{ normalized: string, variableMap: Record<string, number> }}
 * An object containing:
 *  - `normalized`: The template string with all placeholders converted to `{{1}}`, `{{2}}`, etc.
 *  - `variableMap`: A map of the original placeholder names to their corresponding numeric index.
 *
 * @example
 * // Input: "Hi {{customerName}}, your order from {{shopName}} is ready."
 * // Output: {
 * //   normalized: "Hi {{1}}, your order from {{2}} is ready.",
 * //   variableMap: { customerName: 1, shopName: 2 }
 * // }
 * */
function normalizeTemplateContent(template: string): {
  normalized: string;
  variableMap: Record<string, number>;
} {
  const matches = [...template.matchAll(/{{(.*?)}}/g)];
  const seen = new Map<string, number>();
  let index = 1;
  let normalized = template;

  for (const match of matches) {
    const full = match[0];
    const name = match[1].trim();

    if (!seen.has(name)) {
      seen.set(name, index++);
    }

    const numbered = `{{${seen.get(name)}}}`;
    while (normalized.includes(full)) {
      normalized = normalized.replace(full, numbered);
    }
  }

  const variableMap: Record<string, number> = {};
  seen.forEach((value, key) => (variableMap[key] = value));

  return { normalized, variableMap };
}

/**
 * Extracts Twilio-compatible numbered variables from a template string.
 * Twilio only supports numbered variables like {{1}}, {{2}}, etc.
 * This function maps each detected variable to a sample value required for template approval.
 * @param {string} template - The message template string containing {{}} placeholders.
 * @return {Record<string, string>} An object mapping variable numbers to example values.
 * */
function extractTwilioVariables(template: string): {
  variables: Record<string, string>;
  exampleValues: string[];
} {
  const matches = [...template.matchAll(/{{(.*?)}}/g)];
  const variables: Record<string, string> = {};
  const exampleValues: string[] = [];
  const seen = new Set<string>();
  let index = 1;

  for (const match of matches) {
    if (!seen.has(match[0])) {
      const key = `${index}`;
      variables[key] = `Example ${index}`;
      exampleValues.push(`Example ${index}`);
      seen.add(match[0]);
      index++;
    }
  }

  return { variables, exampleValues };
}

/**
 *
 * Submits a newly created WhatsApp template to Twilio's Content API for approval.
 * Automatically triggers when a new template is created in Firestore under messagingTemplates.
 * */
exports.submitWhatsAppTemplate = functions.firestore
  .document("messagingTemplates/{templateId}")
  .onCreate(async (snap: firestore.DocumentSnapshot, context) => {
    const templateData = snap.data();
    const templateId = context.params.templateId;

    const whatsapp = templateData?.channels?.whatsapp;
    if (!whatsapp) {
      console.log("No WhatsApp content found, skipping Twilio submission.");
      return;
    }

    const rawContent = whatsapp.templateContent?.trim();
    const mediaUrl = whatsapp.mediaUrl?.trim();
    if (!rawContent) {
      console.log("No content provided in WhatsApp template.");
      return;
    }

    const { normalized: content } = normalizeTemplateContent(rawContent);
    const { variables, exampleValues } = extractTwilioVariables(content);

    const twilioAuth = {
      username: functions.config().twilio.sid,
      password: functions.config().twilio.token,
    };

    const createPayload: any = {
      friendly_name: templateData.name,
      language: "en",
      channel: "whatsapp",
      types: {
        "twilio/text": { body: content },
        ...(mediaUrl && {
          "twilio/media": {
            body: content,
            media: [mediaUrl],
          },
        }),
      },
      ...(Object.keys(variables).length > 0 && { variables }),
    };

    try {
      const createRes = await axios.post(
        "https://content.twilio.com/v1/Content",
        createPayload,
        {
          auth: twilioAuth,
        },
      );

      const sid = createRes.data.sid;
      console.log("✅ Template created:", sid);

      const approvalPayload: any = {
        name: templateData.name.toLowerCase().replace(/\s+/g, "_"),
        category: "MARKETING",
      };

      if (exampleValues.length > 0) {
        approvalPayload.components = [
          {
            type: "BODY",
            example: {
              body_text: [exampleValues],
            },
          },
        ];
      }

      const approvalRes = await axios.post(
        `https://content.twilio.com/v1/Content/${sid}/ApprovalRequests/whatsapp`,
        approvalPayload,
        { auth: twilioAuth },
      );

      console.log("✅ WhatsApp approval submitted:", approvalRes.data);

      await db.collection("messagingTemplates").doc(templateId).update({
        "channels.whatsapp.twilioTemplateId": sid,
        "channels.whatsapp.approvalStatus": "submitted",
      });
    } catch (error: any) {
      const err = error as AxiosError;
      console.error(
        "❌ Template creation or approval failed:",
        err.response?.data || err.message,
      );

      await db
        .collection("messagingTemplates")
        .doc(templateId)
        .update({
          "channels.whatsapp.approvalStatus": "submission_failed",
          "channels.whatsapp.submissionError": JSON.stringify(
            err.response?.data || err.message,
          ),
        });
    }
  });
