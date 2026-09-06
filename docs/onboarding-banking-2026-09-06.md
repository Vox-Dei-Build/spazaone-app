# Onboarding and banking edits — 6 September 2026

Implemented locally as part of the approved approachable redesign. No bank
account, production data, deployment, or release was changed during this work.

## Onboarding

- Removed the retired “Pasella is now Spaza One” popup and its startup gate.
- New shop owners can start by adding a customer, adding a product, or choosing
  **Explore the app**. The guide does not require completing setup before use.
- **Settings → Shop setup** remains a resumable guide. Everyday tools and
  optional online ordering, payout and promotion setup are grouped separately.
  Customer and product actions open their forms directly and return to the
  guide after saving.
- Copy distinguishes products selected for WhatsApp from confirmed catalogue
  status, and saved banking details from a verified payout account.
- Startup progress is scoped to the signed-in user, active shop and login
  session. Notification permission waits for the privacy choice to close and
  for onboarding and any selected form to finish. Offline or ineligible guide
  skips release that session without permanently marking the intro as seen.
- Intro eligibility uses bounded server reads and a resolved owner identity.
  Existing shops and operators skip the first-shop welcome. Late results from
  a previous shop cannot open a form or release the new shop’s startup queue.

## Banking details

- The saved payout account appears before the verification journey, with an
  explicit **Edit** action beside it for the active shop’s owner or admin.
- The editor starts from saved details and owns a separate draft. **Cancel**
  and Back leave saved values intact. Failed saves keep the draft available.
- Saving checks the current shop and editing permission again. Only successful
  persistence updates the saved values; the created document ID is retained so
  later edits update the same account. An account read failure offers Retry
  instead of a blank Add form.
- Verification remains a separate status and action. Editing details does not
  claim that the changed account is verified.

## Verification and release boundary

- Full Flutter suite: **688 passed, 1 failed**. The unchanged Firebase identity
  test still fails because the ignored preview `.env` has no operational
  Firebase identity (expected `pasella-ledger`, actual null).
- Final startup, consent, onboarding, attribution, activation and notification
  checks: **40 passed**. They include delayed notification lookup, route
  transitions, store changes and cancellation of obsolete startup generations.
- Final banking checks: **27 passed**, including prefilled editing, save/retry,
  cancellation and Back, current-shop/role restrictions, create/update document
  IDs, and 320px screens with 200% text.
- Static analysis of **225 changed/new Dart files**: **0 errors, 0 warnings**;
  96 informational lints remain. The final preview-only correction also passed
  scoped analysis.
- Browser review caught an existing blank Shop setup gallery sample caused by
  an empty synthetic shop ID. That preview now renders the actual guide, with
  a content assertion added to the layout checks. The final gallery/setup
  rerun passed **81 tests**, including 320px and 200% text.
- Final release web preview build succeeded. Browser review confirmed the
  initial choices, Explore dismissal, rendered setup guide, prefilled banking
  form, cancellation restoring the original name, and Save updating the
  fictional account summary. Whitespace checks passed.

The preview uses synthetic account details and never calls live banking
services. Its build and visual review are local; they do not verify managed
bank persistence or native notification permission behavior.

Before release, verify a configured development account through first login,
privacy dismissal, both initial actions, skipping, offline startup, store
switching and notification timing. Verify saved bank editing, cancelling,
saving, permission loss, a failed request, and the verification status after an
account change against the managed service.

The release-lineage limitation in [the crash-fix handover](crash-fixes-2026-09-06.md)
still applies: integrate the client changes on the current Vox Dei authority
revision while retaining its backend, rules and deployment configuration.
