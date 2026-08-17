# Online-payment verification state map

This map separates merchant presentation from the server records used to make
the decision. `paymentAdministrationRequests` and `merchantPaymentProfiles`
remain server-only; the app receives a purpose-limited projection from
`getMerchantPaymentOverviewV2`.

| Merchant state | Source of truth | Merchant action | Operations action |
| --- | --- | --- | --- |
| Not started | Overview has loaded with no active request | Review the journey | None |
| Missing information | No saved bank account | Add the required bank details | None |
| Ready to submit | Saved bank account, no active request | Request verification | None |
| Submitting | Local request in flight, or a leased server bank check | Wait; duplicate controls stay disabled | None |
| Submitted | Request is `authorization_required` | Leave safely or refresh later | Authorize or decline the secure bank check |
| Pending review | Request/profile is `pending_review` after provider validation | Wait; status refreshes on resume | Approve, request changes, or reject |
| Approved | Request or active profile is `approved` | Use enabled online-payment capabilities | None |
| Changes required | Request is `changes_required` | Update saved bank details and resubmit | Wait for resubmission |
| Rejected | Request is `rejected` | Use updated details or contact support | Wait for a deliberate retry |
| Retryable failure | A request failed before a durable server transition | Retry the same action; deterministic IDs prevent duplicate requests | None unless repeated |
| Blocked | Authorization revoked/expired or provider outcome needs reconciliation | Refresh or contact support; do not blindly retry | Reconcile or reauthorize |

Important transitions:

1. A merchant request uses one deterministic request document per merchant.
2. Repeated taps on an unchanged active request do not reset its queue age.
3. Identity or registration details are requested only after the short bank-
   check authorization is active.
4. Provider validation creates a disabled Paystack subaccount and moves the
   request to final review; it never enables settlement authority by itself.
5. An approval activates the reviewed destination. Changes-required and
   rejection deactivate and discard only the pending destination; an existing
   approved destination remains active until a replacement is approved.
6. The merchant never receives reviewer notes, internal identifiers, provider
   codes, identity evidence, or full account numbers.
