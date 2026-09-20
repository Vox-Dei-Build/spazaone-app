import assert from "node:assert/strict";
import test from "node:test";

import {
  parseBotpressProviderPage,
  sanitizeBotpressMessages,
} from "../lib/bots/botpress-conversation-proxy.js";

test("Botpress sanitizer preserves valid messages and isolates malformed rows", () => {
  const result = sanitizeBotpressMessages([
    null,
    { payload: { type: "text", text: "Missing id" } },
    {
      id: "valid-1",
      payload: { type: "text", text: "Hello" },
      createdAt: "2026-09-20T13:20:00.000Z",
      direction: "outgoing",
      tags: { "whatsapp:replyTo": "message-0" },
    },
    {
      id: "sanitized-1",
      payload: {
        type: "carousel",
        title: { unexpected: true },
        items: [{ title: 42, actions: "not-a-list" }, "bad-card"],
      },
      tags: "not-a-map",
    },
  ]);

  assert.equal(result.skippedMessageCount, 2);
  assert.equal(result.sanitizedMessageCount, 1);
  assert.equal(result.messages.length, 2);
  assert.deepEqual(result.messages[0].payload, { type: "text", text: "Hello" });
  assert.deepEqual(result.messages[1].tags, {});
  assert.deepEqual(result.messages[1].payload.items, [
    { title: "42", actions: [] },
  ]);
});

test("Botpress sanitizer converts invalid payloads to a safe empty object", () => {
  const result = sanitizeBotpressMessages([
    { id: "message-1", payload: "unexpected", tags: [] },
  ]);

  assert.equal(result.skippedMessageCount, 0);
  assert.equal(result.sanitizedMessageCount, 1);
  assert.deepEqual(result.messages[0].payload, {});
  assert.deepEqual(result.messages[0].tags, {});
});

test("Botpress provider pages reject malformed top-level contracts", () => {
  assert.throws(
    () => parseBotpressProviderPage({ messages: "not-a-list" }, "messages"),
    /BOTPRESS_PROVIDER_CONTRACT_INVALID/,
  );
  assert.throws(
    () => parseBotpressProviderPage(null, "conversations"),
    /BOTPRESS_PROVIDER_CONTRACT_INVALID/,
  );
});

test("Botpress provider pages preserve items and tolerate malformed metadata", () => {
  assert.deepEqual(
    parseBotpressProviderPage(
      { messages: [{ id: "1" }], meta: [] },
      "messages",
    ),
    { items: [{ id: "1" }], nextToken: undefined },
  );
});
