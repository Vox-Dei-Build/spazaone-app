# Pasella app-wide UI/UX audit

## Audit baseline

- Release: `v4.1.0+64`
- Baseline commit: `8b5acb0` (`origin/main`)
- Remediation branch: `codex/ui-ux-audit-remediation`
- Surfaces reviewed: authentication, Customers, Products, Sales, Marketing,
  reports, orders, Billing, Settings, onboarding, privacy, loading/error/empty
  states, rotation, large text, offline behavior, and Flutter web startup.

The audit combined rendered phone-sized checks, portrait/landscape review,
200% text-scale tests, interaction and state-flow inspection, and source review
of the shared design and navigation foundations.

## Findings and resolutions

| ID | Severity | Finding | Resolution |
| --- | --- | --- | --- |
| UX-01 | High | The header could report **Online** when the device had a network interface but could not reach the backend. Queued messages could be flushed on that false-positive signal. | Added a timed backend reachability probe, explicit checking/offline/synced states, and queue flushing only after backend access is confirmed. |
| UX-02 | High | App launch waited on Firebase, Remote Config (up to its network timeout), Hive, flags, and telemetry before rendering a useful frame. Startup failure had no recovery action. | Added an immediate branded bootstrap surface, kept initial-route flags ordered correctly, deferred non-critical services, and added a friendly retry state. Notification permission is no longer requested at launch. |
| UX-03 | High | Flutter web initialized Firebase without the generated platform options. | Initialized with `DefaultFirebaseOptions.currentPlatform`; verified with a web build and rendered local web smoke test. |
| UX-04 | High | Typography and icons scaled from device height/width in ways that collapsed type or inflated imagery after rotation. | Typography now uses a bounded width token; image/spacing sizing uses a bounded shortest-edge token. Portrait and landscape are regression-tested and rendered. |
| UX-05 | High | Help and Privacy could overflow or hide controls at 200% text scale and on short screens. Settings subtitles could truncate important context. | Made the affected surfaces scrollable, removed rigid spacer layouts, allowed two-line settings descriptions, and added small-screen 200% text tests. |
| UX-06 | High | Several controls used gesture-only interaction, suppressed native feedback, lacked button semantics/tooltips, or had targets below 48px. Contrast for secondary copy and unselected navigation was weak. | Restored native Material feedback, button semantics and state-aware navigation colors; improved secondary contrast; added labels/tooltips; enlarged app bars, filter chips, consent actions, coachmark dismiss, image edit, and promotion actions to at least 48px. |
| UX-07 | High | Ledger filters shallow-copied nested values, so Cancel could still mutate applied state. Reminder filters could conflict; Today compared insufficient date components. | Deep-copied temporary/applied state, made reminder choices mutually exclusive, compared full calendar dates, and added cancel/deep-copy tests. |
| UX-08 | Medium | Sales/report date **Clear** did not actually clear the active period, and compact date controls were hard to target. | Added explicit clear callbacks and true all-time state, with 48px controls, semantics, and a clear-action regression test. |
| UX-09 | High | Monetary fields often used integer-only keyboards, while money display mixed decimal separators and hand-built `R` strings. | Enabled decimal keyboards for all monetary entry flows and routed visible Rand amounts through `CurrencyUtil.format`. Quantity, phone, OTP, and account-number fields remain numeric. |
| UX-10 | High | Product group selection was not reliably persisted and custom groups could be erased while the async group list loaded. Images uploaded before Save, leaving abandoned uploads. Save was icon-only and edit/create could discard changes without warning. | Preserved custom/selected groups, delayed image upload until Save, previewed the local pending image, added labeled Save actions/loading states, and added create/edit discard guards. Cost and selling price are stacked for narrow/large-text layouts. |
| UX-11 | High | Template and promotion creation could pop on failure, provide little/no error feedback, or silently discard in-progress work. The success screen promised notifications even when permission was not enabled. | Keep failed sends/submissions on-screen with actionable feedback, added discard guards, made success content scrollable, and made notification copy conditional. A contextual Notifications action now lives in Settings. |
| UX-12 | Medium | Billing/Wallet leaked its view model and balance cards could break on small screens or large text. Wallet terminology was unclear in shared headers. | Dispose the wallet view model, constrain/scroll balance cards, standardize currency rendering, and expose the shared balance pill as **Billing, app balance** to assistive technology. |
| UX-13 | High | Multiple list/report surfaces exposed raw backend errors or dead-end failure cards. | Replaced raw exceptions with plain-language states; added retry actions to business/customer reporting and retained refresh/re-entry paths on list surfaces. Internal details remain in diagnostics only. |
| UX-14 | Medium | Empty Customers, Products, and Sales surfaces could show both an inline primary action and a competing FAB. Content could sit under FABs. | Use the inline first-action CTA when empty, reveal the FAB once data exists, and reserve bottom spacing for content near floating controls. |
| UX-15 | Medium | Merchant setup repeated the current **Up next** task in the checklist, creating duplicate labels/chevrons and competing actions. | Promote the current action once and omit its duplicate checklist row; updated the onboarding regression suite. |
| UX-16 | Medium | Product and sales summary layouts used rigid horizontal sizing that clipped content on smaller/large-text displays. | Replaced the rigid sales metric scroller with wrapping content and converted product price fields to a vertical responsive flow. |
| UX-17 | Medium | Merchant-facing terminology mixed **BNPL**, **Pay Later**, contacts/customers, sales entries, Products(s), and wallet/billing language. | Standardized customer-facing order/payment language on **Pay Later**, primary ledger language on **Customer**, stock/report copy on natural product wording, sales wording on Sales, and app-funds navigation on Billing. Backend enum/action keys remain unchanged. |
| UX-18 | Medium | Unfinished legacy Settings routes remained navigable despite having placeholder or incomplete experiences. | Removed Security, legacy Profile/Account/Language, Update Number, Backup, and Find Defaulter from the registered route table while retaining active supported settings. Unknown/stale routes use the existing safe fallback. |
| UX-19 | Medium | Privacy refusal and coachmark dismissal had smaller targets than the surrounding primary choices. | Raised Reject all, Accept all, and coachmark dismiss targets to 48px without changing consent defaults or persistence. |
| UX-20 | Medium | Automated coverage did not protect rotation sizing, large text, button semantics/targets, filter cancellation/deep copies, real date clearing, or onboarding de-duplication. | Added `ui_ux_regression_test.dart` and strengthened merchant setup expectations. The complete suite now contains 109 passing tests. |

## Verification

- `flutter analyze --no-pub --no-fatal-infos` — passes with no errors or
  warnings (339 existing informational lints remain).
- `flutter test` — 109 tests pass.
- `flutter build web --debug` — succeeds.
- `flutter build apk --debug` — succeeds.
- Rendered local web smoke checks at 390×844 and 844×390 — entry and consent
  surfaces render, retain readable sizing, and remain scrollable/reachable.
- `git diff --check` — passes.

## Non-blocking technical debt observed

These did not block or invalidate the UI/UX remediation:

- The analyzer reports 339 informational lints, primarily existing
  deprecations, naming rules, `print` calls, and async-context guidance.
- Flutter reports deprecated loader patterns in `web/index.html`.
- Android dependencies emit Java 8 source/target deprecation warnings.

They should be handled in focused platform/maintenance changes to keep this
UI/UX review scoped and reviewable.
