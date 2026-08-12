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
4. The merchant is `enabled` and has that same purpose in
   `merchantPaymentProfiles/{merchantId}.capabilities`.

All controls default to disabled. `setGlobalPaymentConfigurationV2` and
`setMerchantPaymentState` require the `spazaAdmin` claim, an audit reason and
write immutable audit records. Collection capabilities cannot be enabled for
a merchant until their resolved Paystack subaccount has been approved.

The emergency response is to set `emergencySuspended=true`, preserve the
affected records, run reconciliation, and identify every charged intent that
still needs fulfilment or a refund. Do not delete or rewrite provider events.

## Capability activation

Keep all capabilities dark while the backwards-compatible production backend
and exact `4.8.0+88` signed artifacts are verified. After the full development,
emulator, TestFlight/Play Internal Testing and approved low-value live evidence
pack passes, globally activate these three capabilities together:

1. `campaign_credit`
2. `merchant_order`
3. `account_settlement`

There is no controlled customer pilot and no seven-day waiting period. Review
reconciliation and support evidence continuously after activation, and use the
global kill switch immediately if any stop condition appears.

`supplier_order` remains separately dark until CJ fulfilment and automatic
refund evidence passes and split-refund recovery is proved in writing or by
controlled full and partial live tests that reconcile both Delta and merchant
shares.

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
| CJ create/pay validation fails | `refund_pending` | Operations | Paystack refund is automatically requested and remains visible until provider confirmation. |
| Refund is pending/processing | `refund_pending` | Operations/support | Explain that the provider is processing it; never say refunded. |
| Refund needs attention/fails | `provider_failed` or provider status | Operations | Resolve with Paystack and re-run reconciliation. Do not locally complete it. |
| Reconciliation mismatch | run `mismatch` | Engineering + finance | Globally suspend payments and account for every cent before resuming. |
| Settlement destination changes | merchant `pending_review` | Admin + finance | Resolve the account again and approve the new fingerprint before re-enabling collections. |

## Reconciliation evidence

The daily job checks the immutable intent and fee snapshot against provider
amount/reference, applied provider events, settlement amounts, refund totals,
the business projection, inventory reservation, and supplier fulfilment. A
run with any mismatch is not a successful checkpoint.

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
  shares correctly before settlement.
- Finance approval of the processor tariffs, VAT, 1.5%/R0.50 collection fee,
  supplier margin safety and real unit economics.
- Privacy/data-safety approval for payment and transient transcription data.
- Independent payment/security architecture review.
- Paystack test-mode evidence and explicitly approved low-value live
  transactions through Delta's Paystack account on Android and iOS.
- Exact signed-artifact evidence for campaign credits, owned-stock orders and
  full/partial account payments, including every applicable disaster, refund,
  settlement and rollback scenario.
- Support, dispute and provider-outage rehearsal with named on-call owners.

Any unexplained cent, duplicate movement, unverified destination, unsupported
refund claim, P0/P1 trust defect or failed kill switch stops progression.
