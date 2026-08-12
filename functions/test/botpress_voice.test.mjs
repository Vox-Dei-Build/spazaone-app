import assert from "node:assert/strict";
import test from "node:test";
import {
  assessVoiceTranscript,
  oggOpusDurationSeconds,
  validatedBotpressAudioUrl,
} from "../lib/bots/botpress-voice.js";

function oggPage(granuleSamples) {
  const page = Buffer.alloc(29);
  page.write("OggS", 0, "ascii");
  page.writeBigUInt64LE(BigInt(granuleSamples), 6);
  page[26] = 1;
  page[27] = 1;
  page[28] = 0;
  return page;
}

test("Botpress media URLs fail closed against SSRF", () => {
  assert.equal(
    validatedBotpressAudioUrl("https://files.bpcontent.cloud/audio/note.ogg", [
      "bpcontent.cloud",
    ]).hostname,
    "files.bpcontent.cloud",
  );
  for (const invalid of [
    "http://files.bpcontent.cloud/audio.ogg",
    "https://127.0.0.1/audio.ogg",
    "https://bpcontent.cloud.evil.test/audio.ogg",
    "https://user:pass@files.bpcontent.cloud/audio.ogg",
  ]) {
    assert.throws(
      () => validatedBotpressAudioUrl(invalid, ["bpcontent.cloud"]),
      /VOICE_AUDIO_URL_INVALID/,
    );
  }
});

test("Ogg Opus duration enforces the two-minute contract without copying audio", () => {
  assert.equal(oggOpusDurationSeconds(oggPage(48_000 * 120)), 120);
  assert.equal(oggOpusDurationSeconds(oggPage(48_000 * 15)), 15);
  assert.throws(
    () => oggOpusDurationSeconds(Buffer.from("not-an-ogg")),
    /VOICE_AUDIO_INVALID|VOICE_AUDIO_FORMAT_UNSUPPORTED/,
  );
});

test("uncertain or empty transcripts ask the customer to type or resend", () => {
  assert.deepEqual(
    assessVoiceTranscript([
      {
        languageCode: "zu-ZA",
        alternatives: [{ transcript: "Ngifuna ukukhokha", confidence: 0.91 }],
      },
    ]),
    {
      transcript: "Ngifuna ukukhokha",
      confidence: 0.91,
      languageCode: "zu-ZA",
      fallbackRequired: false,
    },
  );
  assert.equal(
    assessVoiceTranscript([
      { alternatives: [{ transcript: "unclear", confidence: 0.4 }] },
    ]).fallbackRequired,
    true,
  );
  assert.equal(assessVoiceTranscript([]).fallbackRequired, true);
});
