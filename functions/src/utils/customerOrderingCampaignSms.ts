export const DEFAULT_CATALOG_READY_SMS =
  "SpazaOne: Order from {{shop_name}} on WhatsApp: {{ordering_url}}. Send CATALOG or type what you need. Reply STOP to opt out.";

export const DEFAULT_CATALOG_EMPTY_SMS =
  "SpazaOne: Try {{shop_name}} on WhatsApp: {{ordering_url}}. No products? Ask {{merchant_name}} to add them in SpazaOne. Reply STOP to opt out.";

export interface OrderingCampaignSmsVariables {
  merchantName: string;
  shopName: string;
  orderingUrl: string;
}

/**
 * Replaces the campaign's supported SMS variables and rejects unresolved
 * placeholders. SMS bodies remain configurable through the HTTP request, while
 * these defaults provide concise, ASCII-safe copy.
 */
export function renderOrderingCampaignSms(
  template: string,
  variables: OrderingCampaignSmsVariables,
): string {
  const rendered = template
    .split("{{merchant_name}}")
    .join(variables.merchantName.trim())
    .split("{{shop_name}}")
    .join(variables.shopName.trim())
    .split("{{ordering_url}}")
    .join(variables.orderingUrl.trim())
    .trim();

  if (!rendered) {
    throw new Error("SMS body cannot be empty.");
  }
  if (/\{\{[^}]+\}\}/.test(rendered)) {
    throw new Error("SMS body contains an unsupported or unresolved variable.");
  }
  return rendered;
}

/**
 * Estimates Twilio SMS segments. The campaign defaults are GSM-7-compatible,
 * but merchant names can introduce Unicode, so segment reporting must account
 * for both encodings.
 */
export function calculateSmsSegments(text: string): number {
  const content = text.trim();
  if (!content) return 1;

  const isUnicode = [...content].some((char) => char.charCodeAt(0) > 127);
  const singleSegmentLength = isUnicode ? 70 : 160;
  const multipartSegmentLength = isUnicode ? 67 : 153;

  if (content.length <= singleSegmentLength) return 1;
  return Math.ceil(content.length / multipartSegmentLength);
}
