import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  GOOGLE_SPEECH_LANGUAGE_CODES,
  GOOGLE_SPEECH_MODEL,
  encodingForContentType,
  isTrustedBotpressMediaUrl,
  transcribeVoiceNoteFromMedia,
} from "../lib/bots/transcribeVoiceNoteBotHttp.js";

it("uses multilingual automatic language detection for township voice notes", () => {
  assert.equal(GOOGLE_SPEECH_MODEL, "chirp_3");
  assert.deepEqual(GOOGLE_SPEECH_LANGUAGE_CODES, ["auto"]);
});

const trustedUrl = "https://files.bpcontent.cloud/voice/customer-note";

describe("voice-note transcription", () => {
  it("accepts only the Botpress HTTPS media host", () => {
    assert.equal(isTrustedBotpressMediaUrl(trustedUrl), true);
    assert.equal(
      isTrustedBotpressMediaUrl("https://files.bpcontent.cloud.evil.test/note"),
      false,
    );
    assert.equal(
      isTrustedBotpressMediaUrl("http://files.bpcontent.cloud/note"),
      false,
    );
    assert.equal(isTrustedBotpressMediaUrl("https://127.0.0.1/note"), false);
  });

  it("maps WhatsApp OGG/Opus and WebM/Opus content types", () => {
    assert.equal(encodingForContentType("audio/ogg; codecs=opus"), "OGG_OPUS");
    assert.equal(encodingForContentType("application/ogg"), "OGG_OPUS");
    assert.equal(
      encodingForContentType("audio/webm; codecs=opus"),
      "WEBM_OPUS",
    );
    assert.equal(encodingForContentType("audio/mpeg"), null);
  });

  it("downloads a bounded OGG voice note and returns the transcript", async () => {
    const ogg = Buffer.concat([Buffer.from("OggS"), Buffer.from([0, 1, 2, 3])]);
    let recognitionRequest;
    const result = await transcribeVoiceNoteFromMedia(trustedUrl, {
      fetchImpl: async () =>
        new Response(ogg, {
          status: 200,
          headers: {
            "content-type": "audio/ogg; codecs=opus",
            "content-length": String(ogg.length),
          },
        }),
      recognize: async (request) => {
        recognitionRequest = request;
        return {
          results: [
            {
              languageCode: "xh-ZA",
              alternatives: [
                {
                  transcript: "Ndicela two bags of maize meal",
                  confidence: 0.91,
                },
              ],
            },
          ],
        };
      },
    });

    assert.equal(recognitionRequest.encoding, "OGG_OPUS");
    assert.deepEqual(recognitionRequest.audioContent, ogg);
    assert.deepEqual(result, {
      text: "Ndicela two bags of maize meal",
      confidence: 0.91,
      engine: "google-speech-v2-chirp3",
      languageCode: "xh-ZA",
      languageCodes: ["xh-ZA"],
    });
  });

  it("preserves code-switched transcript segments and detected languages", async () => {
    const ogg = Buffer.concat([Buffer.from("OggS"), Buffer.from([4, 5, 6])]);
    const result = await transcribeVoiceNoteFromMedia(trustedUrl, {
      fetchImpl: async () =>
        new Response(ogg, {
          status: 200,
          headers: { "content-type": "audio/ogg" },
        }),
      recognize: async () => ({
        results: [
          {
            languageCode: "xh-ZA",
            alternatives: [{ transcript: "Ndicela two loaves" }],
          },
          {
            languageCode: "en",
            alternatives: [{ transcript: "please" }],
          },
        ],
      }),
    });

    assert.deepEqual(result, {
      text: "Ndicela two loaves please",
      confidence: 0.75,
      engine: "google-speech-v2-chirp3",
      languageCode: "xh-ZA",
      languageCodes: ["xh-ZA", "en"],
    });
  });

  it("rejects a mismatched container before speech recognition", async () => {
    let called = false;
    await assert.rejects(
      transcribeVoiceNoteFromMedia(trustedUrl, {
        fetchImpl: async () =>
          new Response(Buffer.from("not-an-ogg-file"), {
            status: 200,
            headers: { "content-type": "audio/ogg" },
          }),
        recognize: async () => {
          called = true;
          return {};
        },
      }),
      { message: "audio_container_mismatch" },
    );
    assert.equal(called, false);
  });

  it("rejects declared files above the synchronous recognition limit", async () => {
    await assert.rejects(
      transcribeVoiceNoteFromMedia(trustedUrl, {
        fetchImpl: async () =>
          new Response(Buffer.from("OggS"), {
            status: 200,
            headers: {
              "content-type": "audio/ogg",
              "content-length": String(10 * 1024 * 1024 + 1),
            },
          }),
        recognize: async () => ({}),
      }),
      { message: "audio_too_large" },
    );
  });
});
