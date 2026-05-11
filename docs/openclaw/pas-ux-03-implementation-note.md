# PAS-UX-03 — Send confirmation clarity (implementation note)

## Surface
`lib/shared/billing/cost_confirmation_sheet.dart` — the modal bottom sheet
shown immediately before a wallet-deducting outbound message (transaction
edit, add credit, add payment, add contact welcome, payment reminder).

## Root cause
The sheet's two-button row was labelled `Cancel` / `Send`. In every call
site that drives this sheet, the underlying record (transaction, contact)
is **already persisted** before the sheet appears. Returning `false` only
skips the outbound notification — it does not roll back the transaction.
Calling that path "Cancel" implied the whole action would be undone, which
caused merchant hesitation and the wrong mental model for the
"continue without sending SMS" path described in the delivery ticket.

## Change
- Added optional `skipLabel` parameter to `CostConfirmationSheet` and the
  static `show(...)` helper. Default value: `"Don't send"`.
- Replaced the two `Cancel` literals (the affordable-branch outlined
  button and the insufficient-balance fallback `TextButton`) with the
  parameterised `skipLabel`.
- Updated the class doc comment to document the negative action's true
  semantics so future call sites do not regress to "Cancel".

No call site needed to change: the new default is correct for all current
use sites (`add_payment_view_model`, `add_credit_view_model`,
`edit_transaction_view_model`, `add_contact_view_model`,
`customer_management_view_model`).

## Why this is the smallest correct fix
- Copy-only change inside one shared component.
- No layout, hierarchy, or branching-logic changes.
- The destructive `Top Up Wallet` action and the primary `Send` CTA are
  untouched, so action hierarchy and momentum are preserved.
- True destructive cancel dialogs elsewhere (delete promotion, delete
  template, discard unsaved changes, delete product) were intentionally
  left alone — they truly mean cancel.

## Regression surfaces
Five call sites reuse this sheet. All five share the same semantics
(record already written, sheet only gates the message), so the new label
is accurate everywhere:
- `lib/pages/transactions/view_model/add_payment_view_model.dart:114`
- `lib/pages/transactions/view_model/add_credit_view_model.dart:136`
- `lib/pages/transactions/view_model/edit_transaction_view_model.dart:237`
- `lib/pages/contact/view_model/add_contact_view_model.dart:225`
- `lib/pages/contact/view_model/customer_management_view_model.dart:303`
  (payment reminder — no record is created, but "Don't send" is still the
  literal truth of the action and is less ambiguous than "Cancel").

## Verification
- `flutter analyze lib/shared/billing/cost_confirmation_sheet.dart`
  reports zero new issues. The two `withOpacity` deprecation infos are
  pre-existing and out of scope.
- Mobile (the only target the sheet renders on — Pasella is a Flutter
  mobile app): action-row hierarchy unchanged, button widths unchanged,
  `Don't send` fits comfortably on the smallest supported width.
- Safari: N/A — this surface is a native modal bottom sheet inside the
  Flutter mobile app, not a web view.

## Risks / follow-ups
- Translations: if/when localisation is wired up, both `Don't send` and
  `Top Up Wallet` will need entries; today the codebase uses raw English
  literals throughout this surface so no regression.
- The reminder-only flow (`customer_management_view_model`) does not
  pre-persist a record. "Don't send" is still accurate (no message is
  sent and nothing to undo), but if product later wants the reminder
  flow's negative action to read literally as `Cancel`, they can pass
  `skipLabel: 'Cancel'` from that one call site without touching the
  shared component.
