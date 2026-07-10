import {
  calculateSmsSegments,
  DEFAULT_CATALOG_EMPTY_SMS,
  DEFAULT_CATALOG_READY_SMS,
  renderOrderingCampaignSms,
} from "../customerOrderingCampaignSms";

const variables = {
  merchantName: "Mpho",
  shopName: "Mpho's Shop",
  orderingUrl: "https://wa.me/27600167119",
};

const ready = renderOrderingCampaignSms(DEFAULT_CATALOG_READY_SMS, variables);
const empty = renderOrderingCampaignSms(DEFAULT_CATALOG_EMPTY_SMS, variables);

if (ready.includes("{{") || empty.includes("{{")) {
  throw new Error("Rendered SMS copy contains unresolved variables.");
}
if (!ready.includes("Reply STOP") || !empty.includes("Reply STOP")) {
  throw new Error("SMS copy must retain opt-out wording.");
}
if (calculateSmsSegments(ready) !== 1) {
  throw new Error(`Ready-catalog SMS exceeds one segment: ${ready}`);
}
if (calculateSmsSegments(empty) !== 1) {
  throw new Error(`Empty-catalog SMS exceeds one segment: ${empty}`);
}

let rejectedUnknownVariable = false;
try {
  renderOrderingCampaignSms("Hello {{customer_name}}", variables);
} catch {
  rejectedUnknownVariable = true;
}
if (!rejectedUnknownVariable) {
  throw new Error("Unsupported SMS variables must be rejected.");
}

// eslint-disable-next-line no-console
console.log("Verified ordering campaign SMS rendering and segment counts.");
