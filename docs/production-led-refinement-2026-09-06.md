# Production-led refinement — 6 September 2026

## Implemented

The user prefers production’s identity and Customers list, with the new spacing,
Products and Sales improvements, grouped Settings and Wallet/banking controls.

- Restored production green #1C863B, navy #2B325F, gold #EBCB58 and muted text
  #686A77. Kept the shared spacing, fonts, neutral surfaces and form layouts.
  Primary navigation has a navy indicator with a gold selected icon.
- Customer cards are compact flat rows again: avatar, identity/channel, unread
  count and right-aligned balance. Large text stacks the balance without
  shrinking it. Existing navigation and replay privacy masking remain.
- Product amounts and arrows share a consistent trailing row. Measured price
  width and larger text move the price below the name before they crowd it.
- WhatsApp catalogue status is a compact entry with detailed counts, refresh and
  guidance in a scrollable, bottom-safe sheet. Listing and sync states remain
  truthful; provider/navigation lifecycle fixes are preserved.
- Sales details, date choices, online-order filters and invoice choices account
  for Android navigation and keyboard insets. The final rows can scroll fully
  into view; long date ranges scroll while the Close control stays available.
- Message-price failures preserve safe error categories, payment-fee information
  loads independently, and retry targets the failed section. See the
  [pricing diagnosis](dev-pricing-2026-09-06.md) for the live environment evidence.
- Retained OTP/catalogue Crashlytics fixes, PDF invoice handling, onboarding
  improvements, removal of the rebrand popup and editable saved bank accounts.

## Verified

- Full development-configured Flutter suite: **710 tests passed**.
- Analysis of 229 changed/new Dart files: **0 errors, 0 warnings**, 96 retained
  informational lints. Final pricing checks: 14 passing tests and no lints.
- New regression coverage includes compact/right-aligned customer rows, very
  large product prices, catalogue disclosure, eight drawer inset cases and
  independent pricing loads/retry. Existing crash and banking regressions pass.
- Release web preview rebuilt. Browser review confirmed Customers, Products,
  catalogue details and Sales details, including the visible final entry count.
- Development Android APK built successfully; manifest identifies only the dev
  package and both Flutter/native Firebase configuration target spazaone-dev.
- APK signed with the same existing certificate as the previous phone install;
  application/asset entries are byte-identical before and after signing.
- Client sources match the recorded overlay manifest. Backend, rules and native
  config stay on authority revision 7078080079bf63410484b3440917de2036b52dcb.
  No production release or cloud configuration changes were performed.

## Phone build and remaining verification

Version: **4.8.4-dev.2 (101)**; package: `com.tsepo.spazaone.dev`.
APK: `/Users/admin/.codex/worktrees/2f79/pasella-app-dev-install/build/app/outputs/flutter-apk/spazaone-development-4.8.4-dev.2-101.apk`
SHA-256: `75f3cb80f0c3571791a92c37ea5ca844453e30bc78c392e3a6e00eb9d12b730a`

The phone’s USB connection became intermittent during preparation. Installation
and launch are only complete when recorded below. Existing dev data is preserved
with an in-place update; there is no uninstall or app-data clear.

The pricing function rejected invalid App Check tokens just after the earlier
phone install. Its endpoint and required pricing configuration are present. A
successful request from the installed phone remains necessary. Any new debug-app
authorization in Firebase requires action-time approval under the machine-wide
AGENTS.md; no token has been inspected or registered during this refinement.

Logs: `/tmp/spaza-refinement-full-tests.log`,
`/tmp/spaza-refinement-analysis.log`, `/tmp/spaza-refinement-apk-build.log`,
`/tmp/spaza-refinement-preview-build.log`.
Source manifest: `/tmp/spaza-refinement-source-manifest.json`.
APK receipt: `/tmp/spaza-refinement-apk-receipt.json`.
