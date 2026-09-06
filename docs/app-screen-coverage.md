# Approachable design rollout — 5 September 2026

The chosen **Clean and approachable** style now reaches the active app families
through shared foundations and an audit of their remaining presentation
components. The 40-screen local gallery uses production widgets with synthetic
state. It is a design review tool, not an authenticated copy of every route.

| Family | Applied presentation | Coverage record |
| --- | --- | --- |
| Authentication and account setup | Login, phone/OTP, registration/profile, anonymous compatibility flow, required-name gate, business type/category choices | [Account and setup](design-coverage-settings.md) |
| Customers, accounts and messages | Customer list/detail, balance, actions, messages, credit/payment/edit flows, repayment and reports | [Customer coverage](design-coverage-customers.md) |
| Products and stock | Product create/edit, search, stock reports, suppliers/catalogue/listings, sale detail/edit and attachments | [Product coverage](design-coverage-products.md) |
| Sales, online orders and receipts | Main sales presentation, online lists, order/receipt details, amounts, status and action controls | [Commerce coverage](design-coverage-commerce.md) |
| Wallet and payments | Banking, balances/history, costs, payment/top-up states, repayment report and suspension presentation | [Commerce coverage](design-coverage-commerce.md) |
| Marketing | Campaign/template choices, review, history and detail presentation | [Commerce coverage](design-coverage-commerce.md) |
| Settings and shop | Grouped Settings, Your shop, setup, ordering options/link, store context, Privacy, Help and tutorial frame | [Account and setup](design-coverage-settings.md) |
| Shared components | Fonts, colours, spacing, shape, fields/actions, tabs, headers, empty states, consent and responsive layout | [Design system](app-design-system.md) |

## Review locally

Open the app preview and choose **All screens**. Search by name or browse the
five groups. Opening a secondary screen keeps the gallery behind it, so Back
returns to the same place. The eight main screen choices remain available in
the top selector. The gallery contains 32 additional layouts, not just new
colour mockups.

The examples do not send messages, submit campaigns, start payments, create
accounts or save server data. Rates and financial values are labeled examples.
Some secondary previews show the shared content rather than a live backend
container: for example Active store is a summary, and Bank details lets you edit
a fictional account in memory using the production form. No account access or
device permission is needed to review.

The updated first-use choices, removed rebrand popup, startup sequencing and
bank-account editor are documented in [the onboarding and banking
handover](onboarding-banking-2026-09-06.md).

## Verification

- Full Flutter suite: **620 passed, 1 failed**. The unchanged Firebase identity
  configuration test fails because this checkout lacks operational `.env`
  values. It has not been disabled or worked around.
- Gallery/setup integration: **123 passed**, including every added screen at
  320px with normal and 200% text, local privacy controls, navigation, setup,
  consent and short-screen tutorial support.
- The release web preview build succeeded with the existing web-bootstrap and
  optional Cupertino icon-font warnings.
- Final analysis of **193 changed/new Dart files**: **0 errors, 0 warnings**;
  27 retained informational lints remain. Whitespace checks passed.
- The final repayment-report layout check and both customer-account copy
  regression cases passed after the full-suite run. The final preview was
  rebuilt and browser-reviewed; gallery search/return navigation, customer
  account and campaign-review presentation were exercised.

New layout checks led to fixes for large-text supplier cards, campaign review
rows and the customer account's short-screen scroll area. Display formatting of
integer-valued sale prices and payout amounts is normalized without changing
those values or calculations.

## Release gate and excluded code

This work is implemented locally. Authenticated device verification remains
necessary for OTP, photo permissions/uploads, store/team access, payment and
campaign operations, deletion, hosted support/video, and platform share sheets.
Their service logic and access gates are retained. No deployment was performed.

Unreachable prototype screens and old duplicate widgets have not been promoted
into active navigation. Coverage records distinguish those from live routes and
from service-owned content; styling them must not imply that placeholder
features work.
