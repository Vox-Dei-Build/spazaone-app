import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  cleanWhatsAppProfileName,
  shouldUseWhatsAppProfileName,
} from "../lib/ecommerce/getShopContextBotHttp.js";

const sourceRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "src");

test("WhatsApp profile names are bounded and reject provider placeholders", () => {
  assert.equal(
    cleanWhatsAppProfileName("  Thandi   Mokoena  "),
    "Thandi Mokoena",
  );
  assert.equal(cleanWhatsAppProfileName("Anonymous User"), undefined);
  assert.equal(cleanWhatsAppProfileName("WhatsApp 0009"), undefined);
  assert.equal(cleanWhatsAppProfileName("+27 64 837 0009"), undefined);
  assert.equal(cleanWhatsAppProfileName("T".repeat(120))?.length, 80);
});

test("profile name enrichment never overwrites a merchant-edited name", () => {
  assert.equal(shouldUseWhatsAppProfileName("", "0648370009"), true);
  assert.equal(
    shouldUseWhatsAppProfileName("WhatsApp 0009", "0648370009"),
    true,
  );
  assert.equal(
    shouldUseWhatsAppProfileName("Thandi Mokoena", "0648370009"),
    false,
  );
});

test("direct inbound WhatsApp records capability before transcript dedupe", () => {
  const source = readFileSync(
    join(sourceRoot, "merchant_hub/logUnreadMessage.ts"),
    "utf8",
  );
  const capabilityWrite = source.indexOf(
    "await storeWhatsAppCapability(String(customerNumber), true)",
  );
  const dedupeCheck = source.indexOf("unreadMessages.some(", capabilityWrite);
  assert.ok(capabilityWrite > 0);
  assert.ok(dedupeCheck > capabilityWrite);
  assert.match(
    source.slice(capabilityWrite - 240, capabilityWrite),
    /resolvedDirection === "inbound"[\s\S]*resolvedChannel === "whatsapp"/,
  );
});
