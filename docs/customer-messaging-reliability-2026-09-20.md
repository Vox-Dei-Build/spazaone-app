# Customer messaging reliability — implementation handover

**Owner:** Spaza One app / Vox Dei
**Production project:** `pasella-ledger`
**Status:** Implemented and prepared for internal release. Production
configuration, backend deployment, and production-store promotion remain
separate actions.

## Implemented behavior

- The Botpress proxy validates provider page contracts, sanitizes each message,
  skips malformed records individually, preserves valid records, and returns
  additive skipped/sanitized counts.
- The Flutter conversation client uses the shared secure function client,
  refreshes credentials once, distinguishes credential, transport, response,
  and mapping failures, preserves partial history, exposes Retry, and clears
  the warning after a successful reload.
- Remote Config pricing reads retry once only when the template read fails.
  Invalid or missing prices fail closed without retrying or inventing a value.
- Flutter pricing calls refresh Auth and App Check once for retryable credential
  or transport failures. Invalid pricing responses fail closed.
- Transaction confirmation pricing failures offer Try again, Save without
  sending, and Keep editing. Payment requests remain unsent and expose Try
  again.
- Payment-request failures expose safe machine-readable codes while retaining
  calm customer-facing copy. Credential replay keeps the original idempotency
  key.
- Diagnostics contain only controlled surface, stage, code, retry outcome, and
  skipped-count values. App version/build are supplied by the existing global
  Crashlytics build context. Phone numbers, customer identifiers, message
  bodies, tokens, and pricing values are excluded.

## Verification and release gates

The registered `spazaone-dev` Android and iOS configs were downloaded through
the authenticated Firebase CLI, and the repository guard materialized the
ignored development `.env` without printing configuration values.

Local verification completed:

- 52 focused Flutter and Firebase-environment tests passed;
- 18 Functions messaging-reliability tests passed;
- 20 Functions security tests passed;
- 89 Payments V2 policy tests passed;
- Functions TypeScript build passed;
- the complete Flutter analyzer reported no errors or warnings (existing
  repository information-level lints remain);
- the Functions linter reported no errors and no findings in the changed
  files (existing warnings remain elsewhere); and
- the development Android debug APK and Flutter web build completed.

These checks cover partial/malformed Botpress history, provider contract
failure, credential recovery, warning recovery, transient, persistent, and
invalid pricing, both pricing surfaces, save-without-send, and idempotent
payment retry.

Before deployment, re-run the complete local checks using a properly
materialized development environment. Deploy the exact verified revision to
development first. A Play-signed internal build with synthetic merchant and
customer data must then prove App Check exchange, pricing retrieval, and
conversation loading without sending a paid message.

Production Firebase changes, Functions deployment, and Play release each
require their own action-time authorization.
