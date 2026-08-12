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
COMMERCE_PAYMENTS_ENABLED=false
CJ_SANDBOX_MODE=true
CJ_LIVE_FULFILMENT_ENABLED=false
BOTPRESS_PROVIDER_MODE=test
TWILIO_PROVIDER_MODE=test
ACTIVATION_NUDGES_ENABLED=false
ACTIVATION_NUDGES_DRY_RUN=true
```

Paystack, CJ, Botpress and Twilio credentials remain in Secret Manager or the
provider's secure configuration. Do not place them in source control or pass
them in shell arguments. Development rejects a live Paystack key; production
rejects a test key.

The development Payments V2 process-level master is on so sandbox transactions
can be exercised. This does not make a payment public: the global capability
map remains empty by default and each synthetic merchant must be enabled
independently for the exact purpose under test. Production activation remains
separate and dark.

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
development merchant and only Campaign Credits, leaving every real/public
merchant disabled. Rehearse, apply, verify and later roll back with one run ID:

```sh
npm --prefix functions run development:payment-qa -- \
  --project spazaone-dev
npm --prefix functions run development:payment-qa -- \
  --project spazaone-dev --run-id campaign-qa-YYYYMMDD --execute
npm --prefix functions run development:payment-qa -- \
  --project spazaone-dev --run-id campaign-qa-YYYYMMDD --verify
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
- [x] Storage initialized in private-by-default mode and repository Storage
  rules deployed.
- [x] Speech-to-Text enabled for Botpress voice QA.
- [x] Complete dark backend deployed: 114 Functions with Payments V2,
  commerce, reconciliation, notification and voice surfaces.
- [x] Paystack business `1158209` visibly verified as Approved and the Test
  Webhook routed to
  `https://us-central1-spazaone-dev.cloudfunctions.net/verifyPaystackTransaction`.
- [x] Seven-day cleanup policy configured for rebuildable development
  Function container images.
- [ ] App Check debug registrations created for the two development apps.
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
- [ ] Android and iOS device checkout/webhook/refund and WhatsApp text/voice
  journeys verified.

Public payment capabilities remain disabled until every item is complete.
