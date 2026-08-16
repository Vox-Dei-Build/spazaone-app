import assert from "node:assert/strict";
import test from "node:test";

import {
  MessagingPricingUnavailableError,
  messagingPricingSnapshotV1,
} from "../lib/services/dynamic_pricing_service.js";

const values = {
  USD_SMS_REMINDER_PRICE: "0.0757",
  USD_SMS_PAYMENT_PRICE: "0.0757",
  USD_WHATSAPP_UTILITY_PRICE: "0.0076",
  USD_WHATSAPP_PROMOTIONAL_PRICE: "0.0379",
  MARKUP_SMS_PERCENTAGE: "26",
  MARKUP_WHATSAPP_PERCENTAGE: "45",
  MARKUP_PROMOTIONAL_PERCENTAGE: "45",
  USD_ZAR_EXCHANGE_RATE: "18.25",
};

function parameters(source = values) {
  return Object.fromEntries(
    Object.entries(source).map(([key, value]) => [
      key,
      { defaultValue: { value } },
    ]),
  );
}

test("messaging pricing returns exact integer-cent production economics", () => {
  assert.deepEqual(messagingPricingSnapshotV1({ parameters: parameters() }), {
    schemaVersion: 1,
    currency: "ZAR",
    smsCustomerMinor: 174,
    smsPaymentMinor: 174,
    whatsappUtilityMinor: 20,
    whatsappPromotionMinor: 100,
  });
});

test("messaging pricing reads Firebase parameter groups", () => {
  const snapshot = messagingPricingSnapshotV1({
    parameters: {},
    parameterGroups: {
      messaging: { parameters: parameters() },
    },
  });
  assert.equal(snapshot.smsCustomerMinor, 174);
  assert.equal(snapshot.whatsappUtilityMinor, 20);
});

for (const [name, override] of [
  ["missing", undefined],
  ["zero", "0"],
  ["malformed", "free"],
]) {
  test(`messaging pricing fails closed for a ${name} required rate`, () => {
    const source = { ...values };
    if (override === undefined) delete source.USD_WHATSAPP_UTILITY_PRICE;
    else source.USD_WHATSAPP_UTILITY_PRICE = override;
    assert.throws(
      () => messagingPricingSnapshotV1({ parameters: parameters(source) }),
      MessagingPricingUnavailableError,
    );
  });
}
