# Spaza One app design system

The current direction combines **production’s familiar identity** with the
approachable spacing and simpler flows. Customer lists keep production’s compact,
flat rows. Products, recorded sales, grouped Settings and banking edits retain the
reviewed improvements. These foundations are shared by the app and local preview.

## Foundations

- **Typography:** bundled Roboto under the application font family `SpazaSans`,
  using regular, medium and bold. Font assets and their Apache license live in
  `assets/fonts/`. The same files work offline on every platform.
- **Type scale:** 16px body, 13px secondary, 14px actions, 18px sections,
  22px app-bar titles and 27px medium-weight authentication headlines. These are
  Flutter logical pixels; operating-system text scaling remains enabled.
- **Spacing:** 4, 8, 12, 16, 24 and 32px. Workspace gutters, forms and settings
  use 16px. Authentication uses 22px side gutters, reduced to 16px on narrow
  screens. The shared theme gives filled and outlined controls a 52px minimum
  height; icon/text actions keep 48px targets. Settings rows have a 56px minimum
  and grow with their text.
- **Color:** production green `#1C863B`, navy `#2B325F`, gold `#EBCB58` and
  secondary text `#686A77`. Navy headings and navigation restore the familiar
  identity; selected bottom-navigation icons use gold on navy. Pages use
  `#FAFAFA`, white surfaces, neutral inset areas `#F3F4F6` and borders `#E4E5EA`.
  Green marks primary actions and positive states. Customer balances retain
  production’s orange amount for money owed and green for paid-up accounts.
- **Shape:** 8px small elements, 16px controls, 20px panels and 24px sheets/dialogs.
  Product entries are individual rounded cards; Settings destinations sit inside
  shared Shop, Preferences and Account panels. Customers use compact rows with
  separators, avatars and right-aligned balances, without individual card chrome. The authentication form uses a
  22px panel beneath a small store emblem.
- **Icons:** a shared mapping of outlined Material icons for recurring jobs.
  Customers, products, sales, shop, wallet, settings and common actions keep the
  same visual metaphor across screens. Official brand marks remain intact.

Sources: [theme](../lib/design/spaza_theme.dart),
[tokens](../lib/design/spaza_tokens.dart),
[compatibility constants](../lib/constants/constants.dart).

Legacy `SizeConfig.textMultiplier` now stays at 8 so text no longer grows merely
because the device is taller or rotated. Existing layout dimensions continue
to adapt; new typography should come from `Theme.of(context).textTheme`.

## Shared interaction rules

- Keep one primary action obvious; move secondary figures into accessible
  details. Do not discard information just to reduce density.
- Use the same rounded section group with a white selected tab. Primary
  navigation uses the production navy indicator and gold icon. Unread badges expose their full count to screen readers.
- Keep labels visible, wrap essential text, and stack controls when text grows.
  Short screens and keyboards must leave all form actions reachable by scrolling.
- Validation brings the first invalid form field into view. Busy states disable
  submission. Back navigation respects unsaved changes.
- Authentication keeps the existing number-first and legacy feature gates,
  OTP verification, retry/cancel behavior, profile requirements and consent flow.
- Read failures need an explicit retry state. An unloaded configuration must not
  be editable as if its defaults came from the server.

## Local review

`tool/app_design_preview.dart` assembles the production presentation widgets with
synthetic data. Its selector provides Login, Activity, Products, Sales, Settings,
Record sale, Wallet and Marketing. **All screens** opens a searchable gallery of
40 layouts, including 32 additional customer, product, order, wallet, campaign and
setup screens that reuse production presentation. See the
[screen coverage](app-screen-coverage.md). Login accepts a valid-format example South African
mobile number and the demo code 123456. No SMS, account creation, billing, campaign
send or server write occurs. Preview form submissions are demonstrations and do
not persist entries.

Build with the project's pinned Flutter 3.29.2:

```sh
flutter build web --no-pub --release -t tool/app_design_preview.dart --output build/design-preview
python3 -m http.server 8765 --bind 127.0.0.1 --directory build/design-preview
```

The preview uses an empty, ignored `.env` asset. It does not carry an operational
Firebase configuration. The existing configuration-isolation test cannot verify
that absent configuration. Native authenticated-device checks are still needed
before release; local synthetic UI verification does not substitute for them.

See the [app audit](app-design-audit-2026-09-05.md) for completed areas and
specific remaining opportunities.

## Combined crash-fix verification — 6 September 2026

The approved design is combined with the catalogue provider and OTP lifecycle
fixes, preserving the newer released catalogue and PDF invoice client features.
See the [crash-fix handover](crash-fixes-2026-09-06.md) for source-version
reconciliation, regression evidence and remaining device checks. The full suite
now has **661 passing tests** and the same single unconfigured Firebase identity
failure; analysis of 214 Dart files has no errors or warnings. The local preview
was rebuilt successfully.

## Neutral palette refinement — 6 September 2026

Removed decorative green from the shared canvas, text, borders, generic highlight
panels, product placeholders, authentication emblem, onboarding notices and
ordering-link panel. Actions, selection, progress and confirmed positive states
retain their green accents. Banking verification uses a neutral icon until the
account is approved.

- Existing presentation and gallery checks: **100 passed**, including 320px
  layouts at normal and 200% text.
- Scoped analysis of the 10 changed Dart files: **no issues found**. Formatting
  and whitespace checks passed; Dart's telemetry write was sandbox-blocked after
  analysis and formatting completed.
- Release web preview rebuilt successfully; refreshed browser review confirmed
  the neutral palette on Login, Products and Recorded Sales. This is a local
  palette update; the full-suite and native-verification limits below remain
  applicable.

## App-wide rollout verification — 5 September 2026

The main style now extends through the remaining active screen families. The
[screen coverage](app-screen-coverage.md) links the route audits and describes
the 40-screen local gallery.

- Full suite: **620 passed, 1 failed** (the unchanged, unconfigured Firebase
  identity check).
- Gallery/setup integration: **123 passed**, including all 32 added layouts at
  320px with normal and 200% text and return/navigation checks.
- Final scoped analysis: **193 Dart files, 0 errors, 0 warnings**, with 27
  retained informational lints. Whitespace checks passed. Final repayment-report
  and customer-account copy checks passed after the full-suite run.
- Release web preview built successfully. Native authenticated flows still need
  device verification before release. No deployment was performed.

## Core-screen verification baseline — 5 September 2026

- Full Flutter suite: **526 passed, 1 failed**. The sole failure remains the
  Firebase environment-identity check because this checkout's ignored `.env`
  has no operational Firebase configuration. The check is unchanged and enabled.
- The final Products heading and Record Sale form color adjustments passed
  **51 focused tests** and scoped analysis after the full suite.
- Analysis of all 81 changed/new Dart files: no errors or warnings. The same
  11 informational lints remain in unchanged portions of `sale_view_model.dart`.
- Release web preview built successfully. Browser review covered Login,
  Products, Activity, Recorded Sales, the sales-details sheet and grouped
  Settings; stock filters and navigation were exercised. The remaining preview
  flows have widget coverage.
- Layout checks include 320px phones, short landscape, 200% text and keyboard
  obstruction. Existing validation, retry states, unread counts, stock filters,
  financial meanings and 50-entry Activity paging remain covered.
- `git diff --check` passed. Native authenticated verification remains pending
  before release; no deployment or external data mutation was performed.

## Verification baseline before the approachable selection — 5 September 2026

The results below belong to the preceding compact implementation. They are
retained as the integration baseline, not as verification of the approachable
changes described above. Final approachable verification is recorded separately.

- Full Flutter test suite: **523 passed, 1 failed**. The sole failure is the
  existing Firebase environment-identity check: this local preview deliberately
  has no configured Firebase project in its ignored `.env` asset. That test is
  neither disabled nor changed.
- Analysis of 81 changed/new Dart files: no errors or warnings; 11 informational
  lints remain in pre-existing sales transaction/legacy methods.
- Release web preview build succeeded. Existing web-bootstrap deprecation and
  optional Cupertino icon-font warnings remain; the redesigned controls use
  the bundled Material icon font.
- Final whitespace/diff check passed. Layout tests include 320px phones,
  short landscape, 200% text, keyboard obstruction, unread counts, validation,
  and retry/action availability. The local browser preview was visually reviewed.
- Authenticated native-device verification is pending before release. No
  deployment or external data mutation was performed.
