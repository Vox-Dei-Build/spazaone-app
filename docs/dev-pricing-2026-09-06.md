# Development pricing diagnosis — 6 September 2026

## Read-only evidence

Explicit project: `spazaone-dev`; registered CLI account:
`tsepo.ntsaba@thedelta.io`. No cloud configuration, credentials, device
registrations, prices or financial data were changed.

- `getMessagingPricingV1` is **ACTIVE**, `us-central1`, Node.js 20. The
  development inventory contains 161 functions.
- All eight messaging-price inputs required by the server are present and
  numerically valid in development Remote Config: the four USD message rates,
  three markup percentages and USD/ZAR exchange rate. Values were not logged.
- The last 100 pricing-function log lines contain three invalid App Check
  token rejection events, at **2026-09-06 10:33:07 UTC**, **10:33:08 UTC** and
  **10:34:29 UTC** (12:33–12:34 South African time). These occur shortly after
  the documented development installation at 12:31 local time.
- No recognized missing-pricing-configuration or pricing-lookup-failed log
  event appeared in that sample. Logs were filtered in memory; only categories,
  counts and timestamps were emitted. No raw logs, tokens or user identifiers
  were printed or stored.

The contemporary App Check rejections strongly indicate a development app/device
verification problem, rather than missing prices or an absent callable. They do
not independently identify which device produced each request. The phone was
disconnected during subsequent investigation, preventing fresh request matching.

## Local corrections

- Preserve safe callable failure categories, including app verification,
  sign-in, shop permission and connection failures. Server response details
  remain private.
- Load messaging rates independently from online-payment fee information.
  A slow or rejected message-price request no longer blocks both sections.
- Retry only the failed section. Paid messaging continues to require a valid
  server snapshot; no fallback message prices or production routing were added.
- Reject fractional and non-finite minor-unit values instead of rounding an
  invalid price into a payable rate.

Local verification: all 14 focused tests pass across messaging schema,
unavailable UI, summary layout and independent loading/retry regressions.
Logs: `/tmp/spaza-pricing-tests.log` and `/tmp/spaza-pricing-analyze.log`.

## Remaining environment verification

After the phone reconnects, confirm the development app/device App Check
authorization through the approved secure workflow. Any new debug-device
registration requires the machine-governance action-time approval; no token was
retrieved and no enforcement bypass was attempted in this investigation.

The closing evidence is a successful authenticated development
`getMessagingPricingV1` request from the installed app, valid displayed message
rates, and no corresponding App Check rejection. Do not send paid messages or
start payment transactions merely to verify the pricing screen.
