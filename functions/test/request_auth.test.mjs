import assert from "node:assert/strict";
import {afterEach, test} from "node:test";
import requestAuth from "../lib/security/requestAuth.js";

const originalSecret = process.env.PASELLA_BOT_TOKEN;

afterEach(() => {
  if (originalSecret === undefined) {
    delete process.env.PASELLA_BOT_TOKEN;
  } else {
    process.env.PASELLA_BOT_TOKEN = originalSecret;
  }
});

const requestWithToken = (token) => ({
  get: (name) =>
    name.toLowerCase() === "x-pasella-bot-token" ? token : undefined,
});

test(
  "accepts an HTTP-safe token when the stored secret has surrounding whitespace",
  () => {
    process.env.PASELLA_BOT_TOKEN = "  release-token\n";
    assert.equal(
      requestAuth.verifyBotRequest(requestWithToken("release-token")),
      true,
    );
  },
);

test("does not normalize whitespace inside a bot token", () => {
  process.env.PASELLA_BOT_TOKEN = "release-token";
  assert.equal(requestAuth.verifyBotRequest(requestWithToken("release token")), false);
});

test("rejects missing and whitespace-only bot tokens", () => {
  process.env.PASELLA_BOT_TOKEN = "\n";
  assert.equal(requestAuth.verifyBotRequest(requestWithToken("")), false);
  assert.equal(requestAuth.verifyBotRequest(requestWithToken(undefined)), false);
});
