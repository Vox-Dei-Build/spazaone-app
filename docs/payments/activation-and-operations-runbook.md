# Payments V2 activation and operations runbook

Baseline: `4.7.1+87` (`28290792c455ceaabfc2eff4b7776eccda451b19`)

This runbook is deliberately fail-closed. Merging the code does not enable a
payment capability, deploy Functions, charge a customer, purchase a CJ order,
or submit a store build.

## Control hierarchy

Every transaction requires all four controls to agree:

1. `PAYMENTS_V2_MASTER_ENABLED=true` in the explicit Functions environment.
2. `paymentConfiguration/global.emergencySuspended != true`.
3. The payment purpose is enabled in
   `paymentConfiguration/global.capabilities`.
4. For settlement purposes, the merchant is `enabled` and has that same
   purpose in `merchantPaymentProfiles/{merchantId}.capabilities`. Campaign
   Credits do not require a settlement destination; a suspended merchant or
   an explicit merchant-level Campaign Credit disable still blocks them.

All controls default to disabled. `setGlobalPaymentConfigurationV2` and
`setMerchantPaymentState` require the `spazaAdmin` claim, an audit reason and
write immutable audit records. Collection capabilities cannot be enabled for
a merchant until their resolved Paystack subaccount has been approved.
`campaign_credit` is the intentional exception because its proceeds do not
settle to the merchant.

Direct WhatsApp adds a separate merchant-app compatibility gate. Delivery,
Pay Later, owned-order payments, account payments and supplier ordering require
an authenticated merchant heartbeat from build 88 or newer. The default can be
advanced per feature through `config/app.botFeatureMinimumBuilds`. Older
merchants keep legacy owned-product browsing, pickup, cash and manual-transfer
ordering, but the server masks newer choices and rejects a direct or stale bot
request. `whatsappEligibleOverride` and `forceEnableUntil` do not bypass this
feature-level gate.

The emergency response is to set `emergencySuspended=true`, preserve the
affected records, run reconciliation, and identify every charged intent that
still needs fulfilment or a refund. Do not delete or rewrite provider events.

## Capability activation

Keep all capabilities dark while the backwards-compatible production backend
and exact `4.8.0+88` signed artifacts are verified. After the full development,
emulator, TestFlight/Play Internal Testing and approved low-value live evidence
pack passes, globally activate these four capabilities together:

1. `campaign_credit`
2. `merchant_order`
3. `account_settlement`
4. `supplier_order`

There is no controlled customer pilot and no seven-day waiting period. Review
reconciliation and support evidence continuously after activation, and use the
global kill switch immediately if any stop condition appears.

Supplier ordering is a blocker for that combined activation, not a later
pilot. It remains dark with the other three capabilities until CJ fulfilment,
funding, tracking and refund evidence passes and split-refund recovery is
proved in writing or by controlled full and partial live tests that reconcile
both Delta and merchant shares.

The 13 August development rehearsal reached the supplier-funding gate and
stopped safely before Paystack because the CJ sandbox balance could not cover
the USD 5.76 quote. This is an operations/provider-funding blocker, not a
reason to bypass the gate: fund sandbox, repeat the successful create/pay and
tracking path, then exercise deterministic failure/refund and ambiguous-result
recovery before the combined activation can proceed.

`repayment_installment` remains independently disabled until full and partial
account settlement has passed its live checkpoint. Premium, subscriptions,
custom merchant payment links, Apple Pay and Google Pay are not part of this
programme.

## Operations ownership

| Condition | System state | Owner | Required action |
| --- | --- | --- | --- |
| Paystack initialized but no charge | `initialized` | Customer/support | Customer can retry the same hosted URL until expiry. No ledger change is allowed. |
| Charge confirmed and inventory committed | `paid` | Merchant | Prepare and fulfil the owned-stock order. |
| Charge confirmed but reservation unavailable | `refund_pending` | Operations | The durable refund worker submits/reconciles the provider refund. Stock is not guessed. |
| Supplier charge confirmed | fulfilment `queued` | Operations automation | Re-quote CJ, verify route/price/balance, create and pay the CJ order. |
| CJ is authoritatively absent after a deterministic pre-create failure | `refund_pending` | Operations automation | Request the Paystack refund and keep it pending until provider confirmation. |
| CJ create/pay result is ambiguous or an order may exist | `operations_review` | Operations | Do not retry payment or promise a refund. Query CJ, delete only a confirmed unpaid `CREATED`/`IN_CART` order where allowed, then choose one accountable recovery. |
| CJ is confirmed unpaid after a payment-call failure | fulfilment `retry` | Operations automation | Retry only payment for the same CJ order; never create or pay a second order blindly. |
| Refund is pending/processing | `refund_pending` | Operations/support | Explain that the provider is processing it; never say refunded. |
| Refund needs attention/fails | `provider_failed` or provider status | Operations | Resolve with Paystack and re-run reconciliation. Do not locally complete it. |
| Reconciliation mismatch | run `mismatch` | Engineering + finance | Globally suspend payments and account for every cent before resuming. |
| Settlement destination changes | merchant `pending_review` | Admin + finance | New online initialization is suspended. Reconcile pending settlements, approve the exact new fingerprint, activate it and retire the old subaccount only when safe. Existing intents retain their immutable destination snapshot. |

## Merchant Payment Setup

- Existing merchants explicitly choose Payment Setup and provide the one-time
  personal identity/passport or business-registration evidence Paystack
  requires. Legacy bank records are never silently migrated.
- New merchants can continue with cash and Pay Later, but online selling stays
  disabled until setup is complete.
- South African banks come from Paystack's verification-enabled bank list and
  accounts are validated through Paystack's bank-validation endpoint.
- Full identity, passport and business-registration numbers are transient and
  never stored. The server retains a keyed fingerprint, account/document type,
  verification flags, masked account holder and account last four only.
- Validation is deduplicated and protected by the billable-verification limits
  below. Provider verification never grants settlement authority by itself;
  every new destination remains inactive and pending an audited Spaza One
  admin review.

### Billable-verification fraud controls

Paystack charges R3 for each successful South African Account Validation API
call. Treat this as a billable fraud surface, even though it verifies bank
accounts rather than charging or validating cards.

- The endpoint accepts only a server-loaded saved bank account and explicitly
  rejects card/PAN/BIN/CVV/expiry/authorization fields or a card instrument
  type. No card BIN, card authorization or card verification API is called.
- A valid Firebase ID token and valid App Check attestation are both required.
  Only the merchant owner or an active store admin may initiate validation;
  ordinary operators cannot.
- Before the endpoint can call Paystack, a `spazaAdmin` must open a single
  audited 24-hour authorization with at most two attempts. New stores and new
  app installs have no verification authority by default. Authorization is
  consumed transactionally and can be revoked immediately.
- Exact active or pending destinations deduplicate before another validation.
- Limits are two provider attempts per merchant per UTC day, six per merchant
  lifetime before support review and ten for the entire platform per UTC day.
  At the current published tariff this bounds the worst-case daily successful
  validation exposure to R30.
- The seventh platform attempt opens an operations warning. The tenth opens a
  critical alert and automatically sets
  `settlementVerificationSuspended=true`; further attempts fail before Paystack.
- Attempts, maximum exposure and provider-accepted estimated cost are stored in
  server-only `paymentSecurityBudgets`; no client can alter the counters.
- Only the request that acquired the serialized verification claim may release
  or fail it, preventing concurrent replay from clearing another attempt’s
  lease.
- Resumption requires an authenticated `spazaAdmin` configuration action with
  an audit reason. Never lift the circuit breaker without reviewing merchant,
  device/App Check and provider-billing evidence.
- A successful validation creates an inactive Paystack subaccount in
  `pending_review`; a second, explicit `spazaAdmin` review is required before
  the destination or collection capabilities can be enabled.

## Reconciliation evidence

The daily job checks the immutable intent and fee snapshot against provider
amount/reference, applied provider events, settlement amounts, refund totals,
the business projection, inventory reservation, and supplier fulfilment. A
run with any mismatch is not a successful checkpoint.

The admin-only `reconcilePaymentsV2OnDemand` callable uses the same runner as
the daily job. It requires a unique `operationId` and audit reason and writes a
server-only `paymentOperations` receipt. Supplier status/tracking uses the
same pattern through `reconcileSupplierTrackingV2OnDemand`. Neither command
permits a Firestore-console financial edit.

Finance must separately reconcile Paystack's settlement export and bank
receipt because a local `settlements` document is an expectation, not proof
that the bank received funds.

## Botpress contracts

- Voice: send `event.payload.audioUrl` to `transcribeBotpressVoice` using the
  bot secret. Route a confident transcript through the same typed workflow;
  otherwise use the returned typed fallback. See
  `botpress-voice-contract.md`.
- Account payment: first use the existing account summary/merchant selection
  flow. POST the selected `merchantId`, bound `customerId`, exact
  `amountMinor`, customer email, selected channel and a stable idempotency key
  to `createAccountSettlementLinkV2` using the bot secret. Show only the
  hosted `authorizationUrl`; never claim payment before the verified receipt
  appears.
- Repayment plans: no automatic debit or saved-card action exists. Each due
  installment creates a fresh hosted link for the exact next amount.

## Evidence still required before production activation

- Written Paystack confirmation that South African split refunds recover both
  shares correctly before settlement, or controlled full and partial live
  split-refund receipts with zero unexplained variance.
- Finance approval of the processor tariffs, VAT, 1.5%/R0.50 collection fee,
  supplier margin safety and real unit economics.
- Privacy/data-safety approval for payment and transient transcription data.
- Independent payment/security architecture review.
- Paystack test-mode evidence and explicitly approved low-value live
  transactions through Delta's Paystack account on Android and iOS.
- An explicitly approved low-value live CJ purchase proving create, actual
  charge verification, balance payment, tracking and delivery reconciliation.
- Exact signed-artifact evidence for campaign credits, owned-stock orders and
  full/partial account payments, including every applicable disaster, refund,
  settlement and rollback scenario.
- Support, dispute and provider-outage rehearsal with named on-call owners.
- Named Product, Finance, Engineering/Security, Privacy, Operations/Support
  and QA sign-off against the exact signed artifacts and 100% reconciliation.

Any unexplained cent, duplicate movement, unverified destination, unsupported
refund claim, P0/P1 trust defect or failed kill switch stops progression.
