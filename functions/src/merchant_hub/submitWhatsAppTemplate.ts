import { functions, db } from "../config/main";
import axios, { AxiosError } from "axios";
import { firestore } from "firebase-admin";

/**
 * Parse named placeholders from a template body in first-appearance order,
 * generate a variables map (for Twilio Content API), and a single-row examples
 * matrix for WhatsApp approval components.example.body_text.
 *
 * Allowed names: [A-Za-z0-9_], no spaces inside {{ }}.
 *
 * @param {string} template - Body with named placeholders (e.g., "Hi {{customerName}}...")
 * @returns {object} Parsed variables and examples for Twilio/WhatsApp.
 * @property {string[]} orderedNames - Placeholder names in first-appearance order.
 * @property {Object<string, string>} variables - Deterministic sample values keyed by name.
 * @property {string[][]} examplesMatrix - Single-row matrix for WA approval examples.
 */
function parseNamedVariables(template: string): {
  orderedNames: string[];
  variables: Record<string, string>;
  examplesMatrix: string[][];
} {
  const re = /{{\s*([A-Za-z0-9_]+)\s*}}/g;
  const orderedNames: string[] = [];
  const seen = new Set<string>();
  let m: RegExpExecArray | null;

  while ((m = re.exec(template)) !== null) {
    const name = m[1];
    if (!seen.has(name)) {
      seen.add(name);
      orderedNames.push(name);
    }
  }

  // Deterministic sample generation (tweak as needed)
  const variables: Record<string, string> = {};
  const row: string[] = [];
  orderedNames.forEach((name, i) => {
    const sample = /amount|price|total/i.test(name)
      ? "R150"
      : /balance/i.test(name)
        ? "0"
        : /shop/i.test(name)
          ? "Test Shop"
          : /name/i.test(name)
            ? "Tsepo"
            : "Example " + (i + 1);
    variables[name] = sample;
    row.push(sample);
  });

  return { orderedNames, variables, examplesMatrix: row.length ? [row] : [] };
}

/**
 * Soft validation for common WA format pitfalls. We only log warnings, do not block.
 * @param {string} body - WhatsApp template body text to validate.
 * @return {string[]} warnings - List of non-blocking warning messages.
 */
function validateWhatsAppBody(body: string): string[] {
  const warnings: string[] = [];
  const startsWithVar = /^\s*{{\s*[A-Za-z0-9_]+\s*}}/.test(body);
  // Ends with a bare variable (no trailing non-space punctuation)
  const endsWithVar = /{{\s*[A-Za-z0-9_]+\s*}}\s*$/.test(body);
  const adjacentVars = /{{\s*[A-Za-z0-9_]+\s*}}\s+{{\s*[A-Za-z0-9_]+\s*}}/.test(
    body,
  );

  if (startsWithVar)
    warnings.push("Body starts with a variable; ensure samples are provided.");
  if (endsWithVar)
    warnings.push(
      "Body ends with a variable; add punctuation so it doesn't end on a placeholder.",
    );
  if (adjacentVars)
    warnings.push("Body has adjacent variables; ensure samples are provided.");
  return warnings;
}

function ensureNonVariableEnding(body: string): string {
  // If the body ends with a bare variable, add a period to avoid WA review issues
  if (/{{\s*[A-Za-z0-9_]+\s*}}\s*$/.test(body)) {
    return body + ".";
  }
  return body;
}

function buildProviderTemplateName(
  rawName: unknown,
  merchantId: string,
  templateId: string,
): string {
  const base = String(rawName || "template")
    .toLowerCase()
    .replace(/[\s-]+/g, "_")
    .replace(/[^a-z0-9_]/g, "")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
  const suffix =
    merchantId
      .toLowerCase()
      .replace(/[^a-z0-9]/g, "")
      .slice(0, 10) ||
    templateId
      .toLowerCase()
      .replace(/[^a-z0-9]/g, "")
      .slice(0, 10);
  const scopedName = `${base || "template"}_${suffix}`;
  return scopedName.slice(0, 512).replace(/_+$/g, "");
}

/**
 * Submits a newly created WhatsApp template to Twilio's Content API for approval.
 * Automatically triggers when a new template is created in Firestore under messagingTemplates.
 */
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

    const merchantId =
      typeof templateData?.userId === "string"
        ? templateData.userId.trim()
        : "";
    if (!merchantId) {
      console.error(
        `Template ${templateId} is missing userId; not submitting.`,
      );
      await snap.ref.update({
        "channels.whatsapp.approvalStatus": "submission_failed",
        "channels.whatsapp.submissionError": "Missing merchant userId",
      });
      return;
    }

    const rawContent = whatsapp.templateContent?.trim();
    const mediaUrl = whatsapp.mediaUrl?.trim();
    if (!rawContent) {
      console.log("No content provided in WhatsApp template.");
      return;
    }

    // Keep named placeholders as-is, but ensure we don't end on a variable
    const content = ensureNonVariableEnding(rawContent);
    const { variables, examplesMatrix } = parseNamedVariables(content);

    // Soft warnings (log only)
    for (const w of validateWhatsAppBody(content)) {
      console.warn(`[WA template warning] ${w}`);
    }

    const twilioAuth = {
      username: functions.config().twilio.sid,
      password: functions.config().twilio.token,
    };

    const createPayload: any = {
      friendly_name: buildProviderTemplateName(
        templateData.name,
        merchantId,
        templateId,
      ),
      language: "en",
      channel: "whatsapp",
      types: {
        "twilio/text": { body: content },
        ...(mediaUrl && {
          "twilio/media": { body: content, media: [mediaUrl] },
        }),
      },
      ...(Object.keys(variables).length > 0 && { variables }),
    };

    let approvalPayload: any;
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

      approvalPayload = {
        name: createPayload.friendly_name,
        category: "MARKETING",
      };

      if (examplesMatrix.length) {
        approvalPayload.components = [
          { type: "BODY", example: { body_text: examplesMatrix } },
        ];
      }

      const approvalRes = await axios.post(
        `https://content.twilio.com/v1/Content/${sid}/ApprovalRequests/whatsapp`,
        approvalPayload,
        { auth: twilioAuth },
      );

      console.log("✅ WhatsApp approval submitted:", approvalRes.data);

      await db.collection("messagingTemplates").doc(templateId).update({
        "channels.whatsapp.providerTemplateName": createPayload.friendly_name,
        "channels.whatsapp.twilioTemplateId": sid,
        "channels.whatsapp.approvalStatus": "submitted",
      });
    } catch (error: any) {
      const err = error as AxiosError;
      console.error(
        "❌ Template creation or approval failed:",
        err.response?.data || err.message,
      );
      console.error(
        "Payloads:",
        JSON.stringify({ createPayload, approvalPayload }, null, 2),
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
