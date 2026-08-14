# SpazaOne Development lane

The permanent cloud development project is `spazaone-dev`. Production remains
the legacy Firebase project `pasella-ledger`; the legacy identifier must never
appear in a development runtime contract.

## Applications

| Lane | Display name | Android application ID | iOS bundle ID | Firebase project |
| --- | --- | --- | --- | --- |
| Development | SpazaOne Dev | `com.tsepo.spazaone.dev` | `com.tsepo.spazaone.dev` | `spazaone-dev` |
| Production | SpazaOne | `com.tsepo.pasella` | `com.tsepo.pasella` | `pasella-ledger` |

The Android product flavors and iOS schemes enforce this matrix. Dart also
validates it before connecting, then verifies the same environment and project
against the deployed `getEnvironmentInfo` Function. Development builds display
a persistent DEV banner.

The downloaded development Firebase configuration files and generated `.env`
files are ignored. Materialize app configuration from the registered Firebase
apps with:

```sh
ruby tool/materialize_development_env.rb
```

No command may use a mutable Firebase default. Every Firebase command must
include `--project spazaone-dev`; local emulator commands use an explicit
`demo-*` project instead.

## Build commands

```sh
flutter build apk --debug --flavor development \
  --dart-define=SPAZAONE_ENVIRONMENT=development

LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
flutter build ios --debug --flavor development --no-codesign \
  --dart-define=SPAZAONE_ENVIRONMENT=development
```

Production CI uses the production flavor and
`SPAZAONE_ENVIRONMENT=production`. A development Firebase project, Firebase
emulator setting or test provider mode makes a production runtime fail closed.

## Backend contract

The development Functions environment must set these non-secret values:

```dotenv
SPAZAONE_ENVIRONMENT=development
SPAZAONE_FIREBASE_PROJECT_ID=spazaone-dev
PAYSTACK_PROVIDER_MODE=test
PAYMENTS_V2_MASTER_ENABLED=true
COMMERCE_PAYMENTS_ENABLED=true
CJ_SANDBOX_MODE=true
CJ_LIVE_FULFILMENT_ENABLED=false
BOTPRESS_PROVIDER_MODE=test
CUSTOMER_PAYMENT_REQUESTS_ENABLED=true
ACTIVATION_NUDGES_ENABLED=false
ACTIVATION_NUDGES_DRY_RUN=true
```

Paystack, CJ and Botpress credentials remain in Secret Manager or the
provider's secure configuration. Direct Botpress WhatsApp is the supported
payment-request lane; Twilio is optional SMS fallback and is not a release
dependency. Do not place credentials in source control or pass them in shell
arguments. Development rejects a live Paystack key; production rejects a test
key.

The development Payments V2 and supplier-commerce process-level gates are on
so sandbox transactions can be exercised. This does not make a payment public:
the global capability map remains empty by default and each synthetic merchant
must be enabled independently for the exact purpose under test. CJ remains in
sandbox mode and production activation remains separate and dark.

## Local verification

With JDK 21 available, the complete local seed/migration/payments/rules
rehearsal is:

```sh
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH \
firebase emulators:exec \
  --config firebase.development.json \
  --project demo-spazaone-qa \
  ./functions/scripts/run-local-development-verification.sh
```

The migration command is dry-run by default. Development apply, verify and
replay use the same run ID. Production apply additionally requires explicit
backup evidence and action-time confirmation.

Cloud Paystack QA is also dry-run by default. It enables only the synthetic
development merchant, leaving every real/public merchant disabled. The 4.8.0
candidate exercises all four coupled capabilities with an already verified
Paystack Test subaccount. Rehearse, apply, verify and later roll back with one
run ID:

```sh
npm --prefix functions run development:payment-qa -- \
  --project spazaone-dev
npm --prefix functions run development:payment-qa -- \
  --project spazaone-dev --run-id commerce-qa-YYYYMMDD \
  --capabilities campaign_credit,merchant_order,account_settlement,supplier_order \
  --test-subaccount-code <verified-test-subaccount-code> --execute
npm --prefix functions run development:payment-qa -- \
  --project spazaone-dev --run-id commerce-qa-YYYYMMDD \
  --capabilities campaign_credit,merchant_order,account_settlement,supplier_order \
  --test-subaccount-code <verified-test-subaccount-code> --verify
```

The campaign smoke command creates a bounded R10 test-mode checkout and writes
the short-lived checkout handoff to an explicitly supplied mode-`0600`
temporary file. It never prints Firebase tokens or the checkout URL:

```sh
npm --prefix functions run development:campaign-smoke -- \
  --project spazaone-dev
```

The separate verifier polls durable Firestore evidence and fails unless the
intent, one immutable provider event, purchase, wallet operation, top-up
transaction and temporary-auth cleanup all agree. It also stops on a single
cent of quoted-versus-actual processor-fee variance:

```sh
GOOGLE_CLOUD_QUOTA_PROJECT=spazaone-dev \
npm --prefix functions run development:campaign-smoke:verify -- \
  --project spazaone-dev --handoff /absolute/mode-0600/checkout.json
```

### Paystack Test evidence — 12 August 2026

- The development Test secret is stored without leading/trailing whitespace,
  starts with the Test-only prefix, and active version 3 is bound to all eight
  Paystack-aware development functions. Stale versions 1 and 2 are disabled;
  a direct read-only provider probe through version 3 returned HTTP 200.
- A deliberately observed formatting failure proved the webhook fails closed:
  a one-byte trailing newline caused three signed deliveries to return 401 and
  produced no credit. After the secret was corrected and the functions were
  rebound, Paystack retried the same event, received 200 and applied it once.
- The first R10.24 EFT run exposed a one-cent quote variance: Paystack reported
  a 25-cent processor fee instead of the quoted 24 cents. That run is retained
  as failed synthetic evidence; it is not a releasable economics result.
- The fee calculator now mirrors Paystack's observed cent boundaries by
  rounding the ex-VAT fee and VAT component separately. The repeat run charged
  R10.25, reported an actual 25-cent processor fee, credited exactly R10.00,
  recorded exactly one immutable event and passed the durable verifier.
- No live key, live charge or production Firebase resource was used.

### Commerce candidate evidence — 13 August 2026

- Cloud seed `commerce-20260813-b`, additive migration
  `payments-v2-20260813-a`, 50-product bot catalogue
  `bot-catalog-20260813-a`, and payment-capability setup
  `commerce-payments-20260813-b` all applied and verified in `spazaone-dev`.
- The cloud failure rehearsal `commerce-failures-20260813-b` proved invalid
  bot authority, the kill switch, an unverified settlement destination,
  overpayment, an invalid channel and unavailable inventory all stop before a
  provider charge.
- Account-payment run `account-settlement-20260813-b` charged R40.00 in
  Paystack Test Mode and reconciled one intent, one signed event, one customer
  ledger movement, one settlement, one required notification and zero refunds.
- Owned-stock run `owned-order-20260813-d` charged R16.00 in Paystack Test Mode
  and reconciled one intent, one signed event, one settlement, one required
  notification, one committed reservation, exactly one stock decrement and
  zero refunds. Reservations now record immutable `availableBefore` and
  `availableAfter` quantities, and every cloud smoke run uses an isolated
  synthetic product so interrupted runs cannot contaminate later evidence.
- The supplier rehearsal stopped before Paystack initialization because the
  CJ sandbox account could not cover the USD 5.76 supplier commitment. It
  created one immutable internal intent in `created` state but no funding
  reservation, provider reference or charge. The buyer-safe response now
  states that supplier checkout is temporarily unavailable and that no charge
  occurred, without exposing provider funding details.
- Flutter tests passed 297/297; Functions quality gates passed 155/155;
  Firestore/Storage rules passed 15/15; Payments V2 emulator integration
  passed 11/11; Botpress tests passed 336/336; both production and development
  ADK builds passed. Android development APK and unsigned iOS development app
  builds also completed. `flutter analyze` has no warnings or errors and
  retains 273 pre-existing informational lints.

Guarded development deployments use the separately registered target:

```sh
/Users/admin/.codex/identity-governance/bin/codex-guard firebase-deploy \
  --project spaza-one --environment firebase_development -- \
  --only functions --config firebase.development.json
```

Production remains the guard's default Firebase target. The development
selector resolves immutably to `spazaone-dev` and cannot accept a caller-
supplied Firebase project or account override.

## Cloud completion checklist

- [x] Firebase project `spazaone-dev` created.
- [x] Android and iOS development apps registered and configurations
  materialized locally.
- [x] Firestore and Remote Config enabled.
- [x] Firestore rules, indexes and fail-closed Remote Config deployed
  explicitly to `spazaone-dev`.
- [x] Firebase Blaze linked to the existing `The Delta Studio- Pasella`
  billing account for `spazaone-dev` only.
- [x] Cloud Functions, Cloud Build, Artifact Registry, Cloud Run, Eventarc,
  Pub/Sub and Secret Manager APIs enabled for the development project.
- [x] `getEnvironmentInfo` deployed and externally verified as SpazaOne,
  development, `spazaone-dev`, with every provider in test mode.
- [x] Authentication initialized with Phone sign-in and development Android
  SHA-1/SHA-256 fingerprints registered.
- [x] Phone Auth restricted to an explicit South Africa SMS allowlist and real
  OTP delivery plus automatic verification proved on the physical Android
  development app. A separate fictional Firebase test identity exists for
  development automation; its fixed code is stored only in the macOS
  Keychain. No real phone number or OTP is retained in repository evidence.
- [x] Storage initialized in private-by-default mode and repository Storage
  rules deployed.
- [x] Speech-to-Text enabled for Botpress voice QA.
- [x] Complete dark backend deployed with Payments V2, commerce,
  reconciliation, notification and voice surfaces. Re-count from the exact
  candidate at deploy time rather than relying on a stale fixed total.
- [x] Development client presentation and all four client rollback gates are
  enabled. The synthetic merchant has matching server capabilities; every
  other merchant still fails closed without explicit server authorization.
- [x] The development commerce hub exposes truthful per-purpose readiness,
  buyer-safe disabled reasons, server-approved channels, Payment Setup actions
  and combined owned/supplier order reporting. Production client defaults and
  all production capability controls remain disabled.
- [x] Paystack business `1158209` visibly verified as Approved and the Test
  Webhook routed to
  `https://us-central1-spazaone-dev.cloudfunctions.net/verifyPaystackTransaction`.
- [x] Seven-day cleanup policy configured for rebuildable development
  Function container images.
- [x] Android development App Check debug registration created and token
  exchange proved on the physical Samsung without recording the token.
- [ ] iOS development App Check debug registration and device proof complete.
- [ ] Complete provider-side Paystack key rotation. The current dashboard's
  rotation control rotates both Test and Live secret keys together and asks
  for the account password, so it cannot be used as a Test-only automation
  action. The current Test secret has been securely synchronized and verified
  for sandbox work, but production activation remains blocked until the
  provider offers a Test-only rotation or the account owner completes the
  combined rotation directly. No live key was accessed or changed.
- [x] Paystack Test secret formatting, binding, signed-webhook retry,
  single-event idempotency and exact R10.00 EFT credit reconciliation verified.
- [x] CJ sandbox credential, unique development backend token, Botpress token
  and Twilio auth token stored in development Secret Manager without
  source-control exposure.
- [x] Separate Botpress ADK bot `SpazaOne Development` provisioned as
  `6232ab3d-0da9-41e8-a80d-4699be36b7ee`, backed by `spazaone-dev`.
- [x] Direct Botpress WhatsApp integration attached to both the development bot
  and production bot `402deb8c-c6b2-45d3-85ce-d090b99e25b0`. Direct WhatsApp
  is the supported release lane; Twilio is compatibility-only and is not a
  release dependency.
- [x] Synthetic seed and migration rehearsal completed in the cloud project,
  including verified idempotent replay.
- [x] Android development APK and unsigned iOS device app produced from
  `4.8.0+88`; app tests and environment fail-closed checks pass.
- [x] Paystack Test hosted checkout/webhook/reconciliation verified for
  Campaign Credits, owned stock and account settlement.
- [x] A complete 30-day development reconciliation checked 16 intents with zero
  mismatches and no truncation. The audited on-demand receipt and retry binding
  pass unit/emulator integration; live callable proof awaits an explicitly
  authorized development admin identity.
- [ ] Android and iOS exact signed-candidate checkout/refund journeys verified.
- [ ] WhatsApp text/voice journeys verified against the exact candidate and
  the isolated SpazaOne Development bot.
- [ ] Fund the CJ sandbox account and complete supplier create/pay/tracking,
  deterministic failure/refund and ambiguous-provider recovery evidence.

Production payment capabilities remain disabled until every item is complete.
Only the named synthetic development merchant has development capabilities.
