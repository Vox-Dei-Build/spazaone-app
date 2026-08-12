# Failure-first payment truth catalogue

Baseline: `4.7.1+87` (`28290792c455ceaabfc2eff4b7776eccda451b19`)

This is the I0 source-of-truth inventory for the Paystack and commerce
programme. It documents the released behavior before V2 payment code changes
it. V2 must coexist with these paths until the released clients that depend on
them are outside the supported-version window.

## Accountability

| Concern | Accountable function | Verification evidence |
| --- | --- | --- |
| Journey, pricing and affordances | Vox Dei product owner | Approved journey maps and copy |
| State machines, security and reconciliation | Engineering | Rules, unit, integration and failure-injection results |
| Fees, VAT and settlements | Finance | Signed fee worksheet and reconciliation report |
| CJ funding, exceptions and refunds | Operations | Funding/refund runbook and provider receipts |
| Customer and merchant communication | Support | Approved templates and escalation paths |
| Release recommendation | QA | Checkpoint evidence pack with no open stop condition |

## Existing financial truths

| Source | Current writer | Current meaning | Failure exposure | V2 treatment |
| --- | --- | --- | --- | --- |
| `users/{storeId}/sales/{saleId}` | Checkout Functions and legacy clients | Cash, Online and Pay Later sale/order record | Rand doubles; status and payment proof share one mutable document | Keep as the released business record. V2 projects verified payment status into it, but never treats it as provider proof. |
| `users/{storeId}/customers/{customerId}/transactions/{id}` | Legacy clients and Functions | Credit and manual Payment ledger entries | Store members can create entries directly | Preserve manual entries with `source=manual`. V2 online entries use `source=paystack_v2` and an immutable V2 intent/event binding. |
| `campaignWalletBalances/{walletStoreId}` | Cloud Functions | Canonical campaign credits | Already server-owned, but legacy Paystack credits the provider net rather than a separately quoted credit value | Reuse only through the canonical campaign-credit mutation helpers and V2 idempotency. |
| `users/{storeId}/wallet/current` | Legacy clients and Functions | Mixed campaign, sales, cash-advance and payout balances | Store members can write beneath the legacy user tree; sales balance is not provider settlement truth | V2 never reads or increments `salesVirtualBalance`. Retain only for released-client compatibility. |
| `payoutRequests/{id}` | Legacy clients | Request to withdraw the legacy sales balance | Client-writable and no provider executor exists | Do not execute from V2. Replace with Paystack settlement records after merchant onboarding. |
| `paymentReferences/{id}` | Legacy clients | Loose payment-reference record | Client-writable, so it cannot prove a provider payment | Never trust in V2. Provider events and intent bindings are server-only. |
| `commerceOrders/{id}` | Commerce Functions | Supplier-order source of truth | Paystack success marks paid but does not currently create or fund CJ fulfilment | Retain as business truth; bind it to server-only V2 intent and supplier-fulfilment records. |
| Commerce `refund` fields | Commerce Functions/admin action | Operational record that a refund was requested or recorded | `mark_refunded` does not itself prove Paystack returned funds | V2 remains `refund_pending` until a verified provider refund event confirms completion. |
| `users/{storeId}/bankingDetails/{id}` | Legacy clients | Raw bank account details | Unverified and client-managed | V2 creates a verified, masked `merchantPaymentProfiles` record. Never use this collection as a settlement instruction. |
| Paystack processed-reference documents | Paystack-specific Functions | Per-path deduplication marker | Separate sale, top-up and commerce paths use different schemas | V2 uses one event inbox and deterministic intent idempotency across all purposes. |

## Existing journeys that must remain intact

1. **Cash sale** — merchant records a sale; no Paystack or platform collection
   fee is introduced.
2. **Manual transfer** — merchant/customer arrange an EFT externally and the
   merchant records receipt manually.
3. **Pay Later** — merchant approves or rejects the existing order and records
   repayments through the existing customer ledger.
4. **Manual customer payment** — `Add Payment` records a `Payment` transaction
   and optionally sends a paid message after explicit cost confirmation.
5. **Owned-stock order** — `checkoutCart` creates a sale and locks the cart;
   stock is currently finalized later in the order lifecycle.
6. **Supplier order** — `commerceOrders` is separate from Sales, live CJ price
   is snapshotted, and the merchant currently places/funds the CJ order
   manually.
7. **Campaign-credit top-up** — UI and Paystack code exist but production is
   deliberately disabled by feature flags.

## V2 boundary

- V2 amounts are integer minor units only.
- Historical Rand doubles are normalized at a read boundary; there is no bulk
  historical rewrite in this programme.
- V2 collections are Admin SDK only. Clients reach them through authenticated,
  App-Check-protected functions and receive purpose-limited projections.
- A manual business record is not payment-provider proof.
- A provider event is not sufficient on its own: it must match an existing
  intent's merchant, purpose, amount, currency and business binding.
- No V2 code reads or mutates the legacy sales wallet.

## I0 exit gate

- [x] Existing financial sources and writers catalogued.
- [x] Released journeys and compatibility constraints documented.
- [x] V2 trust boundary documented.
- [ ] Product owner approval.
- [ ] Engineering/security approval.
- [ ] Finance approval of fee and VAT rules.
- [ ] Operations approval of CJ/refund ownership.
- [ ] Support approval of lifecycle messages.
- [ ] QA evidence-pack owner assigned.

