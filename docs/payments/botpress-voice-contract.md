# Botpress voice-note contract

Botpress maps an incoming WhatsApp audio message to
`event.payload.audioUrl`. The customer workflow must handle it as follows:

1. When `event.type == "audio"`, POST `event.payload.audioUrl` to
   `transcribeBotpressVoice` with `X-Pasella-Bot-Token`.
2. If the response is `ok: true` and `fallbackRequired: false`, pass
   `transcript` into the same typed-message router. Do not create a second
   ordering, account, address, or payment workflow for voice.
3. If `fallbackRequired` is true, or the endpoint returns an error, send the
   returned `fallback` copy and wait for a typed message or a new voice note.
4. Never log the media URL or copy the audio into Firestore/Storage. Botpress's
   expiring media object is downloaded in memory, transcribed, and discarded.
5. Include `requestId` in internal diagnostics and support escalation; do not
   show provider error details to the customer.

Accepted input is an Ogg Opus voice note no longer than two minutes or 10 MB.
Recognition uses South African English with isiZulu, isiXhosa and Afrikaans
alternatives. The endpoint accepts media only from the configured Botpress
host allow-list and follows no redirects.

QA must exercise unclear audio, silence, oversize/overlength files, an expired
URL, an untrusted URL, typed fallback, all four languages, ordering, accounts,
addresses, payment recovery, and human handoff.

