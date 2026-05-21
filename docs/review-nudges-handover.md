# Review Nudges — Handover Note

**Branch:** `growth/pas-review-nudges`
**Ticket:** PAS-GROWTH (in-app review nudges)

## What was built

A small, throttled in-app review nudge anchored to the strongest "the app
just worked" moments in Pasella's core ledger flow. No modals, no custom
UI — we delegate to the OS's native review sheet (Apple
`SKStoreReviewController` / Google Play In-App Review API) which is itself
quota-throttled at the platform level.

## Files touched

| File | Change |
|---|---|
| `pubspec.yaml` | Add `in_app_review: ^2.0.9` (resolves to 2.0.10, last release compatible with Dart 3.0+/Flutter 3.29). |
| `lib/services/review_prompt_service.dart` | **New.** Singleton service: state persistence, eligibility, native call, telemetry. |
| `lib/services/analytics_event.dart` | New `ReviewNudgeShown` event in the typed taxonomy. |
| `lib/main.dart` | `await ReviewPromptService.instance.init();` after telemetry boot, after `Hive.openBox('appBox')`. |
| `lib/pages/sales/view_model/sale_view_model.dart` | Fire-and-forget `maybePrompt(saleCompletedCash)` after the existing `SaleCompleted` capture. |
| `lib/pages/transactions/view_model/add_credit_view_model.dart` | Fire-and-forget `maybePrompt(saleCompletedCredit)` after the existing `SaleCompleted` capture. |

## Trigger moments

Both triggers sit immediately after the existing typed `SaleCompleted`
analytics capture, **before** the success snackbar / navigator pop, so
the prompt (when shown) appears on the merchant's own home/ledger screen,
not while a modal is still tearing down.

1. **Cash sale completed** — `lib/pages/sales/view_model/sale_view_model.dart:296-303`
2. **Credit / BNPL sale completed** — `lib/pages/transactions/view_model/add_credit_view_model.dart:316-323`

These are the top 2 of the 5 candidate hooks the audit surfaced. We
deliberately rejected the others for now:

- *Customer created* — fires too easily during contact-import binges; not a
  "value moment" so much as data entry.
- *First reminder delivered* (`CommsSent`) — fires from a background
  delivery callback, often when the merchant isn't even on-screen, so the
  OS prompt would land on whatever they happen to be looking at.
- *Onboarding checklist 3/4* — viable later, but the checklist UI itself
  is the celebratory moment; layering an OS prompt on top would feel busy.

The hook can be re-pointed by adding a new `ReviewTrigger` enum value and
calling `maybePrompt(...)` from the new site — no other change required.

## Eligibility / throttling

All gates live in `ReviewPromptService._evaluateEligibility` and are
constants at the top of the file (clearly labelled "tunable"):

| Gate | Default | Rationale |
|---|---|---|
| `_minTriggerCount` | **3 sales** | First and second sale are often test data. By the third the merchant has clearly adopted the flow. |
| `_firstPromptCooldown` | **2 days** since first install | A merchant blasting through 3 test sales in their first 5 minutes still won't see the prompt on day zero. |
| `_repeatCooldown` | **90 days** since last prompt | Apple permits ~3 prompts/365d, Google ~1/quarter — our local floor (90d) keeps us strictly inside both vendor quotas even after an app reinstall on the same device. |
| `optedOut` flag | sticky | Wired but no UI yet; lets a future Settings toggle ("Don't ask again") permanently mute. |
| OS `isAvailable()` | required | Last check, async — Play Services may be missing on Huawei devices, etc. |

State is persisted as a single JSON blob in the existing `appBox` Hive
box under key `review_prompt_state_v1` (mirrors `ConsentService` and
`merchantHeartbeat` patterns). No `shared_preferences` was added.

## Why this avoids spam

1. **No custom modal, ever.** The native sheet is the only UI we surface.
   The platform itself silently no-ops if its quota is exhausted.
2. **Two value-anchored triggers, not "every screen view".** Both hook
   sites are in completed-write code paths — the merchant has just
   succeeded at the core action.
3. **Layered cooldowns.** Three independent gates (activity count,
   install age, prompt cooldown) all have to pass.
4. **Fire-and-forget at the call site.** `maybePrompt` is never awaited
   in a critical user path; if the SDK or Hive throws, the merchant's
   navigation continues unaffected (errors funnel into Crashlytics via
   the codebase's existing `CrashService.recordNonFatal` pattern).
5. **Telemetry consent-respecting.** The `ReviewNudgeShown` event goes
   through `TelemetryService` which is gated by `ConsentService`; if the
   merchant declined analytics, the nudge still fires but no event is
   sent.

## Verification

- `flutter pub get` ✅ — resolves on the project's pinned Dart 3.0/Flutter 3.29 toolchain.
- `flutter analyze` on touched files: **0 new issues** (21 pre-existing infos in untouched code, all `avoid_print` / `BuildContext`-across-async — unrelated).
- `flutter test` ✅ — full suite (31 tests) green.

## Tuning hooks

All tunables are top-of-file constants in
`lib/services/review_prompt_service.dart`. The cleanest follow-up would
be to back `_minTriggerCount`, `_firstPromptCooldown` and `_repeatCooldown`
with `RemoteConfigService` (already in the project at
`lib/config/remote_config.dart`) so growth can adjust without a release.

A "Don't ask again" Settings toggle can call
`ReviewPromptService.instance.optOut()` — the field already exists in the
persisted state and is honoured by the eligibility gate.

## Future trigger candidates (when we want more volume)

- `add_contact_view_model.dart:307` after `CustomerCreated` — gate to
  `isFirstCustomer == true` only.
- `messaging_notification_service.dart:525` (`sendReminderMessage`) —
  delivery-confirmed reminder. UX caveat: fires off-screen.
- `onboarding_checklist.dart` flipping to ≥3/4 done — strong "engaged
  merchant" signal.
