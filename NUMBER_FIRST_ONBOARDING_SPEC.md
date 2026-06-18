# PAS-UX-22 — Number-First Onboarding Spec

Status: design / spec — no code changes in this packet.
Worktree: `pasella-app-worktrees/number-first-onboarding`
Owner of next build slice: TBD.

---

## 1. Current-state summary

Pasella's pre-auth surface is two screens reached via `MaterialApp.initialRoute`:

| Route | File | What it does |
|---|---|---|
| `/loginPage` (initial) | `lib/pages/auth/login/login.dart` | Phone-only form. On submit, looks up Firestore `users` to confirm number is registered, then triggers Firebase phone OTP, then prompts for the SMS code in an `AlertDialog`. |
| `/registerPage` | `lib/pages/auth/register/register.dart` | Full Name + Business Name + Phone form. Same lookup, but inverted: rejects if number *is* registered. Then OTP, then writes `users/{uid}` doc + initial wallet. |
| `/registerAnonymousPage` | `lib/pages/auth/registerAnonymous/register_anonymous.dart` | Reached only from the `Explore` button (feature-flagged off via `FeatureFlags.enableAnonymousGate`). Upgrades an anonymous Firebase user to a phone-OTP account by linking. |

All three share one view-model: `lib/pages/auth/view_model/auth_view_model.dart`. The same OTP dialog (`_promptForVerificationCode`, `auth_view_model.dart:333`) is reused across login, register and link-anonymous via the `VerificationPurpose` enum.

Branching that currently exists pre-auth:
- `LoginPage` → `Navigator.pushReplacementNamed('/registerPage')` via "Create a new account" text link (`login_ui.dart:128`).
- `RegisterPage` → `Navigator.pushNamed('/loginPage')` via "LOGIN" text link (`register.dart:218`).
- `RegisterAnonymousPage` → `logout(context)` then `/loginPage` via the same "LOGIN" link (`register_anonymous.dart:163`).

Other relevant facts:
- Phone validation is **SA-only** today via `lib/utils/phone_util.dart` (`isValidSAPhoneNumber`, `formatPhoneNumber`, `kSAOnlyPhoneMessage`). Local `0XXXXXXXXX`, `+27XXXXXXXXX` and `27XXXXXXXXX` all accepted; everything else rejected with the shared message.
- Pre-lookup network guard exists in `handleLogin` and `registerUser` (`auth_view_model.dart:53` and `:105`) using `connectivity_plus` to prevent the offline-cache-says-no-match → duplicate-account failure mode.
- Lookup uses `Source.server` and falls through `mobileNumberNormalized` → legacy `mobileNumber` (local) → legacy `mobileNumber` (E.164) to handle legacy writes (`auth_view_model.dart:490`).
- OTP dialog already uses `AutofillHints.oneTimeCode` (`auth_view_model.dart:398`) and shows a masked version of the number ("+27•••567") via `_maskPhoneNumber`.
- Telemetry already fires `SignupCompleted(method:'phone'|'anonymous')` and `SigninCompleted(method:'phone')` (`lib/services/analytics_event.dart:43`).
- A first-run **telemetry consent modal** (POPIA) is shown from `LoginPage.initState` *before* the user can interact with the form (`login.dart:37`). Any redesign must preserve this pre-auth gate.
- `BusinessNameGate` (`lib/pages/profile/business_name_gate.dart`) is a *post-auth* soft-gate that forces legacy merchants with a blank `shopName` to set one before the dashboard renders. This is the closest existing pattern to what we need for collecting deferred details.
- No i18n framework. `intl` is used only for currency/date formatting; all UI copy is inline English. SMS body templates are pulled from Remote Config (`SMSMessages.loadTemplates`).
- `UpdateNumberPage` (`lib/pages/settings/mobile_acc/update_number.dart`) is a **stub** — no OTP, no migration. Number changes are not currently supported anywhere.

Files reviewed (confidence: **high** on the auth surface, **medium** on downstream copy/i18n implications):
- `TASK_PACKET.md`, `OPNCODE_PROMPT.md`
- `lib/main.dart` (routes table + boot order)
- `lib/pages/auth/login/login.dart`
- `lib/pages/auth/widgets/login_ui.dart`
- `lib/pages/auth/widgets/logo_display.dart`
- `lib/pages/auth/register/register.dart`
- `lib/pages/auth/registerAnonymous/register_anonymous.dart`
- `lib/pages/auth/view_model/auth_view_model.dart`
- `lib/pages/profile/business_name_page.dart`, `business_name_gate.dart`
- `lib/pages/dashboard/dashboard.dart`
- `lib/shared/widgets/onboarding/merchant_onboarding_intro.dart`
- `test/merchant_onboarding_intro_test.dart`
- `lib/utils/phone_util.dart`, `lib/utils/auth_util.dart`, `lib/utils/feature_flags.dart`, `lib/utils/show_toast.dart`
- `lib/services/analytics_event.dart`
- `lib/shared/widgets/custom_text_field.dart`, `lib/widgets/private_region.dart`
- `lib/constants/constants.dart`, `lib/constants/layout_constants.dart`

---

## 2. Friction points (what we're fixing)

1. **Pre-flight Login vs Register choice.** The first decision the user is asked to make is "are you new or returning?" before they enter anything. New users frequently land on `/loginPage` from a referral / share / app store and either:
   - tap Login → get "This number is not registered. Please register first." (`auth_view_model.dart:70`) → manually navigate via the divider link to `/registerPage` → re-type their phone number.
   - or vice versa, registering an existing number → "This number is already registered. Please log in." (`auth_view_model.dart:124`) → navigate back, re-type.
   In both error paths **the phone number they just typed is thrown away** because the two screens have separate `TextEditingController`s (`mobileNoController` vs `registrationMobileNoController`).

2. **Register asks for 3 fields before the first value moment.** Full Name + Business Name + Phone are all required before the OTP even sends (`register.dart:80–137`). New users have no idea what the app is for at this point. Drop-off here is plausible.

3. **Wrong-CTA taps.** PAS-AUTH-02 (`login_ui.dart:99–124`) already softened the original "two green buttons stacked" layout, but the user still has to read enough text to pick the right path. A correct number-first flow eliminates the choice entirely.

4. **Returning user must remember they registered.** A returning user who reinstalls / new device has no local hint. They land on Login (correctly) but if their phone autofill misfires they may still tap Register and bounce off the duplicate guard.

5. **No resumable state.** If a user abandons mid-register (e.g. backgrounds during OTP wait, comes back 10 min later) the form is cleared, the OTP `verificationId` is gone, and they restart from zero. The current screens have no concept of "you started signing up — pick up where you left off".

6. **`shopName`/profile chrome competes with the phone field for attention.** PAS-UX-09 made Business Name required again at signup, but it sits *above* Mobile Number in the register form — the most action-critical field is the third one down.

7. **Anonymous "Explore" path exists but is hidden behind `FEATURE_ANONYMOUS_GATE_ENABLED=false`.** Cannot rely on it for the first slice. Decision below is to leave it off and not depend on it.

---

## 3. Proposed number-first flow

Single canonical entry. One screen, one input.

```
       ┌──────────────────────────────────────────┐
       │  PhoneEntryPage (/phoneEntryPage)        │
       │                                          │
       │  Logo                                    │
       │  "Enter your mobile number to start"     │
       │  [ 082 123 4567 ]   (SA validator)       │
       │  [ Continue ]                            │
       │                                          │
       │  (no Login/Register toggle, no copy      │
       │   about being new vs returning)          │
       └────────────────┬─────────────────────────┘
                        │ tap Continue, valid SA number
                        ▼
              ┌─────────────────────┐
              │ network + lookup    │  AuthViewModel.lookupAndRoute(phone)
              │ (Source.server)     │  reuses _isUserRegistered() +
              └────────┬────────────┘  _hasNetwork() guards
                       │
       ┌───────────────┼────────────────────┐
       │               │                    │
   isRegistered    !isRegistered        lookup failed
       │               │                    │
       ▼               ▼                    ▼
 ┌──────────────┐  ┌──────────────┐   ┌──────────────────┐
 │ OTP dialog   │  │ OTP dialog   │   │ inline error +   │
 │ (login       │  │ (registration│   │ Retry button.    │
 │  purpose)    │  │  purpose)    │   │ DO NOT proceed   │
 └──────┬───────┘  └──────┬───────┘   │ to OTP — risks   │
        │                 │           │ duplicate account│
        │                 │           └──────────────────┘
        ▼                 ▼
  signInWithCredential   signInWithCredential
  → identify             → identify
  → SigninCompleted      → write users/{uid} (phone only)
  → /dashboard           → SignupCompleted(method:'phone')
                         → /finishProfilePage
                                │
                                ▼
                      ┌────────────────────────┐
                      │ FinishProfilePage      │
                      │ (post-auth, gated)     │
                      │                        │
                      │ Business Name *        │
                      │ Full Name *            │
                      │ [ Continue ]           │
                      │                        │
                      │ Mirrors BusinessName-  │
                      │ Gate pattern: cannot   │
                      │ skip, no back gesture. │
                      └────────────┬───────────┘
                                   ▼
                           /dashboard (wrapped in
                           BusinessNameGate as today)
```

Why this works:

- **One field, one decision.** The number-first screen has nothing for the user to choose. They cannot pick the wrong path because there is no choice.
- **Branching happens server-side.** The same `_isUserRegistered` lookup we run today decides login vs registration *for* the user. The user never sees the words "register" or "login" before the OTP.
- **OTP step is unchanged.** Reusing `AuthViewModel._promptForVerificationCode` keeps the same masked-number copy, SMS autofill hint, cancel-and-retry copy, and `VerificationPurpose` plumbing. The signup analytics event still fires from the existing register branch.
- **Profile details defer to post-OTP.** Business Name and Full Name are still required (PAS-UX-09 reversal stands — they're load-bearing for SMS/WhatsApp templates and receipts) but they're collected *after* the user has invested an SMS round-trip. The `FinishProfilePage` reuses the `BusinessNameGate` "no back gesture, no skip" pattern from `business_name_gate.dart:208`, so we keep the auth-safety guarantee that no user reaches the dashboard with a blank shop name.
- **Returning users skip the profile page entirely.** Their `users/{uid}` doc already has `name` and `shopName`. They land on the dashboard after OTP, exactly like today.
- **Lookup failure is handled honestly.** If the Firestore lookup itself errors (offline-after-radio-check, permission, etc.) we surface a clear retry — we do NOT fall through to registration, because that's exactly the duplicate-account hazard the existing network guard was added to close.

---

## 4. First implementation slice

Goal: ship the smallest version of the above that is buildable, QA-able, and reversible.

### 4.1 In scope for slice 1

1. **New screen:** `PhoneEntryPage` at `/phoneEntryPage`.
   - Logo + headline + one `CustomTextField` (phone) + `CustomButton` (`Continue`).
   - SA validator via existing `isValidSAPhoneNumber`; error copy `kSAOnlyPhoneMessage`.
   - "Need help?" → existing `SupportUtil.sendWhatsAppMessage(context, WhatsAppMessageType.support)` (already used on `register.dart:193`).

2. **New view-model method:** `AuthViewModel.lookupAndRoute(BuildContext, String phone)`.
   - Re-uses `_hasNetwork()` and `_isUserRegistered()` unchanged.
   - On `true` → existing `handleLogin` path, but split so the OTP-initiation half can be called directly (extract `_initiateOtp(phone, purpose)`).
   - On `false` → existing `registerUser` path, but split so registration runs against the *single* phone field, and profile-data write is deferred.
   - On lookup throw → `showErrorSnackBar` with retry copy; do **not** advance.

3. **New screen:** `FinishProfilePage` at `/finishProfilePage`.
   - Required fields: Business Name, Full Name. Same validators as `register.dart:85` and `:108`.
   - Re-uses `BusinessNameGate`'s `PopScope(canPop: false)` pattern so the user cannot back-button out.
   - Writes to `users/{uid}` via the existing `_storeUserDetails` helper (extract the doc-write block so we can call it from the new page).
   - On success → `Navigator.pushReplacementNamed('/dashboard')`. Dashboard's existing `BusinessNameGate` becomes a defense-in-depth no-op for new signups (already passes because we just wrote the field).

4. **Routing change in `lib/main.dart`:**
   - `initialRoute: PhoneEntryPage.id` (was `LoginPage.id`).
   - Add `PhoneEntryPage.id` and `FinishProfilePage.id` to `_routes`.
   - **Keep** `/loginPage` and `/registerPage` registered (existing deep links, share links, and the post-logout `Navigator.pushReplacementNamed(context, '/loginPage')` in `auth_util.dart:71` must keep working). They redirect to `/phoneEntryPage` via a 1-line `WidgetsBinding.instance.addPostFrameCallback` in their `initState`. This keeps the slice reversible and avoids touching every navigation callsite.

5. **Feature flag:** `FeatureFlags.enableNumberFirstOnboarding` (Remote Config key `FEATURE_NUMBER_FIRST_ONBOARDING_ENABLED`, default `false`). When false, `initialRoute` stays `LoginPage.id` and the redirects in `/loginPage`/`/registerPage` are skipped. This is the rollback lever.

6. **Telemetry:** Re-use existing events. Specifically:
   - On new-user OTP success → `SignupCompleted(method: 'phone')` exactly as today.
   - On returning-user OTP success → `SigninCompleted(method: 'phone')` exactly as today.
   - Add two new typed events to `lib/services/analytics_event.dart`:
     - `PhoneLookupSucceeded({required bool isRegistered})` — fires once per Continue tap, used to size the new vs returning split.
     - `PhoneLookupFailed({required String reason})` — fires when the lookup errors so we can monitor the duplicate-account-prevention guard.

### 4.2 Explicitly out of slice 1

- Multi-country / non-SA phone input. SA-only stays via `kSAOnlyPhoneMessage`.
- Carrier-name display, country picker, formatted-as-you-type masking.
- Resumable signup state across app restarts (handles cases #5 above) — tracked as open question.
- Removing `/loginPage` and `/registerPage`. They stay as compat shims until the flag rollout is at 100 % for one full release.
- Anonymous "Explore" path. `FeatureFlags.enableAnonymousGate` stays as it is today (off).
- `UpdateNumberPage` work. Still a stub.
- i18n / translation. Copy lives inline as it does today.

---

## 5. Requirements

### Functional

- F1. User enters phone number on `/phoneEntryPage` and taps Continue. App determines new-vs-returning without further user input.
- F2. Returning users are routed straight to the OTP dialog with `VerificationPurpose.login`; on success they land on `/dashboard`.
- F3. New users are routed to the OTP dialog with `VerificationPurpose.registration`; on success they land on `/finishProfilePage`.
- F4. `/finishProfilePage` collects Business Name + Full Name, writes them to `users/{uid}`, then routes to `/dashboard`.
- F5. `/finishProfilePage` cannot be skipped (no back gesture, no Skip button, no system back).
- F6. The phone entered on `/phoneEntryPage` is preserved into the registration write (no second-typing of the number anywhere in the flow).
- F7. Lookup failure (network, permission, Firestore unavailable) surfaces a retry, never silently proceeds.
- F8. Feature flag `FEATURE_NUMBER_FIRST_ONBOARDING_ENABLED` (default `false`) gates the entire slice; when off, the app behaves exactly as today.
- F9. POPIA consent modal continues to fire pre-auth from the first screen (whichever screen the flag picks).

### Non-functional / safety

- N1. No path through `/phoneEntryPage` results in a user with two different `users/{uid}` docs for the same phone number.
- N2. No path proceeds past phone entry if the device is offline (existing `_hasNetwork()` guard stays).
- N3. `users/{uid}.shopName` is never written as an empty string at the end of a successful signup; either populated or the doc creation is rolled back.
- N4. Phone validation reuses `isValidSAPhoneNumber` — no second source of truth. SA-only constraint surfaces via `kSAOnlyPhoneMessage`.
- N5. OTP dialog and SMS path are unchanged; we do not touch `verifyPhoneNumber` configuration, the `AutofillHints.oneTimeCode` opt-in, or the masked-number copy.
- N6. Existing `Source.server` reads in `_isUserRegistered` are preserved verbatim — they are load-bearing for N1.
- N7. The existing post-auth `BusinessNameGate` stays in place as defense in depth.
- N8. Logout flow (`auth_util.dart:60`) still routes to a valid screen. If `/loginPage` is the post-logout destination, it must redirect to `/phoneEntryPage` when the flag is on (covered by the compat shim).

---

## 6. Acceptance criteria

1. With `FEATURE_NUMBER_FIRST_ONBOARDING_ENABLED=true` and a fresh install, the app launches into `/phoneEntryPage`. There is no Register button, no Login button, no "Already have an account?" link — only a phone field and Continue.
2. Entering a phone number that has a corresponding `users/{normalizedNumber}` doc, completing the OTP, results in the user landing on `/dashboard` with **zero** profile-data prompts on the way. The existing `BusinessNameGate` does not fire because the doc already has a `shopName`.
3. Entering a brand-new SA phone number, completing the OTP, lands on `/finishProfilePage`. The back gesture is suppressed (Android system back is a no-op; iOS swipe-back is blocked). Filling Business Name + Full Name + tapping Continue creates `users/{uid}` with `name`, `shopName`, `mobileNumber`, `mobileNumberNormalized`, and an initial wallet doc, then lands on `/dashboard`.
4. Entering an invalid number ("12345", "+44 …", empty) shows `kSAOnlyPhoneMessage` inline on the field. Continue does not advance.
5. With airplane mode on, tapping Continue shows the existing "You're offline" snack and does **not** advance.
6. Forcing the Firestore lookup to throw (simulate by revoking rules) shows a retry-style error and does **not** advance. The user is not pushed into a registration write.
7. Logging out from the dashboard returns the user to `/phoneEntryPage` (or `/loginPage` which redirects there). Re-entering the same number lands on the dashboard via the login branch.
8. With the flag off, the app behaves exactly as today: launches into `/loginPage`, with the existing two-CTA pattern.
9. A `PhoneLookupSucceeded` event is recorded in PostHog for every Continue tap that completes a lookup, with `isRegistered:true|false` matching the branch taken. `PhoneLookupFailed` is recorded for every lookup-error branch.
10. `SignupCompleted(method:'phone')` fires exactly once per new account at the OTP-success boundary (unchanged from today). `SigninCompleted(method:'phone')` fires exactly once per returning-user sign-in (unchanged).

---

## 7. Validation / error / loading states

| State | Trigger | UX |
|---|---|---|
| Empty / invalid phone | Continue tapped with empty or non-SA value | Inline `FormField` error using existing `kSAOnlyPhoneMessage`. No nav, no spinner. |
| Offline (radio off) | `_hasNetwork()` returns false | Existing orange snack: "You're offline. Please connect to the internet and try again." Continue button re-enabled. |
| Looking up | Continue tapped, valid number, network OK | Continue button shows spinner overlay using the same `ValueListenableBuilder<bool>` + `Stack` pattern as `register.dart:139`. Field is disabled. |
| Sending OTP | After lookup, before `codeSent` callback | Same spinner state, copy unchanged. |
| OTP dialog | `codeSent` callback fires | Existing `_promptForVerificationCode` dialog. Re-used as-is, including masked number copy and `AutofillHints.oneTimeCode`. |
| OTP code wrong | `signInWithCredential` throws | Existing "Failed to sign in: $e" snack. User can re-try the dialog. |
| OTP cancelled | User taps Cancel on dialog | Dialog dismisses; user returns to `/phoneEntryPage` with the number still in the field. |
| Lookup throws | `_isUserRegistered` re-throws (offline mid-read, permission, etc.) | New: red snack "Could not check your number. Please try again." No nav. Continue button re-enabled. Lookup failure is logged via existing `CrashService.recordNonFatal` + new `PhoneLookupFailed` event. |
| Successful login (returning) | `signInWithCredential` resolves | Existing `handleSuccessfulLogin` → `/dashboard`. |
| Successful registration (new) | `signInWithCredential` resolves AND `users/{uid}` doc does not exist | Navigate to `/finishProfilePage` (NOT `/dashboard` yet). |
| Finish-profile validation | Submit tapped with empty Business Name or Full Name | Inline form errors via the existing validators copied from `register.dart`. |
| Finish-profile save | Submit tapped, valid | Spinner state on Continue; on success → `/dashboard`. On Firestore write failure → red snack "Could not save your details. Try again." Form stays. |
| User abandons after OTP, before profile | Backgrounds the app between OTP success and `FinishProfilePage` submit | On resume, `FirebaseAuth.currentUser` is non-null but `users/{uid}` is empty. The app's existing post-auth flow already routes to `/dashboard`, which then hits `BusinessNameGate` — which forces a re-entry of Business Name. This is the defense-in-depth safety net (existing behaviour) and ensures we never strand a user. **Open question:** do we also want to route abandon-resume directly to `/finishProfilePage` instead of via the gate? See §10. |

---

## 8. QA checklist (for the build, not for this spec)

Smoke / happy path
- [ ] New SA number → OTP → finish profile → dashboard.
- [ ] Existing SA number → OTP → dashboard (no profile page).
- [ ] Returning user on a fresh install with autofill → same as above.

Validation
- [ ] Empty phone shows inline error.
- [ ] `12345` shows `kSAOnlyPhoneMessage`.
- [ ] `+44 7700 900000` shows `kSAOnlyPhoneMessage`.
- [ ] `082 123 4567` (with spaces) is accepted.
- [ ] `+27821234567` and `0821234567` both route the same user to the same branch.
- [ ] `0521234567` (invalid prefix per ICASA) is rejected.

Network / failure
- [ ] Airplane mode on → tap Continue → existing offline snack, no nav.
- [ ] Toggle airplane mode off mid-flow → retry Continue → succeeds.
- [ ] Force Firestore lookup to throw (revoke rules locally) → red retry snack, no nav, no registration write.
- [ ] OTP send failure (`verifyPhoneNumber.verificationFailed`) → existing "Verification failed: ..." snack, no nav.
- [ ] Wrong OTP code → existing snack, dialog stays open for retry.

Abandon / resume
- [ ] Background the app on `/phoneEntryPage` → resume → field state preserved (Flutter default `TextEditingController` survives background).
- [ ] Background the app during OTP wait → resume → dialog still present, code field focused.
- [ ] Background after OTP success but before submitting Finish Profile → resume → user lands on dashboard via `BusinessNameGate`, which forces Business Name entry. Full Name is **lost** in this case (open question §10).
- [ ] Force-kill the app between OTP success and Finish Profile → reopen → same as above (Firebase Auth session is persisted, `users/{uid}` is empty, gate fires).

Duplicate-account safety
- [ ] Register a number, log out, repeat the flow with the same number → second pass lands on dashboard (login branch), does NOT create a second `users/{uid}` doc.
- [ ] Repeat with airplane mode on → second pass blocked by offline snack before any write.
- [ ] Repeat with Firestore lookup forced to throw → second pass blocked by retry snack before any write.

Mobile layout / keyboard
- [ ] Field is visible above the keyboard on a small iPhone SE form-factor (`SafeArea` + `SingleChildScrollView` already in the template).
- [ ] `TextInputType.phone` shows the numeric keypad with `+` on iOS.
- [ ] `autofillHints: [AutofillHints.telephoneNumber]` (NEW — to be added) surfaces the OS phone-number autofill chip.
- [ ] OTP dialog autofocuses the code field; OS one-time-code suggestion appears above the keyboard on iOS.
- [ ] Both `/phoneEntryPage` and `/finishProfilePage` render correctly with the Android navigation bar shown and with gesture navigation.
- [ ] Pull-to-dismiss is blocked on `/finishProfilePage`.

Feature flag
- [ ] `FEATURE_NUMBER_FIRST_ONBOARDING_ENABLED=false` → app launches into legacy `/loginPage`, two-CTA layout.
- [ ] Flip the flag on via Remote Config → relaunch → app launches into `/phoneEntryPage`.
- [ ] Deep link to `/loginPage` while flag is on → redirects to `/phoneEntryPage`.
- [ ] Logout while flag is on → lands on `/phoneEntryPage` (not `/loginPage`).

Analytics
- [ ] `phone_lookup_succeeded` event fires with `is_registered:true|false` on every successful Continue.
- [ ] `phone_lookup_failed` event fires with `reason` on every error branch.
- [ ] `signup_completed` event fires exactly once per new user, with `method:'phone'`.
- [ ] `signin_completed` event fires exactly once per returning sign-in, with `method:'phone'`.
- [ ] No PII (raw phone number, name) is attached to any of the four events above (per `analytics_event.dart` rules).

Safari / web — **N/A**. Pasella is Flutter mobile only; no web auth surface is touched by this slice.

---

## 9. Code touchpoints (for the build, not for this spec)

New files:
- `lib/pages/auth/phone_entry/phone_entry_page.dart` — `PhoneEntryPage` (`id = '/phoneEntryPage'`).
- `lib/pages/auth/finish_profile/finish_profile_page.dart` — `FinishProfilePage` (`id = '/finishProfilePage'`). Modelled on `business_name_page.dart` (uses `PopScope(canPop: false)` when in gate mode).

Edited files:
- `lib/pages/auth/view_model/auth_view_model.dart`
  - Add `lookupAndRoute(BuildContext, String phone)` that performs `_hasNetwork()` + `_isUserRegistered()` + routes to OTP with the correct `VerificationPurpose`.
  - Extract `_initiateOtp(phone, purpose, {referrerUserId})` from the duplicate code in `handleLogin` and `registerUser` so both paths share one entry point.
  - Extract `_writeUserProfile(uid, {name, shopName, referrerUserId})` from `_storeUserDetails` so `FinishProfilePage` can call it with the same write semantics.
  - In the new-user OTP success branch, write only `{mobileNumber, mobileNumberNormalized, referralCount:0, referrerUserId}` then route to `/finishProfilePage` (defer `name` and `shopName` until that page submits).
  - **Do NOT touch:** `_hasNetwork`, `_isUserRegistered`, `_promptForVerificationCode`, `initiatePhoneNumberVerification`, telemetry calls, wallet creation.
- `lib/main.dart`
  - Add `PhoneEntryPage.id` and `FinishProfilePage.id` to `MyApp._routes`.
  - Make `initialRoute` conditional on `FeatureFlags.enableNumberFirstOnboarding`.
- `lib/app_imports.dart`
  - Export the two new pages.
- `lib/utils/feature_flags.dart`
  - Add `static bool enableNumberFirstOnboarding = false;` and the `RemoteConfig` lookup for `FEATURE_NUMBER_FIRST_ONBOARDING_ENABLED`.
- `lib/services/analytics_event.dart`
  - Add `PhoneLookupSucceeded` and `PhoneLookupFailed` event classes.
- `lib/pages/auth/login/login.dart` and `lib/pages/auth/register/register.dart`
  - Add a 1-line post-frame redirect to `/phoneEntryPage` when `enableNumberFirstOnboarding` is true. The full pages stay registered as compat shims for the rollout window.

Unchanged but worth flagging:
- `lib/utils/phone_util.dart` — reused verbatim.
- `lib/utils/auth_util.dart` — `logout()` still routes to `/loginPage`. The compat shim above handles redirection while the flag rolls out; once we drop `/loginPage` we'll edit this in a follow-up.
- `lib/pages/profile/business_name_gate.dart` — stays as defense in depth.
- `lib/pages/dashboard/dashboard.dart` — unchanged.
- `lib/widgets/consent_modal.dart` + the `LoginPage.initState` POPIA consent trigger — **must be ported** to `PhoneEntryPage.initState` so the consent prompt still fires pre-auth.

---

## 10. Risks and open questions

Risks
- **R1. Lookup race:** Two devices with the same number tapping Continue simultaneously could both hit the "not registered" branch before either write completes. Mitigation: existing `Source.server` reads + Firebase phone-auth itself is keyed on the phone number, so the second `signInWithCredential` returns the same Firebase UID and our `set(..., merge: true)` in `_storeUserDetails` (`auth_view_model.dart:737`) deduplicates the doc. Acceptable for slice 1.
- **R2. Compat shim drift:** Keeping `/loginPage` and `/registerPage` as redirects means two flows exist in code. If a future PR edits `/loginPage` without realising it's deprecated, behaviour diverges. Mitigation: add a deprecation comment + remove the shims in the follow-up release after rollout hits 100 %.
- **R3. POPIA consent gate moved:** Porting `ConsentModal.showIfNeeded` from `LoginPage.initState` to `PhoneEntryPage.initState` must happen in the same PR. If we miss it, anonymous-auth and screen-view events could fire to PostHog before the merchant consents. Verification: search for `ConsentModal.showIfNeeded` callsites in the PR diff.
- **R4. Existing test:** `test/merchant_onboarding_intro_test.dart` is unrelated and stays green. No existing auth tests to break — but this means we're also not adding regression coverage for the legacy flow. Recommend adding a widget test for `PhoneEntryPage` in slice 1.

Open questions
- **Q1. Abandon-resume after OTP, before profile completion.** If a user OTPs successfully then backgrounds the app before submitting `FinishProfilePage`, on resume they're an authenticated Firebase user with an empty `users/{uid}` doc. Today's `BusinessNameGate` will catch the missing `shopName` and force re-entry — but Full Name is lost. **Recommendation:** route resume-with-no-`users`-doc directly to `/finishProfilePage` (extend `BusinessNameGate` to a `ProfileCompletenessGate`), but defer to slice 2 to keep slice 1 minimal. Confirm with PM.
- **Q2. What about the "Explore" anonymous path?** Currently flagged off (`FeatureFlags.enableAnonymousGate = false`). If product wants to keep an "explore without registering" affordance, where does it sit in the number-first flow? Options: (a) skip — don't reintroduce, (b) text link below the phone field "Just looking around? Continue as guest", (c) full secondary CTA. **Recommendation:** option (a) for slice 1, since the flag is already off in prod.
- **Q3. Referral / deep-link `referrerUserId`.** The existing `deepLinkBox` plumbing (`register.dart:33`, `register_anonymous.dart:33`) reads `referrerUserId` from Hive at the register page mount. We need to read it at `PhoneEntryPage.initState` and pass it through `lookupAndRoute` → registration write. **No design issue, just a wiring reminder for the build.**
- **Q4. Carrier display / future intl support.** SA-only is a real product constraint today (`kSAOnlyPhoneMessage` calls it out). Whether the first slice also displays a `+27` country chip vs leaving the field free-form is a copy / visual decision rather than a flow decision. **Recommendation:** keep the field free-form (same as today's login/register inputs) — adding a country picker is a Slice 2+ change.
- **Q5. i18n.** No localization framework today. All copy in this spec is English-only and inline. If product plans translations for SA's official languages (zu, xh, af, st, ...), the number-first screens are a good place to start, but that's a separate epic — **not** in slice 1. Copy notes below are written so they're easy to extract into ARB files later.

---

## 11. i18n / copy notes

There is no `flutter_localizations` / `AppLocalizations` setup in this repo today. Copy lives inline. To keep slice 1 honest and easy to translate later:

- All new strings live in **one place per screen** (top of file as `static const`), not scattered inside `Text(...)` widgets. Easier to lift into an ARB file later.
- Re-use `kSAOnlyPhoneMessage` from `phone_util.dart` rather than re-typing the SA-only constraint.
- New copy required (English, write once, mirror tone of existing PAS-AUTH-01 copy in `login_ui.dart:30`):

| Key (suggested) | English copy |
|---|---|
| `phoneEntryHeadline` | "Enter your mobile number to start" |
| `phoneEntrySub` | "We'll text you a 6-digit code. No password needed." |
| `phoneEntryCta` | "Continue" |
| `phoneEntryLookupErr` | "Couldn't check your number. Tap Continue to try again." |
| `finishProfileHeadline` | "Tell us about your business" |
| `finishProfileSub` | "Customers see your business name on every receipt, SMS and WhatsApp we send for you." |
| `finishProfileCta` | "Continue" |
| `finishProfileSaveErr` | "Couldn't save your details. Please try again." |

Existing copy (reused verbatim, no new translation surface):
- `kSAOnlyPhoneMessage` (`phone_util.dart:30`)
- "You're offline. Please connect to the internet and try again." (`auth_view_model.dart:56`)
- "We just sent an SMS to ${maskedNumber}. Enter the code to continue." (`auth_view_model.dart:368`)
- "Code didn't arrive? Wait 30 seconds, then tap Cancel and try again." (`auth_view_model.dart:392`)
- "Verify" / "Cancel" buttons (`auth_view_model.dart:408`, `:419`)
- Business Name validator copy from `register.dart:108–117`.
- Full Name validator copy from `register.dart:85–90`.

---

## 12. Verification notes for this spec

- **Files inspected:** 22 source files + `TASK_PACKET.md`, `OPNCODE_PROMPT.md`, `pubspec.yaml`. Full list in §1.
- **Code changes made by this packet:** none.
- **Confidence:** High on the auth code path (login/register/anon-register all read end-to-end, view-model read end-to-end, network and lookup safety verified). Medium on i18n implications (verified no `AppLocalizations` framework is present; have not audited every downstream string that references the merchant's name or shop name across SMS/WhatsApp templates — those are merchant-facing copy, not pre-auth onboarding, so out of scope for this spec). Medium on rollout/analytics impact (PostHog event taxonomy reviewed but PostHog dashboard sanity-check is operational, not a spec concern).
- **Assumptions called out for confirmation:** Q1, Q2, Q3, Q5 in §10.
