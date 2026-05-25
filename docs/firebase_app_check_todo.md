# Firebase App Check — Activation Backlog

**Status:** Not started. Tracked here, not in a ticket yet.
**Owner:** unassigned
**Priority:** medium — security hardening + likely fixes a class of Crashlytics noise.

## Why this matters

The app talks to Cloud Functions (`getCustomerOrders`, and ~dozens more)
and to Firestore directly. Without App Check, anyone who extracts
`google-services.json` from a shipped APK can call those endpoints from
a script and either scrape merchant data or run up our Functions /
Firestore bill. App Check verifies that requests come from a genuine
build of our app on a genuine device before the backend will accept
them.

## Current state (audit, 2026-05)

- `firebase_app_check: ^0.3.2` is declared in `pubspec.yaml`.
- The plugin is **never `activate`d** in `lib/main.dart`. No provider
  is registered, so no token is ever issued.
- Two files attempt to read a token and attach it as an
  `X-Firebase-AppCheck` header on manual HTTP calls; both currently
  receive `null`:
  - `lib/pages/sales/widgets/online_sales_list.dart:149`
  - `lib/pages/sales/widgets/online_sale_detail_page.dart:49`
- No Cloud Function sets `enforceAppCheck: true`.
- Suspected contributor to the recurring Crashlytics signature
  `[firebase_functions/unknown] java.util.concurrent.ExecutionException:
  1 out of 2 underlying tasks failed`. The Android Functions SDK awaits
  `Tasks.whenAll(authToken, appCheckContext)`; a missing provider can
  fail the AppCheck Task on some builds and nuke the whole call.
  Mitigated for `getCustomerOrders` by the retry in
  `lib/pages/ecommerce/orders_management/data/orders_repository.dart`,
  but the underlying cause is still here.

## Rollout plan

### Phase 1 — Activate, monitor-only

1. In `lib/main.dart`, immediately after `Firebase.initializeApp()`:
   ```dart
   await FirebaseAppCheck.instance.activate(
     androidProvider: kDebugMode
         ? AndroidProvider.debug
         : AndroidProvider.playIntegrity,
     appleProvider: kDebugMode
         ? AppleProvider.debug
         : AppleProvider.deviceCheck, // or .appAttest on iOS 14+
   );
   ```
2. In Firebase Console → App Check, register the Android + iOS apps
   with Play Integrity / DeviceCheck. Leave every service in
   **Unenforced** mode.
3. Generate debug tokens for local dev + CI emulators and add them to
   the console's debug token list. Document the procedure in the
   project README so new contributors don't get locked out.
4. Ship to production. Watch the App Check dashboard for ~1–2 weeks.
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
