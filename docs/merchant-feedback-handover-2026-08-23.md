# SpazaOne merchant-feedback handover — 23 August 2026

## Continuation objective

Continue from this handover without restarting the commerce/release work. First
diagnose the production checkout and payment failures with read-only evidence,
then implement and verify the smallest safe fixes across the Vox Dei authority
repositories. Do not deploy, submit a store release, enable a production gate,
or mutate production data without the user's explicit action-time confirmation.

## Authority and current sources

- Entity and release authority: Vox Dei.
- App and Functions authority: `Vox-Dei-Build/spazaone-app`.
- App worktree at handover: `/Users/admin/.codex/worktrees/c7b2/pasella-app`.
- App worktree HEAD at handover: `8ab5dcdd8e38`; worktree clean.
- Bot authority: `Vox-Dei-Build/spazaone-bot`.
- Bot authority checkout: `/Users/admin/Sites/vox-dei/pasella-botpress`.
- Bot authority HEAD at handover: `2579f5242e30` on `main`; worktree clean.
- Delta repositories remain backup mirrors and must not be used as release
  sources.

## Store-release state to preserve

- Android `4.8.1` build `94` is saved in Google Play as an unsubmitted
  **100% full production rollout**. Do not submit it while the reported
  checkout/payment behavior is unresolved unless the user explicitly chooses
  otherwise at action time.
- iOS `4.8.1` build `94` is in TestFlight. Creation/submission of the App Store
  version is blocked by Apple's updated Developer Program License Agreement.
  Apple requires Account Holder Rebecca Godfrey to accept that agreement.
- The handover itself authorizes no deployment or release action.

## Merchant feedback and confirmed interpretation

### 1. Stock-invoice photos belong on Sales, not Stock

The earlier interpretation was wrong. The merchant wants a scan or photo of a
stock-purchase invoice attached from the **Sales** journey. The current
`Record Sale` form already captures both `Sales amount` and `Stock amount`, so
the attachment belongs beside the restocking amount and on the resulting sale
record—not on a product or the Stock page.

Recommended MVP:

- Add `Attach stock invoice` below `Stock amount` on `Record Sale` and its edit
  flow.
- Allow camera capture and gallery selection. Support multiple pages/images
  with a small documented cap; do not add OCR in the first release.
- Show upload progress, thumbnail/filename, retry, remove and replace.
- Show the attachments on `Sale Details`, labelled `Stock invoices`.
- Keep the existing sale write usable when no invoice is attached.
- Store only attachment metadata on the sale document and keep the binary in a
  store-scoped Firebase Storage path. Reuse the existing image conversion and
  permission handling in `lib/utils/photo_upload_util.dart` where suitable.
- Enforce the same store membership/role boundary as the sale record. Do not
  create a public download URL, expose another store's files, or retain EXIF
  location metadata.

Likely app entry points:

- `lib/pages/sales/widgets/add_sale.dart`
- `lib/pages/sales/widgets/edit_sale.dart`
- `lib/pages/sales/widgets/sale_detail_page.dart`
- `lib/pages/sales/view_model/sale_view_model.dart`
- `lib/models/sales/sales_model.dart`
- Firebase Storage rules and their emulator tests

Acceptance evidence:

1. Record a sale with a non-zero stock amount and one camera image.
2. Record another with multiple gallery images.
3. Reopen and edit the sale; attachments remain visible and removable.
4. Simulate upload and Firestore-write failures; no false success or orphaned
   user-visible attachment remains.
5. Prove cross-store reads/writes are rejected in Storage rules tests.
6. Verify Android and iOS permission, large-text, small-screen and offline/retry
   behavior.

### 2. No alert when a merchant requests bank verification

Merchant feedback: the SpazaOne administrator/operations reviewer receives no
message when a merchant submits banking details for verification.

This is a confirmed code-path gap, not yet proven to be an FCM device fault:

- `upsertSettlementAuthorizationRequest` writes or refreshes the durable
  `paymentAdministrationRequests` record.
- Existing `functions/src/payments/v2/settlementNotifications.ts` sends the
  merchant an outcome notification only after an administrator approves,
  requests changes or rejects the request.
- No request-created operations notification was found in the current source.

Required behavior:

- On a genuinely new/refreshed transition to `authorization_required`, create
  one deterministic, durable operations notification and attempt an immediate
  push to the registered payment-review recipient(s).
- A repeated tap on the unchanged request must not generate another alert or
  reset queue age.
- Copy must be purpose-limited, for example: `A merchant requested bank
  verification. Open the SpazaOne workspace to review it.` Do not place bank
  numbers, identity values, provider identifiers or reviewer notes in the push.
- Deep-link to the authenticated workspace review queue or the app's protected
  review surface. The destination must still enforce payment-admin authority.
- Record `delivered`, `not_delivered` or `no_registered_device` without rolling
  back the request. The durable workspace queue remains the source of truth.
- Confirm the intended operations account and notification-token source before
  implementing the write; do not broadcast the alert to every merchant.

Acceptance evidence:

1. A new request produces one queue item and one operations alert.
2. Repeated taps on the same bank-detail version produce no duplicate alert.
3. A materially changed bank-detail version produces a new actionable alert.
4. Disabled/missing push still leaves an auditable queue item.
5. Notification payload and logs contain no unmasked banking or identity data.

### 3. Bot checkout reports a generic temporary failure

Screenshot evidence:

`/Users/admin/Documents/WhatsApp Image 2026-08-23 at 07.59.22.jpeg`

Observed at approximately 07:57 SAST on 23 August 2026:

- WhatsApp recipient shown: `+27 60 *** 7119` (masked in this handover).
- The customer had an R40 order draft and selected `Yes, send it`.
- The bot replied: `Ordering is temporarily unavailable, so no order was
  placed. Please try again shortly or contact the shop. Your order is still
  here.`
- The screenshot proves the order was **not created** and the draft/cart was
  retained. It does not prove that Paystack was reached.

The exact copy is the `enableLiveCheckout === false` branch in
`/Users/admin/Sites/vox-dei/pasella-botpress/src/confirmation.ts`. The next
task must therefore determine why the deployed conversation received
`enableLiveCheckout: false` before changing copy or payment code.

Read-only diagnosis first:

1. Retrieve the production Botpress event/log around 07:57 SAST and correlate
   it to the merchant/store, conversation and request without copying message
   content or credentials into the handover.
2. Inspect the deployed Botpress configuration for
   `PASELLA_ENABLE_LIVE_CHECKOUT` / `enableLiveCheckout` and compare the
   production core and ADK paths.
3. Inspect the backend merchant context and authoritative ordering/payment
   readiness returned for that store.
4. Confirm whether this is a global bot gate, merchant gate, stale deployment,
   missing customer binding, or backend failure. Do not infer the cause from
   the user-facing text.

UX contract after the cause is known:

- If ordering is intentionally disabled for that shop, do not present a live
  checkout confirmation. Say before checkout that the shop is currently
  browse-only and provide the permitted contact/manual-payment route.
- If order creation fails unexpectedly, say the order was not sent, preserve
  the cart, provide `Try again` and `Contact shop`, and emit a merchant-visible
  operational alert/correlation ID.
- Separate `ordering unavailable` from `secure online payment unavailable`.
  Cash/manual EFT orders must not be blocked merely because hosted payment is
  unavailable, provided those methods are enabled for the merchant.
- Never show banking details or tell the customer to pay until the order has
  been created exactly once and has its final payment reference.

### 4. Choosing more than one item is unclear

The backend already has a multi-product cart (`addToCart`, `getCart`, quantity
updates, removals and a multi-item `checkoutCart`). The commerce handover also
records multi-product cart support. Treat this as a conversation/affordance
problem unless testing proves a backend defect.

WhatsApp list replies are single-selection controls, so the safe experience is
sequential addition rather than promising literal multi-select:

1. Choose a product.
2. Choose quantity.
3. Show the cart summary.
4. Offer a prominent `Add another item` action that returns to search/browse.
5. Repeat until the customer chooses `Checkout`.

Acceptance evidence:

- Add three different products, including a repeated product whose quantity is
  increased rather than duplicated incorrectly.
- Edit quantity, remove one line and return to browsing without losing the
  cart.
- Confirm once; create one order with the correct lines and total.
- Exercise typed replies when WhatsApp structured actions are unavailable.
- Keep owned-stock and supplier restrictions truthful; do not silently combine
  an unsupported mixed cart.

### 5. Online payment is reported as not going through

This is a separate merchant report with no payment-error screenshot or
provider receipt attached. The supplied screenshot fails before order creation,
so it cannot establish a Paystack failure. Diagnose in this order:

1. Restore/prove order creation for an enabled merchant and channel.
2. Capture the Payments V2 intent/reference and public failure code for one
   low-value canary attempt.
3. Correlate Functions logs, immutable provider-event inbox, Paystack
   transaction state, webhook projection and order state.
4. Verify that the approved channel list presented by the app/bot matches the
   live Paystack account. Do not re-enable unapproved channels speculatively.
5. Verify exactly-once settlement, inventory/cart finalization and merchant/
   customer notification after a successful webhook-owned payment.

Minimum passing journey:

- One order is created before payment.
- One active, approved hosted channel opens successfully.
- A successful provider event marks the order paid exactly once, clears the
  cart once and produces the expected notification/ledger evidence.
- Closing or failing hosted checkout does not mark the order paid and gives an
  actionable retry route.

## Priority and execution order for the next task

1. **P0 — Production evidence:** diagnose the bot checkout gate and the
   reported online-payment failure without changing production.
2. **P0 — Truthful recovery:** fix any incorrect global/per-store gate or stale
   deployment in source, and make order/payment failure copy distinguish the
   actual state.
3. **P1 — Verification alert:** add the idempotent administrator/operations
   notification for new settlement-verification requests.
4. **P1 — Multi-item clarity:** expose and test the sequential `Add another
   item` cart loop in both production-core and ADK bot paths.
5. **P1 — Sales invoice attachment:** implement the camera/gallery MVP on the
   Sales record with secure Storage rules and failure cleanup.
6. Run focused tests first, then full Flutter, Functions, rules and bot suites.
   Verify core/ADK drift and produce exact artifact/source hashes.
7. Test in development/internal distribution before any production change.
8. Request action-time confirmation before any production deployment, bot
   publish, gate enablement or store submission.

## Continuation evidence — 24 August 2026

### Paid campaign top-up: provider-confirmed root cause

Read-only inspection used the registered Delta Chrome profile at the user's
direction. The Paystack service itself showed the SpazaOne workspace in live,
approved mode and showed the incident charge as successful with one attempt and
no provider error. The account's live webhook field was empty. Its test webhook
was configured to the development verifier, while no live callback URL was
configured. The visible audit history contained test-webhook changes only.

This closes the primary cause: production initialized and collected the charge,
but Paystack had no production webhook destination to which it could deliver
the successful event. Firestore therefore had no provider event to project,
and the internal reconciliation job could not infer an external success from
an intent that remained `initialized`.

No Paystack setting or production financial record was changed during the
inspection. Adding a live webhook does not establish that Paystack will replay
an event that occurred while no endpoint was configured, so the existing
payment still needs an independently verified, exact-once recovery.

### Local recovery implementation

The Functions working set now includes an admin-only callable recovery path:

- `recoverCampaignTopupV2OnDemand` accepts only an existing intent ID, an
  operation ID and an audit reason.
- It requires the existing payment-admin claim, allowlisted verified Google
  identity, allowed workspace origin, recent authentication, App Check and a
  non-replayed App Check token.
- The server obtains the immutable merchant and Paystack reference from the
  stored intent and independently calls Paystack Verify Transaction with the
  environment-bound payment credential. The caller cannot supply a merchant,
  reference, amount, fee, channel or credit value.
- Only the payment fields required for binding are canonicalized; provider PII
  is neither copied into the event payload nor returned to the caller.
- The verified transaction is applied through
  `applyVerifiedCampaignTopupV2`, preserving the existing transactional wallet,
  purchase, activity and intent projections.
- Recovery and webhook events have distinct deterministic identities. A later
  genuine webhook is closed as deduplicated and attached to the paid intent
  without crediting again. Events created before the ingestion-source field was
  added remain replay-compatible.
- `paymentRecoveryOperations` records immutable operation binding, actor,
  reason digest, processing lease, attempt count, safe failure code and final
  internal event receipt. It stores no provider reference.
- The restricted Payment Operations workspace now exposes this exact command
  behind its existing verified Google-admin session, step-up reauthentication,
  typed confirmation and limited-use App Check token. Browser code can submit
  no merchant, provider reference, amount, fee, channel or credit. Ambiguous
  retries retain the same operation ID until the operator changes the binding.

Verification completed locally:

- Functions lint: 0 errors and 100 pre-existing warnings; the new recovery
  file has no lint warning.
- Functions build: passed.
- Functions `test:ci`: 236/236 passed.
- Payment V2 Firestore emulator integration: 15/15 passed, including
  same-operation replay, a second independently named recovery, a delayed real
  webhook, old-event source compatibility and provider-failure/no-credit.
- Payment Operations security contracts: 8/8 passed; production Vite build
  passed with zero package-audit vulnerabilities.

No function or workspace build was deployed and the successful production
charge remains unreconciled. The next production actions remain separately
confirmation gated: deploy the exact verified Functions and workspace
revisions, configure the Paystack live webhook to the explicit
`pasella-ledger` verifier, invoke one audited recovery for the existing intent,
and verify one R200 credit with no duplicate purchase/activity/event
application.

## Suggested next-chat opening prompt

> Continue SpazaOne merchant-feedback hardening from
> `docs/merchant-feedback-handover-2026-08-23.md`. Do not start from scratch.
> Use only the Vox Dei authority repositories. Preserve the unsubmitted Android
> 4.8.1 build 94 full-rollout draft and do not deploy, publish the bot, enable a
> production gate or submit a store release without my action-time
> confirmation. Start with read-only evidence for the 07:57 SAST WhatsApp
> checkout failure and the reported online-payment failure, then report the
> exact cause and implement the priority-ordered local fixes with tests.
