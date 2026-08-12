import * as admin from "firebase-admin";
import axios from "axios";
import { randomUUID } from "crypto";
import { functions } from "../config/main";
import { requireBotRequest } from "../security/requestAuth";

const MAX_AUDIO_BYTES = 10 * 1024 * 1024;
const MAX_AUDIO_SECONDS = 120;
const SPEECH_OPERATION_TIMEOUT_MS = 150_000;
const DEFAULT_MEDIA_HOSTS = [
  "api.botpress.cloud",
  "cdn.botpress.cloud",
  "files.bpcontent.cloud",
  "bpcontent.cloud",
];

type SpeechAlternative = { transcript?: unknown; confidence?: unknown };
type SpeechResult = {
  alternatives?: SpeechAlternative[];
  languageCode?: unknown;
};

export type VoiceTranscriptAssessment = {
  transcript: string;
  confidence: number;
  languageCode: string;
  fallbackRequired: boolean;
};

function configuredMediaHosts(): string[] {
  const configured = String(process.env.BOTPRESS_MEDIA_HOSTS ?? "")
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean);
  return configured.length ? configured : DEFAULT_MEDIA_HOSTS;
}

export function validatedBotpressAudioUrl(
  value: unknown,
  allowedHosts = configuredMediaHosts(),
): URL {
  let url: URL;
  try {
    url = new URL(String(value ?? ""));
  } catch (_) {
    throw new Error("VOICE_AUDIO_URL_INVALID");
  }
  const host = url.hostname.toLowerCase();
  const allowed = allowedHosts.some(
    (suffix) => host === suffix || host.endsWith(`.${suffix}`),
  );
  if (
    url.protocol !== "https:" ||
    !allowed ||
    url.username ||
    url.password ||
    url.port
  ) {
    throw new Error("VOICE_AUDIO_URL_INVALID");
  }
  return url;
}

/** WhatsApp voice notes are Ogg Opus. The final Ogg page granule is the
 * decoded sample count at 48 kHz, so duration can be bounded without ffmpeg. */
export function oggOpusDurationSeconds(audio: Buffer): number {
  let offset = 0;
  let finalGranule = BigInt(0);
  let pages = 0;
  while (offset + 27 <= audio.length) {
    if (audio.toString("ascii", offset, offset + 4) !== "OggS") {
      throw new Error("VOICE_AUDIO_FORMAT_UNSUPPORTED");
    }
    const segmentCount = audio[offset + 26];
    const headerLength = 27 + segmentCount;
    if (offset + headerLength > audio.length) {
      throw new Error("VOICE_AUDIO_INVALID");
    }
    let bodyLength = 0;
    for (let index = 0; index < segmentCount; index += 1) {
      bodyLength += audio[offset + 27 + index];
    }
    const pageLength = headerLength + bodyLength;
    if (pageLength <= headerLength || offset + pageLength > audio.length) {
      throw new Error("VOICE_AUDIO_INVALID");
    }
    const granule = audio.readBigUInt64LE(offset + 6);
    if (granule > finalGranule) finalGranule = granule;
    pages += 1;
    offset += pageLength;
  }
  if (pages === 0 || offset !== audio.length || finalGranule <= BigInt(0)) {
    throw new Error("VOICE_AUDIO_INVALID");
  }
  return Number(finalGranule) / 48_000;
}

export function assessVoiceTranscript(
  resultsValue: unknown,
): VoiceTranscriptAssessment {
  const results = Array.isArray(resultsValue)
    ? (resultsValue as SpeechResult[])
    : [];
  const alternatives = results
    .map((result) => result.alternatives?.[0])
    .filter((value): value is SpeechAlternative => value != null);
  const transcript = alternatives
    .map((value) => String(value.transcript ?? "").trim())
    .filter(Boolean)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();
  const confidences = alternatives
    .map((value) => Number(value.confidence))
    .filter((value) => Number.isFinite(value) && value >= 0 && value <= 1);
  const confidence = confidences.length
    ? confidences.reduce((sum, value) => sum + value, 0) / confidences.length
    : 0;
  const languageCode = String(
    results.find((result) => String(result.languageCode ?? "").trim())
      ?.languageCode ?? "en-ZA",
  );
  return {
    transcript,
    confidence,
    languageCode,
    fallbackRequired: !transcript || confidence < 0.65,
  };
}

async function accessToken(): Promise<string> {
  const credential = admin.app().options.credential;
  if (!credential) throw new Error("SPEECH_AUTH_UNAVAILABLE");
  const token = await credential.getAccessToken();
  if (!token.access_token) throw new Error("SPEECH_AUTH_UNAVAILABLE");
  return token.access_token;
}

async function transcribeOggOpus(
  audio: Buffer,
): Promise<VoiceTranscriptAssessment> {
  const token = await accessToken();
  const started = await axios.post(
    "https://speech.googleapis.com/v1/speech:longrunningrecognize",
    {
      config: {
        encoding: "OGG_OPUS",
        sampleRateHertz: 48_000,
        languageCode: "en-ZA",
        alternativeLanguageCodes: ["zu-ZA", "xh-ZA", "af-ZA"],
        model: "command_and_search",
        maxAlternatives: 1,
        enableAutomaticPunctuation: true,
      },
      audio: { content: audio.toString("base64") },
    },
    {
      headers: { Authorization: `Bearer ${token}` },
      timeout: 15_000,
      maxBodyLength: 15 * 1024 * 1024,
    },
  );
  const operationName = String(started.data?.name ?? "");
  if (!/^operations\/[A-Za-z0-9._/-]+$/.test(operationName)) {
    throw new Error("SPEECH_OPERATION_INVALID");
  }
  const deadline = Date.now() + SPEECH_OPERATION_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const operation = await axios.get(
      `https://speech.googleapis.com/v1/${operationName}`,
      {
        headers: { Authorization: `Bearer ${token}` },
        timeout: 10_000,
      },
    );
    if (operation.data?.done === true) {
      if (operation.data?.error) throw new Error("SPEECH_PROVIDER_REJECTED");
      return assessVoiceTranscript(operation.data?.response?.results);
    }
    await new Promise((resolve) => setTimeout(resolve, 1_000));
  }
  throw new Error("SPEECH_OPERATION_TIMEOUT");
}

function publicVoiceFailure(code: string): { status: number; message: string } {
  if (code === "VOICE_AUDIO_URL_INVALID") {
    return { status: 400, message: "That voice note link is not trusted." };
  }
  if (code === "VOICE_AUDIO_TOO_LARGE" || code === "VOICE_AUDIO_TOO_LONG") {
    return {
      status: 413,
      message: "Please send a voice note shorter than two minutes and 10 MB.",
    };
  }
  if (
    code === "VOICE_AUDIO_FORMAT_UNSUPPORTED" ||
    code === "VOICE_AUDIO_INVALID"
  ) {
    return {
      status: 422,
      message:
        "I could not read that voice note. Please resend it or type your message.",
    };
  }
  return {
    status: 503,
    message:
      "Voice notes are temporarily unavailable. Please type your message.",
  };
}

export const transcribeBotpressVoice = functions
  .runWith({
    timeoutSeconds: 180,
    memory: "512MB",
    secrets: ["PASELLA_BOT_TOKEN"],
  })
  .https.onRequest(async (req, res) => {
    const requestId = randomUUID();
    if (req.method !== "POST") {
      res.status(405).json({
        ok: false,
        code: "METHOD_NOT_ALLOWED",
        requestId,
        fallback: "Please type your message.",
      });
      return;
    }
    if (!requireBotRequest(req, res)) return;

    let sizeBytes = 0;
    let durationSeconds = 0;
    try {
      const audioUrl = validatedBotpressAudioUrl(req.body?.audioUrl);
      const download = await axios.get<ArrayBuffer>(audioUrl.toString(), {
        responseType: "arraybuffer",
        timeout: 15_000,
        maxRedirects: 0,
        maxContentLength: MAX_AUDIO_BYTES,
        headers: { Accept: "audio/ogg,application/ogg,audio/opus" },
      });
      const contentType = String(download.headers["content-type"] ?? "")
        .split(";")[0]
        .trim()
        .toLowerCase();
      if (
        !new Set(["audio/ogg", "application/ogg", "audio/opus"]).has(
          contentType,
        )
      ) {
        throw new Error("VOICE_AUDIO_FORMAT_UNSUPPORTED");
      }
      const audio = Buffer.from(download.data);
      sizeBytes = audio.byteLength;
      if (!sizeBytes || sizeBytes > MAX_AUDIO_BYTES) {
        throw new Error("VOICE_AUDIO_TOO_LARGE");
      }
      durationSeconds = oggOpusDurationSeconds(audio);
      if (
        !Number.isFinite(durationSeconds) ||
        durationSeconds > MAX_AUDIO_SECONDS
      ) {
        throw new Error("VOICE_AUDIO_TOO_LONG");
      }
      const assessment = await transcribeOggOpus(audio);
      console.info("[botpress-voice] transcription completed", {
        requestId,
        sizeBytes,
        durationSeconds: Math.round(durationSeconds),
        languageCode: assessment.languageCode,
        fallbackRequired: assessment.fallbackRequired,
      });
      res.status(200).json({
        ok: true,
        requestId,
        ...assessment,
        fallback: assessment.fallbackRequired
          ? "I could not hear that clearly. Please resend the voice note or type your message."
          : null,
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : "VOICE_UNKNOWN";
      const failure = publicVoiceFailure(code);
      console.error("[botpress-voice] transcription failed", {
        requestId,
        code,
        sizeBytes,
        durationSeconds: Math.round(durationSeconds),
        providerStatus: axios.isAxiosError(error)
          ? Number(error.response?.status) || null
          : null,
      });
      res.status(failure.status).json({
        ok: false,
        requestId,
        code,
        fallback: failure.message,
      });
    }
  });
