# PAS-UX-03 — Handover

## Lane
- Slug: `pas-ux-03-send-confirmation-clarity`
- Branch: `fix/pas-ux-03-send-confirmation-clarity`
- Worktree: `/Users/admin/Sites/vox-dei/pasella-issue-worktrees/pas-ux-03-send-confirmation-clarity`
- Base: `origin/main` @ `b86c2c8`
- Head: `9c59a98`

## Status
- Implemented
- Verified

## What shipped
Single commit `9c59a98 fix(billing): relabel send-confirmation skip action from 'Cancel' to "Don't send"`.

Files changed:
- `lib/shared/billing/cost_confirmation_sheet.dart` — added optional
  `skipLabel` param (default `"Don't send"`) to `CostConfirmationSheet`
  and its `show(...)` helper; replaced both `Cancel` literals with the
  parameterised label; updated class docstring to lock in the
  negative-action semantics.
- `docs/openclaw/pas-ux-03-implementation-note.md` — implementation
  note (root cause, scope rationale, regression surfaces, verification).

No call sites were modified — the new default is correct for all five
current callers.

## Root cause (one line)
`CostConfirmationSheet`'s negative action was labelled `Cancel`, but in
every call site the underlying record is already persisted before the
sheet appears, so declining only skips the outbound message. The
`Cancel` label implied a transaction roll-back that does not happen and
caused the "continue without sending SMS" hesitation called out in the
delivery ticket.

## Surfaces touched
Only one component was edited. It is shared by these five call sites
(all retain identical semantics under the new label):
- `lib/pages/transactions/view_model/add_payment_view_model.dart:114`
- `lib/pages/transactions/view_model/add_credit_view_model.dart:136`
- `lib/pages/transactions/view_model/edit_transaction_view_model.dart:237`
- `lib/pages/contact/view_model/add_contact_view_model.dart:225`
- `lib/pages/contact/view_model/customer_management_view_model.dart:303`

## Verification performed
- `flutter analyze lib/shared/billing/cost_confirmation_sheet.dart` →
  zero new issues. The two `withOpacity` deprecation infos are
  pre-existing on the file and out of scope.
- Walked all five call sites to confirm the negative-path semantics
  match `"Don't send"` (record persisted, message skipped — or in the
  reminder case, no record exists and no message is sent).
- Mobile width: action-row hierarchy unchanged, button widths
  unchanged, label fits comfortably.
- Safari: N/A — native Flutter modal bottom sheet, not a web view.

## What was deliberately NOT touched
Per the Pasella mandatory rules:
- No broad modal rewrite.
- True destructive cancels left untouched: delete promotion
  (`view_promotion.dart:59`), delete template
  (`template_detail_page.dart:128`), delete product, discard unsaved
  changes guard (`transaction_form_scaffold.dart:108`),
  `ConfirmDialog.showDestructive` callers — all of these still genuinely
  mean cancel.
- No layout, hierarchy, or branching-logic changes inside the sheet.
- No call site copy changes — done entirely via the new default.

## Open risks / follow-ups
- **Localisation**: when i18n is wired up, both `Don't send` and
  `Top Up Wallet` will need translation keys. Today the surface uses
  raw English literals throughout, so no regression introduced.
- **Reminder flow nuance**: `customer_management_view_model.dart:303`
  is the one call site where no record is pre-persisted. `Don't send`
  is still literally accurate (no message goes out and there is nothing
  to undo). If product later wants the reminder negative action to read
  literally as `Cancel`, that single call site can pass
  `skipLabel: 'Cancel'` without touching the shared component.
- **Scaffolding files in the worktree** (`CHAT_PROMPT.md`,
  `LANE_CONTEXT.md`, `TASK_PACKET.md`, `OPENCLAW_HANDOFF_PROMPT.md`)
  remain untracked by design and were intentionally not committed.

## Reviewer checklist
- [ ] Confirm the new default `"Don't send"` reads correctly in product
      voice across all five call sites.
- [ ] Sanity-check on a real device that the wider button label does
      not wrap on the smallest supported width (it should not — verified
      visually but worth a device pass).
- [ ] Decide whether the reminder flow should override `skipLabel`.

## How to land
- PR target: `main`
- Suggested PR title: `fix(billing): clarify send-confirmation skip action ("Don't send" instead of "Cancel")`
- Recommended PR body: copy the root cause + surfaces touched + verification sections from this handover.

## Pointers
- Implementation note: `docs/openclaw/pas-ux-03-implementation-note.md`
- Delivery ticket: `/Users/admin/.openclaw/workspace/voxdei-os/04-Entities/Pasella/delivery-tickets/pas-ux-03-send-confirmation-copy-clarity-2026-05-10.md`
- Lane context: `LANE_CONTEXT.md` (in worktree root, untracked)
- Task packet: `TASK_PACKET.md` (in worktree root, untracked)
