# App design audit — 5 September 2026

The chosen direction is **Clean and approachable**. The shared vocabulary is
16px body text, 13px secondary text, 18px sections, 22px app-bar titles and 27px
authentication headings; 4/8/12/16/24/32 spacing; warm neutral pages, white rounded
surfaces, charcoal headings and green primary actions. Filled and outlined actions
use 52px targets, with 48px icon/text actions and 56px minimum Settings rows.
These are logical pixels before the user's text scale. Text must wrap or the
layout must stack instead of cutting off essential labels.

This is a source audit of the current Flutter checkout, with local widget checks
for the changes below. It does not claim authenticated end-to-end verification
of every route. The later app-wide pass audits remaining screen-level overrides and adds a
40-screen gallery; see the [coverage record](app-screen-coverage.md).

## Implemented and reviewable

| Area | Change and preserved behavior | Source |
| --- | --- | --- |
| Visual vocabulary | One named set of colors, spacing, corner radii and action icons is available to replace per-screen choices. | [spaza_tokens.dart](../lib/design/spaza_tokens.dart) |
| Settings | Rounded white panels group Shop, Preferences and Account on the soft page background. All nine existing actions remain, including notifications, privacy, help, logout and the separate account-deletion confirmation destination. Business name retains its named route. | [SettingsPage and SettingsMenu](../lib/pages/settings/settings.dart) |
| Settings rows | Shared rows use theme body/secondary text, fixed 22px icons on soft 36px tiles, a 56px minimum target, and adaptive height. Navigation rows show the same chevron; custom trailing controls remain supported. This also reaches existing callers in profile/settings without changing their actions. | [SettingTile](../lib/pages/settings/widgets/setting_tile.dart) |
| Store context | Stores & team keeps the active store, store count, role, loading and reconnect states in a smaller outlined entry. Long store names wrap. The existing feature flag and StoreSession ownership remain intact. | [StoreWorkspaceCard](../lib/pages/settings/stores/store_workspace_card.dart), [SettingsPage](../lib/pages/settings/settings.dart) |
| Store/team management | Active-store context wraps long names and keeps the current role inline. Management panels follow the shared 20px corner scale; actions and access checks remain unchanged. | [StoreManagementPage and ActiveStoreSummary](../lib/pages/settings/stores/store_management_page.dart) |
| Your shop | Shop link, store details, stores/team, ordering options and online payments now share Settings row typography and navigation. Existing callbacks and feature gates remain. | [YourShopOverview](../lib/pages/settings/setup/your_shop_page.dart) |
| Help | Tutorial labels use the same customer/product/sale terminology as the workspace. The privacy link uses the existing canonical AppUrls value, with visible feedback when opening fails. Tutorial configuration keys and the support action remain. | [HelpPage](../lib/pages/settings/help/help.dart), [AppUrls](../lib/constants/app_urls.dart) |
| Privacy labels | Settings describes analytics and crash reports, matching the two current Privacy switches instead of advertising a session-replay toggle that the page does not offer. | [SettingsMenu](../lib/pages/settings/settings.dart), [PrivacyPage](../lib/pages/settings/privacy/privacy_page.dart) |
| Ordering failure state | An initial read failure now shows a retry state. Editing and saving are unavailable until the current ordering options have loaded. A failed save preserves edits and says that saving failed. This avoids overwriting real settings with initial false/zero defaults after a failed read. | [OrderOptionsPage](../lib/pages/settings/order_options/order_options_page.dart) |
| Customer Activity | A rounded movement summary with a 30px medium-weight total leads into spacious dated sale/payment rows with 80px minimum height. Latest 50 entries appear initially; Show more reveals another 50. Counts and reconciliation use all queried entries. | [CustomerActivityTimeline](../lib/pages/reports/business_report/widgets/customer_activity_timeline.dart), [movement summary](../lib/pages/reports/business_report/widgets/date_range_movement_summary_card.dart) |
| Products | Rounded white product cards use 80px minimum rows, 48px thumbnails and 10px separation. Search, stock filters, stock-status labels and product callbacks remain; long details wrap within each card. | [ProductCatalogueView](../lib/pages/stock/product_group_page/widgets/product_list.dart) |
| Recorded sales | The rounded summary keeps one Record sale action and a scrollable full-details sheet. Spacious entries use 80px minimum rows. The selected sales period remains after recording/editing. | [SalesSummaryCard](../lib/pages/sales/widgets/sales_stats_card.dart), [RecordedSaleTile](../lib/pages/sales/widgets/sales_list.dart) |
| Recorded-sales read states | Failed queries show recoverable feedback instead of emitting empty results or zero totals. Previous entries/totals remain visible only when they belong to the same selected period; a different unverified period hides those values while retaining Record sale. Retry repeats the current query bounds, and stale requests cannot replace newer results. | [RecordedSalesReader](../lib/pages/sales/view_model/recorded_sales_reader.dart), [SalesViewModel](../lib/pages/sales/view_model/sale_view_model.dart), [SalesList](../lib/pages/sales/widgets/sales_list.dart), [summary availability](../lib/pages/sales/widgets/sales_stats_card.dart) |
| Multi-year sales dates | Entries outside the current year display their year; screen-reader date labels always include it. | [RecordedSaleTile](../lib/pages/sales/widgets/sales_list.dart), [date regression test](../test/recorded_sales_redesign_test.dart) |
| Authentication | Shared login, mobile entry, registration and profile presentation uses the official wordmark, a pale 64px store emblem and a rounded white form panel with a 27px charcoal headline. Visible external labels and a 52px Continue action remain readable; the emblem and gaps shrink when the keyboard or a short screen needs room. Forms and OTP controls remain scrollable, with existing authentication/consent gates intact. | [AuthShell](../lib/pages/auth/widgets/auth_shell.dart), [phone form](../lib/pages/auth/widgets/login_ui.dart) |
| Shared forms | Theme-based labels/fields/actions, consistent minimum targets, first-error reveal, keyboard-safe action placement and back navigation honoring unsaved edits. | [form scaffold](../lib/shared/widgets/forms/transaction_form_scaffold.dart), [fields](../lib/shared/widgets/custom_text_field.dart) |
| Customer detail navigation | Pay later, Orders and Messages use a rounded soft section group with a white selected tab. Unread badges are consistent, capped visually at 99+ and expose the actual count to screen readers. Existing tab selection and unread-clearing logic remain. | [CustomerManagementPage](../lib/pages/contact/contact_management.dart), [WorkspaceSectionTabs](../lib/shared/widgets/workspace_section_tabs.dart) |
| Wallet | Balance, payment status and menu follow shared typography, neutral hierarchy and rounded surfaces. Repayment detail controls stack at large text. Financial calculations and callbacks remain. | [wallet presentation](../lib/pages/wallet/wallet.dart) |
| Marketing | A rounded introduction and readable campaign history inherit the shared approachable palette and type. The introduction scrolls away on short screens; Choose product, review and Run again preserve existing callbacks. | [MarketingOverview](../lib/pages/sales/widgets/marketing_overview.dart), [PromotionHistoryCard](../lib/pages/promote/widgets/promotions/promotions_tab.dart) |

The [design system guide](app-design-system.md) defines foundations and the local
interactive preview. Shared typography no longer depends on device height.

## Remaining findings and opportunities

These are concrete follow-up targets from the source scan, not claims that an
unexecuted live flow failed. Changes being integrated by other owners should be
removed from this list once their final evidence is recorded.

| Priority | Finding and user impact | Evidence and next step |
| --- | --- | --- |
| Medium | The Activity list now bounds rendering, but its range read still fans out across every customer and reads every matching entry. All dates can remain expensive despite the initial 50-row display. | [DateRangeLedgerDrilldown, `_load`](../lib/pages/reports/business_report/widgets/date_range_ledger_drilldown.dart). A later data-layer change should use a query/index strategy that can page records while obtaining trustworthy totals separately; do not calculate totals from only visible rows. |

## Legacy surfaces kept out of the active redesign

The current route table and call-site search did not identify a live entry to
`SecurityPage`, `BackupPage`, `AccountPage` or the old `ProfilePage`. They contain
prototype behavior: Security toggles change in-memory flags and PIN/sign-out
callbacks are empty; Backup shows a literal 2023 sync time and an empty Sync Now
callback; Account has a literal customer amount; Profile's Save Changes callback
is empty. Making these screens look finished would misrepresent their behavior.
They should remain unreachable until explicitly implemented or be removed in a
separate cleanup.

Evidence: [main route table](../lib/main.dart),
[security](../lib/pages/settings/security/security.dart),
[AppModel switch flags](../lib/models/common/app_model.dart),
[backup](../lib/pages/settings/backup/backup.dart),
[account](../lib/pages/settings/account/account.dart),
[profile](../lib/pages/profile/profile.dart).

## App-wide pass

The subsequent rollout covers remaining customer/account/message, product and
supplier, order/receipt, wallet, campaign/template, setup and shared presentation.
Full suite: **620 passed, 1 failed**, with the same absent Firebase configuration.
The 40-screen gallery and its 123-check integration run make the resulting
layouts reviewable. See [screen coverage](app-screen-coverage.md) for the
per-family source records and device verification gate.

## Core-screen verification baseline

The chosen design is implemented in the shared theme and active presentation
widgets. The full local suite reports **526 passed, 1 failed**; the unchanged
Firebase configuration-identity test cannot pass without the operational
configuration absent from this checkout. Final style adjustments passed another
51 focused checks. Static analysis found no errors or warnings in the 81
changed/new Dart files; the 11 existing informational lints remain in unchanged
sales view-model methods.

The release web preview was built and visually reviewed. Stock filters,
workspace navigation, sales details and grouped Settings were exercised in the
browser. See the [design guide](app-design-system.md) for the complete local
verification scope and native-device release gate.

## Verification baseline before approachable — Settings

These results precede the approachable selection and document the existing
behavior checks. They do not replace final verification of the new presentation.

Seventeen focused tests passed with Flutter 3.29.2. Scoped static analysis and
`git diff --check` also passed. The final store-context changes were rechecked
alongside consent behavior after the full suite.

The checks cover existing Settings/setup navigation, every Settings
callback at 320px with 200% text, fixed theme typography on a larger screen,
long active-store names, loading/reconnect states, Your shop accessibility,
ordering read failure/retry, ordering save failure with retained edits, saved
fee conversion and existing consent-state rules. Relevant tests:

- [settings_information_architecture_test.dart](../test/settings_information_architecture_test.dart)
- [store_workspace_card_test.dart](../test/store_workspace_card_test.dart)
- [your_shop_overview_test.dart](../test/your_shop_overview_test.dart)
- [order_options_page_test.dart](../test/order_options_page_test.dart)
- [consent_effective_state_test.dart](../test/consent_effective_state_test.dart)

No authenticated settings were read or changed and no external link was opened
by these tests. The app still needs integrated native-device review of login,
keyboard/validation, customer tabs, wallet, settings and checkout using the same
text-scale and screen-size matrix before release.

## Verification baseline before approachable — recorded-sales failure states

These results precede the approachable selection and remain the behavior
baseline for the retained reader and recovery logic.

Twenty-three focused tests passed across injected read failures/recovery,
matching-period cache retention, changed-period suppression, stale-request
ordering, disposal, truthful empty results, 320px/200% retry accessibility,
summary availability, year-aware dates and existing amount/attachment behavior.
The injected-reader tests use the same controller as SalesViewModel and make no
Firestore or payment writes. Cash/status exclusions, range bounds and financial
calculations remain unchanged.

Evidence: [recorded_sales_reader_test.dart](../test/recorded_sales_reader_test.dart),
[recorded_sales_redesign_test.dart](../test/recorded_sales_redesign_test.dart),
[sale_stock_amount_test.dart](../test/sale_stock_amount_test.dart),
[concise_sales_empty_state_test.dart](../test/concise_sales_empty_state_test.dart),
[stock_invoice_attachment_test.dart](../test/stock_invoice_attachment_test.dart).
