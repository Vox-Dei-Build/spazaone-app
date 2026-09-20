import { functions } from "../config/main";
import { assertCallableStoreAccess } from "../stores/storeAccess";
import {
  DynamicPricingService,
  MessagingPricingUnavailableError,
} from "./dynamic_pricing_service";

export const getMessagingPricingV1 = functions.https.onCall(
  async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Sign in is required.",
      );
    }
    if (!context.app) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "App verification is required.",
      );
    }
    const storeId = String(data?.storeId ?? context.auth.uid).trim();
    await assertCallableStoreAccess(context, storeId);
    try {
      const pricing = await DynamicPricingService.initialize();
      return pricing.buyerSafeSnapshot;
    } catch (error) {
      if (error instanceof MessagingPricingUnavailableError) {
        console.error("[MESSAGING PRICING] required pricing is unavailable", {
          surface: "messaging_pricing",
          stage: "validation",
          code: "INVALID_PRICING_CONFIGURATION",
          retryOutcome: "not_applicable",
        });
        throw new functions.https.HttpsError(
          "failed-precondition",
          "Messaging pricing is temporarily unavailable.",
        );
      }
      console.error("[MESSAGING PRICING] pricing lookup failed", {
        surface: "messaging_pricing",
        stage: "remote_config_read",
        code: "PRICING_PROVIDER_UNAVAILABLE",
        retryOutcome: "exhausted",
      });
      throw new functions.https.HttpsError(
        "unavailable",
        "Messaging pricing is temporarily unavailable.",
      );
    }
  },
);
