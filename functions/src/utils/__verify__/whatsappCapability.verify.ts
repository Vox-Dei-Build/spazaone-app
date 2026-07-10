import {
  classifyWhatsAppCapability,
  WhatsAppCapability,
  WhatsAppCapabilityRecord,
} from "../whatsappCapability";

const now = new Date("2026-06-19T12:00:00.000Z");

const cases: Array<{
  label: string;
  record: WhatsAppCapabilityRecord | null;
  expected: WhatsAppCapability;
}> = [
  {
    label: "no record is unknown",
    record: null,
    expected: "unknown",
  },
  {
    label: "positive record is WhatsApp",
    record: {
      hasWhatsApp: true,
      lastChecked: new Date("2025-01-01T00:00:00.000Z"),
    },
    expected: "whatsapp",
  },
  {
    label: "fresh negative record is SMS",
    record: {
      hasWhatsApp: false,
      lastChecked: new Date("2026-06-01T00:00:00.000Z"),
    },
    expected: "sms",
  },
  {
    label: "stale negative record is unknown",
    record: {
      hasWhatsApp: false,
      lastChecked: new Date("2026-05-01T00:00:00.000Z"),
    },
    expected: "unknown",
  },
  {
    label: "legacy delivered record without capability is unknown",
    record: {},
    expected: "unknown",
  },
  {
    label: "negative record without timestamp is unknown",
    record: { hasWhatsApp: false },
    expected: "unknown",
  },
];

for (const testCase of cases) {
  const actual = classifyWhatsAppCapability(testCase.record, now);
  if (actual !== testCase.expected) {
    throw new Error(
      `${testCase.label}: expected ${testCase.expected}, received ${actual}`,
    );
  }
}

// eslint-disable-next-line no-console
console.log(`Verified ${cases.length} WhatsApp capability cases.`);
