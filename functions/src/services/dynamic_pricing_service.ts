// functions/src/services/dynamic_pricing_service.ts
import * as admin from "firebase-admin";

/**
 * Computes per‑unit messaging prices by fetching
 * Remote Config parameters (both top‑level and grouped),
 * converting USD→ZAR, and applying markups.
 */
export class DynamicPricingService {
  private template: admin.remoteConfig.RemoteConfigTemplate;

  /**
   * @param {admin.remoteConfig.RemoteConfigTemplate} template
   *   The fetched Remote Config template containing parameters and groups.
   */
  private constructor(template: admin.remoteConfig.RemoteConfigTemplate) {
    this.template = template;
  }

  /**
   * Fetches the latest Remote Config template and returns
   * an initialized DynamicPricingService.
   *
   * @return {Promise<DynamicPricingService>}
   *   A promise resolving to the pricing service instance.
   */
  static async initialize(): Promise<DynamicPricingService> {
    const tpl = await admin.remoteConfig().getTemplate();
    console.log("[PRICING SERVICE] fetched ETag:", tpl.etag);
    console.log(
      "[PRICING SERVICE] top‑level parameters:",
      Object.keys(tpl.parameters),
    );
    console.log(
      "[PRICING SERVICE] parameterGroups:",
      Object.keys(tpl.parameterGroups),
    );
    return new DynamicPricingService(tpl);
  }

  /**
   * Reads a parameter’s default value by key, searching both
   * the top‑level `parameters` map and each `parameterGroups` entry.
   * Defaults to `"0"` if not found.
   *
   * @param {string} key
   *   The Remote Config parameter key to look up.
   * @return {string}
   *   The parameter’s string value, or `"0"` if missing.
   */
  private getParamValue(key: string): string {
    let param = this.template.parameters[key];

    if (!param) {
      // Search within each parameter group
      for (const group of Object.values(this.template.parameterGroups)) {
        // Remote Config can return empty groups without a `parameters`
        // object. The promotion callable previously crashed here before it
        // reached the pricing group, surfacing only "internal" to merchants.
        const parameters = group?.parameters;
        if (parameters?.[key]) {
          param = parameters[key];
          break;
        }
      }
    }

    if (!param?.defaultValue) {
      console.warn(
        `[PRICING SERVICE] missing RC param "${key}", defaulting to 0`,
      );
      return "0";
    }

    // Duck‑type to extract string
    const dv = param.defaultValue as { value?: string; defaultValue?: string };
    if (typeof dv.value === "string") return dv.value;
    if (typeof dv.defaultValue === "string") return dv.defaultValue;
    return "0";
  }

  /**
   * Converts a USD price to ZAR and applies a markup percentage.
   *
   * @param {string} usdKey
   *   The parameter key holding the USD base price.
   * @param {string} markupKey
   *   The parameter key holding the markup percentage.
   * @return {number}
   *   The final price in ZAR, rounded to two decimals.
   */
  private calculatePrice(usdKey: string, markupKey: string): number {
    const usd = parseFloat(this.getParamValue(usdKey));
    const mark = parseFloat(this.getParamValue(markupKey));
    const rate = parseFloat(this.getParamValue("USD_ZAR_EXCHANGE_RATE"));
    const base = usd * rate;
    const price = base + (base * mark) / 100;
    console.log(
      `[PRICING SERVICE] ${usdKey}=${usd}, ${markupKey}=${mark}%, rate=${rate} → ${price}`,
    );
    return Math.round(price * 100) / 100;
  }

  /**
   * SMS reminder template price per recipient.
   *
   * @return {number}
   *   The SMS reminder price in ZAR.
   */
  get smsReminderTemplatePrice(): number {
    return this.calculatePrice(
      "USD_SMS_REMINDER_PRICE",
      "MARKUP_SMS_PERCENTAGE",
    );
  }

  /**
   * SMS payment template price per recipient.
   *
   * @return {number}
   *   The SMS payment price in ZAR.
   */
  get smsPaymentTemplatePrice(): number {
    return this.calculatePrice(
      "USD_SMS_PAYMENT_PRICE",
      "MARKUP_SMS_PERCENTAGE",
    );
  }

  /**
   * WhatsApp utility message price per recipient.
   *
   * @return {number}
   *   The WhatsApp utility message price in ZAR.
   */
  get whatsappUtilityPrice(): number {
    return this.calculatePrice(
      "USD_WHATSAPP_UTILITY_PRICE",
      "MARKUP_WHATSAPP_PERCENTAGE",
    );
  }

  /**
   * WhatsApp promotional message price per recipient.
   *
   * @return {number}
   *   The WhatsApp promotional message price in ZAR.
   */
  get whatsappPromotionPrice(): number {
    return this.calculatePrice(
      "USD_WHATSAPP_PROMOTIONAL_PRICE",
      "MARKUP_PROMOTIONAL_PERCENTAGE",
    );
  }
}
