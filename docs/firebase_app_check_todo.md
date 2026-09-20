# Firebase App Check — Activation Backlog

**Status:** Development rollout active; security-sensitive production HTTP
endpoints enforce App Check. Broader Firebase-service enforcement remains a
separate release gate.
**Owner:** Engineering/Security release gate
**Priority:** release evidence and production hardening.

## Why this matters

The app talks to Cloud Functions (`getCustomerOrders`, and ~dozens more)
and to Firestore directly. Without App Check, anyone who extracts
`google-services.json` from a shipped APK can call those endpoints from
a script and either scrape merchant data or run up our Functions /
Firestore bill. App Check verifies that requests come from a genuine
build of our app on a genuine device before the backend will accept
them.

## Current state (verified, 2026-08)

- `firebase_app_check: ^0.3.2` is declared in `pubspec.yaml`.
- The plugin is activated after Firebase initialization. Debug builds and the
  isolated development flavor use registered debug providers, including
  release-mode APKs installed directly for device QA. Production release builds
  use Play Integrity on Android and App Attest on iOS.
- Manual HTTP clients attach an `X-Firebase-AppCheck` header where required:
  - `lib/pages/sales/widgets/online_sales_list.dart:149`
  - `lib/pages/sales/widgets/online_sale_detail_page.dart:49`
- Security-sensitive HTTP payment and bot endpoints verify App Check now. The
  broader Firebase services remain in monitoring mode while old production
  builds age out.
- The physical Android development token is registered in `spazaone-dev` and a
  clean restart proved token exchange without exposing the token.
- The exact signed iOS `4.8.0+88` development app is installed and launches on
  a physical iPhone. The detached device runner did not surface its debug token,
  so iOS registration/exchange remains an explicit release-evidence task.
- Suspected contributor to the recurring Crashlytics signature
  `[firebase_functions/unknown] java.util.concurrent.ExecutionException:
  1 out of 2 underlying tasks failed`. The Android Functions SDK awaits
  `Tasks.whenAll(authToken, appCheckContext)`; a missing provider can
  fail the AppCheck Task on some builds and nuke the whole call.
  Mitigated for `getCustomerOrders` by the retry in
  `lib/pages/ecommerce/orders_management/data/orders_repository.dart`,
  but the underlying cause is still here.

## Production Android registration audit — 20 September 2026

Read-only Firebase CLI checks, using the registered Spaza One operational
account, verified the following in `pasella-ledger`:

- the Firebase Android app exists for package `com.tsepo.pasella` with app ID
  `1:716158514645:android:a4f2b4756aafcebbe5795c`;
- three SHA-256 certificate fingerprints are registered for that Android app;
- production release code activates `AndroidProvider.playIntegrity`; and
- the security-sensitive Botpress and customer-payment HTTP endpoints require
  App Check and keep enforcement enabled.

The Firebase CLI does not expose the Play Integrity provider's Google Play
link, the Play App Signing certificate label, or the Play-only
recognition/licensing toggles. Therefore the registered fingerprints alone do
not prove that one is the current Play App Signing SHA-256. Before a Play-signed
internal verification build, an authorized operator must confirm in the
Firebase and Play consoles that:

1. Play Integrity for `com.tsepo.pasella` is linked to `pasella-ledger`.
2. The current Play App Signing SHA-256 exactly matches a Firebase App Check
   registration.
3. Play-only recognition and licensing settings match the approved release
   policy.

No production configuration was changed during this audit.

## Rollout plan

### Phase 1 — Activate, monitor-only

1. In Firebase Console → App Check, register the Android + iOS apps
   with Play Integrity / DeviceCheck. Leave every service in
   **Unenforced** mode.
2. Generate debug tokens for local dev + CI emulators and add them to
   the console's debug token list. Document the procedure in the
   project README so new contributors don't get locked out.
3. Ship to production. Watch the App Check dashboard for ~1–2 weeks.
   Wait for ≥99% verified per service before moving on.

### Phase 2 — Enforce, service by service

- Start with the lowest-blast-radius service (Storage, or one
  callable). For callables, add `enforceAppCheck: true` to the
  function's options in `functions/src/...`.
- Then Firestore, then the remaining callables.
- Enforcement can be flipped back off in one click in the Console if
  anything regresses.

### Phase 3 — Cleanup

- The SDKs attach `X-Firebase-AppCheck` automatically for Firebase
  calls. The manual header code in `online_sales_list.dart` /
  `online_sale_detail_page.dart` is only needed if those endpoints are
  **non-Firebase** HTTP services we own. Audit and either:
  - keep the header code if they're our own non-Firebase endpoints, or
  - delete it if they're Firebase callables and the SDK is now doing
    it for us.
- Re-check Crashlytics for the
  `firebase_functions/unknown … 1 out of 2 underlying tasks failed`
  signature; consider removing the retry workaround in
  `orders_repository.dart` if the underlying error has disappeared.

## Gotchas to remember before scheduling

- **Play Integrity quota.** Free tier is limited per project per day
  (check current Google Play pricing before enforcing). Tokens cache
  ~1 hour so a merchant app rarely hits it, but verify for our DAU.
- **iOS App Attest** needs iOS 14+. Use `deviceCheck` as fallback or
  branch on OS version.
- **Old app versions in the wild** will not have App Check activated
  until users upgrade. Do not enforce until the long tail has flushed
  out, or until forced-upgrade is in place.
- **Local development** breaks the first time a contributor runs
  against an enforced project without a registered debug token. Phase 1
  must include onboarding docs.

## Decision log

- **2026-05:** Punted. Other priorities. Repository-level retry added
  to `orders_repository.dart` as a stopgap for the most visible
  symptom. Revisit when there's bandwidth or when the crash signature
  resurfaces above threshold.
