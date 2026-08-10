import { Buffer } from "node:buffer";
import { SpeechClient, v2 } from "@google-cloud/speech";
import { functions } from "../config/main";
import { requireBotRequest } from "../security/requestAuth";

const MAX_AUDIO_BYTES = 10 * 1024 * 1024;
const MEDIA_FETCH_TIMEOUT_MS = 12_000;
const TRUSTED_MEDIA_HOST = "files.bpcontent.cloud";
const GOOGLE_SPEECH_REGION = "us";
const GOOGLE_SPEECH_FALLBACK_MODEL = "command_and_search";
export const GOOGLE_SPEECH_MODEL = "chirp_3" as const;
export const GOOGLE_SPEECH_LANGUAGE_CODES = ["auto"] as const;

export type VoiceAudioEncoding = "OGG_OPUS" | "WEBM_OPUS";

type RecognizeRequest = {
  encoding: VoiceAudioEncoding;
  audioContent: Buffer;
};

type RecognizeResponse = {
  results?: Array<{
    languageCode?: string | null;
    alternatives?: Array<{
      transcript?: string | null;
      confidence?: number | null;
    }> | null;
  }> | null;
  engine?: "google-speech-v2-chirp3" | "google-speech-v1";
};

type VoiceTranscriptionDependencies = {
  fetchImpl?: typeof fetch;
  recognize?: (request: RecognizeRequest) => Promise<RecognizeResponse>;
};

type VoiceTranscriptionResult = {
  text: string;
  confidence: number;
  engine: "google-speech-v2-chirp3" | "google-speech-v1";
  languageCode: string;
  languageCodes: string[];
};

class VoiceTranscriptionError extends Error {
  constructor(
    public readonly code: string,
    public readonly status: number,
  ) {
    super(code);
  }
}

let speechClient: SpeechClient | undefined;
let multilingualSpeechClient: v2.SpeechClient | undefined;

function getSpeechClient(): SpeechClient {
  speechClient ??= new SpeechClient();
  return speechClient;
}

function getMultilingualSpeechClient(): v2.SpeechClient {
  multilingualSpeechClient ??= new v2.SpeechClient({
    apiEndpoint: `${GOOGLE_SPEECH_REGION}-speech.googleapis.com`,
  });
  return multilingualSpeechClient;
}

function googleProjectId(): string {
  const projectId = String(
    process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? "",
  ).trim();
  if (!/^[a-z][a-z0-9-]{4,62}$/.test(projectId)) {
    throw new Error("google_project_unavailable");
  }
  return projectId;
}

async function recognizeWithGoogleV1(
  request: RecognizeRequest,
): Promise<RecognizeResponse> {
  const [response] = await getSpeechClient().recognize({
    config: {
      encoding: request.encoding,
      sampleRateHertz: 48_000,
      languageCode: "en-ZA",
      model: GOOGLE_SPEECH_FALLBACK_MODEL,
      enableAutomaticPunctuation: true,
    },
    audio: { content: request.audioContent },
  });
  return { ...response, engine: "google-speech-v1" };
}

async function recognizeWithGoogle(
  request: RecognizeRequest,
): Promise<RecognizeResponse> {
  try {
    const projectId = googleProjectId();
    const [response] = await getMultilingualSpeechClient().recognize({
      recognizer: `projects/${projectId}/locations/${GOOGLE_SPEECH_REGION}/recognizers/_`,
      config: {
        autoDecodingConfig: {},
        // Chirp 3 automatically detects and transcribes multilingual speech.
        // This is deliberately not a fixed locale: township voice notes often
        // switch between English and one or more South African languages.
        languageCodes: [...GOOGLE_SPEECH_LANGUAGE_CODES],
        model: GOOGLE_SPEECH_MODEL,
        features: { enableAutomaticPunctuation: true },
      },
      content: request.audioContent,
    });
    return { ...response, engine: "google-speech-v2-chirp3" };
  } catch (error) {
    // Retain the proven South African English path as an availability fallback
    // if the V2 multilingual endpoint itself fails. Do not log audio or text.
    console.warn("[voice-transcription] multilingual recognition failed", {
      serviceCode: recognitionFailureCode(error),
    });
    return recognizeWithGoogleV1(request);
  }
}

function recognitionFailureCode(error: unknown): string {
  if (!error || typeof error !== "object") return "unknown";
  const candidate = error as { code?: unknown; status?: unknown };
  const value = candidate.code ?? candidate.status;
  return String(value ?? "unknown")
    .replace(/[^A-Za-z0-9_-]+/g, "_")
    .slice(0, 48);
}

export function isTrustedBotpressMediaUrl(value: unknown): value is string {
  if (typeof value !== "string" || value.length > 2_048) return false;
  try {
    const url = new URL(value);
    return (
      url.protocol === "https:" &&
      url.hostname.toLowerCase() === TRUSTED_MEDIA_HOST &&
      !url.username &&
      !url.password &&
      !url.port
    );
  } catch {
    return false;
  }
}

export function encodingForContentType(
  value: string | null,
): VoiceAudioEncoding | null {
  const contentType = value?.split(";", 1)[0].trim().toLowerCase();
  if (contentType === "audio/ogg" || contentType === "application/ogg") {
    return "OGG_OPUS";
  }
  if (contentType === "audio/webm" || contentType === "video/webm") {
    return "WEBM_OPUS";
  }
  return null;
}

function hasExpectedContainer(
  audio: Buffer,
  encoding: VoiceAudioEncoding,
): boolean {
  if (encoding === "OGG_OPUS") {
    return (
      audio.length >= 4 && audio.subarray(0, 4).toString("ascii") === "OggS"
    );
  }
  return (
    audio.length >= 4 &&
    audio[0] === 0x1a &&
    audio[1] === 0x45 &&
    audio[2] === 0xdf &&
    audio[3] === 0xa3
  );
}

async function readLimitedBody(response: Response): Promise<Buffer> {
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_AUDIO_BYTES) {
    throw new VoiceTranscriptionError("audio_too_large", 413);
  }
  if (!response.body) {
    throw new VoiceTranscriptionError("media_download_failed", 502);
  }

  const reader = response.body.getReader();
  const chunks: Buffer[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    const chunk = Buffer.from(value);
    total += chunk.length;
    if (total > MAX_AUDIO_BYTES) {
      await reader.cancel();
      throw new VoiceTranscriptionError("audio_too_large", 413);
    }
    chunks.push(chunk);
  }
  if (total === 0) {
    throw new VoiceTranscriptionError("empty_audio", 422);
  }
  return Buffer.concat(chunks, total);
}

function confidenceFromResponse(response: RecognizeResponse): number {
  const values = (response.results ?? [])
    .map((result) => result.alternatives?.[0]?.confidence)
    .filter(
      (confidence): confidence is number =>
        typeof confidence === "number" &&
        Number.isFinite(confidence) &&
        confidence > 0,
    );
  if (!values.length) return 0.75;
  const mean =
    values.reduce((total, value) => total + value, 0) / values.length;
  return Math.max(0, Math.min(1, mean));
}

function languageCodesFromResponse(response: RecognizeResponse): string[] {
  const detected = (response.results ?? [])
    .map((result) => String(result.languageCode ?? "").trim())
    .filter(Boolean);
  const unique = [...new Set(detected)];
  if (unique.length) return unique;
  return response.engine === "google-speech-v1" ? ["en-ZA"] : ["auto"];
}

export async function transcribeVoiceNoteFromMedia(
  mediaUrl: unknown,
  dependencies: VoiceTranscriptionDependencies = {},
): Promise<VoiceTranscriptionResult> {
  if (!isTrustedBotpressMediaUrl(mediaUrl)) {
    throw new VoiceTranscriptionError("invalid_media_url", 400);
  }

  const fetchImpl = dependencies.fetchImpl ?? fetch;
  let mediaResponse: Response;
  try {
    mediaResponse = await fetchImpl(mediaUrl, {
      method: "GET",
      redirect: "error",
      signal: AbortSignal.timeout(MEDIA_FETCH_TIMEOUT_MS),
    });
  } catch {
    throw new VoiceTranscriptionError("media_download_failed", 502);
  }
  if (!mediaResponse.ok) {
    throw new VoiceTranscriptionError("media_download_failed", 502);
  }

  const encoding = encodingForContentType(
    mediaResponse.headers.get("content-type"),
  );
  if (!encoding) {
    throw new VoiceTranscriptionError("unsupported_audio_format", 415);
  }

  const audioContent = await readLimitedBody(mediaResponse);
  if (!hasExpectedContainer(audioContent, encoding)) {
    throw new VoiceTranscriptionError("audio_container_mismatch", 415);
  }

  let recognition: RecognizeResponse;
  try {
    recognition = await (dependencies.recognize ?? recognizeWithGoogle)({
      encoding,
      audioContent,
    });
  } catch (error) {
    // Log only the provider status code. Do not log the media URL, audio,
    // transcript, credentials or provider message.
    console.warn("[voice-transcription] google recognition failed", {
      serviceCode: recognitionFailureCode(error),
    });
    throw new VoiceTranscriptionError("speech_recognition_failed", 502);
  }

  const text = (recognition.results ?? [])
    .map((result) => result.alternatives?.[0]?.transcript?.trim() ?? "")
    .filter(Boolean)
    .join(" ")
    .trim();
  if (!text) {
    throw new VoiceTranscriptionError("no_speech_detected", 422);
  }

  const languageCodes = languageCodesFromResponse(recognition);
  return {
    text,
    confidence: confidenceFromResponse(recognition),
    engine: recognition.engine ?? "google-speech-v2-chirp3",
    languageCode: languageCodes[0],
    languageCodes,
  };
}

export const transcribeVoiceNoteBotHttp = functions
  .runWith({
    secrets: ["PASELLA_BOT_TOKEN"],
    timeoutSeconds: 30,
    memory: "512MB",
  })
  .https.onRequest(async (req, res) => {
    if (!requireBotRequest(req, res)) return;
    if (req.method !== "POST") {
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }

    try {
      const result = await transcribeVoiceNoteFromMedia(req.body?.mediaUrl);
      res.status(200).json(result);
    } catch (error) {
      const known = error instanceof VoiceTranscriptionError;
      const code = known ? error.code : "speech_recognition_failed";
      const status = known ? error.status : 500;
      console.warn("[voice-transcription] request failed", { code });
      res.status(status).json({ error: code });
    }
  });
