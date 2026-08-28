import { isMerchantProductCustomerVisible } from "../whatsapp/catalogProjection";
import { whatsappProductListRuntimeConfig } from "../whatsapp/nativeProductList";

function isWhatsAppListed(product: Record<string, unknown>): boolean {
  return (
    product.whatsappListed === true ||
    product.whatsappEnabled === true ||
    product.availableOnWhatsApp === true
  );
}

/**
 * Read only the delivery switch needed by the existing Botpress catalogue.
 * Deliberately avoid the native delivery runtime config here: that config
 * validates provider credentials and rollout scope that the legacy endpoint
 * does not need while the feature is dark.
 */
export function nativeProductListDeliveryEnabled(): boolean {
  return (
    String(process.env.WHATSAPP_PRODUCT_LIST_ENABLED ?? "")
      .trim()
      .toLowerCase() === "true"
  );
}

export function merchantBotCatalogVisibilityFilter(): (
  product: Record<string, unknown>,
) => boolean {
  if (!nativeProductListDeliveryEnabled()) {
    // Preserve the endpoint's pre-native-catalogue semantics exactly while
    // native delivery is disabled. In particular, do not require any native
    // provider or rollout configuration on this path.
    return isWhatsAppListed;
  }

  // A true delivery switch may alter the products returned to customers only
  // after the complete native runtime configuration has passed its fail-closed
  // provider, catalogue, rollout, recipient and environment validation.
  const config = whatsappProductListRuntimeConfig();
  if (!config.enabled) {
    throw new Error("WHATSAPP_PRODUCT_LIST_RUNTIME_NOT_ENABLED");
  }
  return isMerchantProductCustomerVisible;
}

export function isMerchantProductVisibleInBotCatalog(
  product: Record<string, unknown>,
): boolean {
  return merchantBotCatalogVisibilityFilter()(product);
}
