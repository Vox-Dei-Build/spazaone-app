import assert from "node:assert/strict";
import test from "node:test";
import { sanitizePresentation } from "../lib/merchant_hub/logUnreadMessage.js";

test("truth surface keeps visible content and drops provider action values", () => {
  const sanitized = sanitizePresentation({
    schemaVersion: 1,
    type: "choices",
    text: "Choose one",
    options: [
      {
        label: "Pay online",
        description: "Secure checkout",
        value: "execute:payment:secret",
      },
    ],
  });
  assert.deepEqual(sanitized, {
    schemaVersion: 1,
    type: "choices",
    text: "Choose one",
    options: [{ label: "Pay online", description: "Secure checkout" }],
    cards: [],
  });
  assert.equal(JSON.stringify(sanitized).includes("secret"), false);
});

test("truth surface rejects oversized or unsafe rich payloads", () => {
  assert.equal(
    sanitizePresentation({
      schemaVersion: 1,
      type: "image",
      mediaUrl: "file:///tmp/raw-audio.aiff",
    })?.mediaUrl,
    undefined,
  );
  assert.equal(
    sanitizePresentation({
      schemaVersion: 1,
      type: "text",
      text: "x".repeat(40_000),
    }),
    null,
  );
  assert.equal(
    sanitizePresentation({ schemaVersion: 1, type: "execute_payment" }),
    null,
  );
});

test("truth surface keeps only bounded reply references and valid locations", () => {
  assert.deepEqual(
    sanitizePresentation({
      schemaVersion: 1,
      type: "location",
      text: "Johannesburg",
      replyToId: "message_123:reply",
      latitude: -26.2041,
      longitude: 28.0473,
    }),
    {
      schemaVersion: 1,
      type: "location",
      text: "Johannesburg",
      replyToId: "message_123:reply",
      latitude: -26.2041,
      longitude: 28.0473,
      options: [],
      cards: [],
    },
  );
  const unsafe = sanitizePresentation({
    schemaVersion: 1,
    type: "location",
    replyToId: "execute payment now",
    latitude: 999,
    longitude: 999,
  });
  assert.equal(unsafe.replyToId, undefined);
  assert.equal(unsafe.latitude, undefined);
});
