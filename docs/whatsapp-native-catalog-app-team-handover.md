# Handover — merchant WhatsApp catalogue visibility and sync UX

Status: V2 status and invoice/PDF app support implemented locally; deployment
and release remain separately governed

Release state: no app release, backend deployment, catalogue sync, or production
write was performed as part of this handover

Implementation update (3 September 2026): the app now consumes the sanitized,
App Check-protected `getWhatsAppCatalogSyncStatusV2` callable with tenant-bound
pagination, one-time catalogue-drift recovery, store/session epoch isolation,
and a user/store Hive cache. Products use server-derived catalogue states (or
the explicit `WhatsApp listing requested` fallback) and shops outside backend
rollout see `Catalogue rollout is not yet enabled for this shop.` The same
change adds private JPEG/PNG/PDF sales-attachment viewing and selection while
retaining the existing three-file and 5 MB limits. V1 is unchanged. No backend,
Storage rule, Remote Config, or app release has been deployed from this work.

## Outcome to build

Give every merchant a truthful, tenant-scoped view of what customers can browse
in the Spaza One WhatsApp catalogue. A merchant should be able to answer:

- How many of my products are live on WhatsApp?
- Is my shop ready for the five-product minimum and ten-product view?
- Which product needs attention, why, and what can I safely do next?
- Is a recent product edit still syncing, accepted, stale, or rejected?

This is merchant-facing observability for the catalogue pipeline. It must not
change catalogue eligibility, trigger customer messages, expose provider
identifiers, or become a second source of product truth.

The rollout mechanics, reconciliation gates, and rollback order remain defined
in [Native WhatsApp catalogue production controls](whatsapp-native-catalog-production.md).

## Source of truth and current behavior

The source of truth is each merchant's own product collection, not a manually
maintained Meta feed or another merchant's inventory. The provider may use one
managed catalogue container, but ownership, selection, and cart revalidation
remain merchant-scoped; the app must never model that container as shared
merchant inventory. A product is projected from the authenticated merchant's
saved product only when the backend confirms all applicable requirements,
including:

- it is explicitly listed for WhatsApp and is not internal, hidden, paused,
  draft, archived, or deleted;
- it has a name, positive customer selling price, and public HTTPS picture;
- the merchant/product has a valid ordering link;
- it does not require unresolved catalogue policy review; and
- any applicable supplier-product access rule permits it.

The backend derives an opaque retailer identity, revision, customer price,
availability, picture, link, and merchant ownership. Product changes enter a
server-owned outbox and are synchronized to Meta in the background. A product
is live only when the current eligible revision has an active mapping and Meta
has accepted that same revision. Counts alone are not proof of readiness.

Before the implementation update above, the app provided the
`List in WhatsApp Store` control, required an image before saving a listed
product, and showed a local preview, but labelled merchant intent as `Online`.
The V2 client now preserves merchant intent separately from server-confirmed
live customer visibility.

The status callable and catalogue projection in this worktree are local
implementation, not evidence that production has been deployed or reconciled.

## Proposed merchant experience

### Catalogue readiness summary

Add a WhatsApp catalogue panel to Products (and optionally the merchant setup
checklist) showing fresh server-derived counts:

- `Live`: current revision accepted and customer-visible.
- `Syncing`: pending, processing, submitted, or safely retrying.
- `Needs attention`: locally ineligible, rejected, or otherwise blocked.
- `Ready for browsing`: yes at five or more live products.
- `Ten-product view`: yes at ten or more live products.

Use plain guidance alongside the counts:

- 0–4 live: add or fix products to reach five.
- 5–9 live: customers can browse those live products; add valid pictured
  products to reach ten.
- 10+ live: the first native view can show ten; additional products remain
  discoverable through the bot's explicit navigation.

Never calculate readiness from `whatsappListed` in Dart. Render the authenticated
backend result and show its last-checked time. A stale/offline result must be
labelled `Last checked ...`, not presented as current.

### Product-level status

Replace the ambiguous `Online` label with a server-derived status chip and one
safe next action:

| Status               | Merchant copy                                        | Safe action                                    |
| -------------------- | ---------------------------------------------------- | ---------------------------------------------- |
| Not listed/internal  | Not in WhatsApp catalogue                            | Turn listing on when ready                     |
| Invalid product data | Needs a valid name, price, picture, or ordering link | Open the relevant edit field                   |
| Syncing              | Updating WhatsApp catalogue                          | Wait; refresh status later                     |
| Live                 | Live in WhatsApp catalogue                           | None                                           |
| Stale                | Latest change is still syncing                       | Wait; do not claim the old details are current |
| Review/rejected      | Needs review before it can appear                    | Show sanitized guidance or contact support     |
| Removal syncing      | Being removed from WhatsApp                          | Wait; do not claim removal is complete         |
| Unknown/inconsistent | Status needs support review                          | Show a non-secret support reference            |

The app should map stable backend reason codes to localized copy. Do not show
raw Meta responses, catalogue IDs, sender/phone-number IDs, opaque retailer IDs,
access tokens, outbox document paths, or internal product/merchant identifiers.
Policy failures should use neutral review copy rather than exposing raw provider
diagnostics.

### Retry and support controls

- A normal pending or submitted state gets refresh only, not a retry button.
- Offer `Try sync again` only when a new authenticated backend operation says
  retry is safe and idempotent for the current revision.
- Ambiguous dispatch, provider acceptance uncertainty, stale ownership, and
  inconsistent mappings go to support review; never blindly resubmit them.
- Generate a short, non-secret support reference server-side. Copying it must
  not include product names, prices, image URLs, phone numbers, Meta IDs, or
  credentials.
- Editing the product remains the merchant's primary correction path. The app
  must explain that a price, picture, visibility, or listing change starts a
  background update and is not necessarily instant.

### Merchant education

Add a short first-use explanation near the listing control:

> Products you list here are prepared for your shop's WhatsApp catalogue in the
> background. Valid pictured products normally appear after synchronization.
> Five live products make the catalogue ready; ten fill the first product view.

Also explain that:

- each merchant sees and manages only their own uploaded products;
- turning listing off requests removal but does not delete the stock product;
- customers see only the latest revision that the backend has verified as
  accepted; and
- support may be needed when Meta requires review.

Do not teach merchants about shared provider catalogue structure or expose
provider configuration. That is an implementation detail, not an app concept.

## Backend contract needed by the app

Keep eligibility and provider state evaluation on the server. The existing V1
callable provides aggregate active/pending/blocked counts and five/ten readiness
booleans. Before implementing the full screen, stabilize a tenant-scoped status
contract that additionally returns:

- a server timestamp and status freshness/expiry;
- aggregate `eligible`, `live`, `syncing`, `needsAttention`, and removal counts;
- per-product stable status and safe reason codes for products owned by the
  authenticated merchant;
- whether refresh or an idempotent retry is currently permitted; and
- a non-secret support reference for review-only states.

The callable must require Firebase Authentication, App Check, and the existing
store-access check. It must paginate product rows, bound response size, and
return no provider identifiers or credentials. Prefer a versioned contract over
silently widening V1 in ways that could break older clients.

The app must not read `whatsappCatalogMappings`, `whatsappCatalogOutbox`, or
reconciliation collections directly. Those are backend implementation and
audit records.

## Acceptance criteria

- A merchant can see accurate aggregate readiness and per-product status for
  their own store only; cross-merchant reads are rejected and tested.
- `whatsappListed=true` is never rendered as `Live` without current-revision
  Meta acceptance from the server.
- The UI correctly represents 0, 1, 4, 5, 9, 10, 11, and 22 eligible/live
  products, including the five-product readiness and ten-product-view boundary.
- Price, picture, listing, visibility, deletion, and ordering-link changes move
  through truthful syncing/stale/removal states and settle to live or a safe
  reason without misleading flicker.
- Rejected, malformed, unavailable, timeout, and ambiguous states never expose
  raw provider data and never trigger a blind retry.
- Offline, expired, loading, empty, and partial-page states have explicit UI;
  cached status is visibly timestamped.
- Product editing, stock/sales behavior, and the existing listing toggle remain
  intact. The status surface does not send a customer message or mutate a cart.
- Widget/unit tests cover status/reason mapping and thresholds; emulator tests
  cover authentication, App Check, tenant isolation, pagination, stale revision,
  provider rejection, and retry authorization.
- Accessibility covers screen-reader labels, color-independent status meaning,
  large text, and a clear focus order.

## Telemetry and privacy

Instrument only operational aggregates needed to improve the experience:

- screen viewed and status refresh succeeded/failed;
- readiness bucket (`0–4`, `5–9`, `10+`), not exact product identities;
- normalized safe reason category and chosen correction action;
- response latency, cache age bucket, and retry/support action outcome.

Do not emit merchant/customer phone numbers, product names/descriptions, prices,
image or ordering URLs, retailer IDs, Meta catalogue/WABA/sender IDs, document
paths, raw provider errors, access tokens, or secret names/values. Use the
project's approved pseudonymous tenant/session correlation and retention rules;
support lookup should require authorized server-side resolution. Confirm event
names and payloads in privacy/data-safety review before release.

## Rollout dependencies and handoff sequence

1. Complete the governed backend/Botpress rollout and strict full-catalogue
   reconciliation defined in the production controls document. App status must
   not be inferred from a partially deployed or unreconciled backend.
2. Freeze and contract-test the versioned aggregate/per-product status API,
   safe reason vocabulary, pagination, freshness rules, and retry semantics.
3. Implement the app surface behind a separately controlled feature flag. Keep
   it read-only until a guarded retry endpoint exists and has independent tests.
4. Verify against synthetic multi-merchant data, then a controlled merchant
   account, including stale, rejected, removal, and offline cases.
5. Complete app lint/tests/build, privacy review, accessibility QA, release
   notes, merchant help copy, and support runbook.
6. Obtain separate app release authorization and follow the normal staged app
   release process. Enabling native WhatsApp delivery does not itself publish
   this app UX.

Rollback of the future app surface is its feature flag. Backend delivery and
sync rollback remain separate governed actions in the production controls
document. Hiding this app panel must never delete products, mappings, catalogue
items, carts, orders, or customer data.
