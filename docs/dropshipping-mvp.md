# Spaza One dropshipping MVP

## Architecture and source-of-truth decisions

The dropshipping flow is separate from manual Sales records and the legacy
WhatsApp ecommerce sale documents. There is no administrator-managed product
catalog in the normal seller flow.

- CJdropshipping is accessed only by Cloud Functions. `CJ_API_KEY` stays in
  Cloud Secret Manager and is exchanged server-side for CJ access tokens.
- Sellers browse a server-owned materialised catalogue in
  `supplierCatalogProducts`. Search, category browsing, product opening and
  listing creation read this cache and make **zero** CJ requests. The app shows
  one South Africa delivery-ready option per product; unverified alternatives
  are not offered. Listing creation accepts only that cached product/variant
  identifier and the seller's markup, then copies the server-owned cost
  snapshot into the listing.
- `supplierCatalogJobs` is an idempotent background discovery/refresh queue.
  `syncCjSupplierCatalog` processes demand, stale refreshes and rotating broad
  categories without administrator curation. It rotates through up to fifty CJ
  result pages per query, refreshes positive products after 72 hours and
  negative results after 24 hours. New seller searches can request background
  discovery, limited per store so one account cannot exhaust the supplier
  allowance.
- The worker and the order quote path share a Firestore transaction gate in
  `supplierIntegrationState`, enforcing the CJ account limit across all Cloud
  Functions instances. Worker retries use leases and exponential backoff. A
  single bounded job runs every five minutes and a 36,000-point UTC daily
  catalogue budget leaves 14,000 of CJ's current 50,000 base points for real
  buyer orders. A broad category receives a fair discovery slot every two
  hours, while the app reads 24 cached products at a time and appends more via
  a cursor. Catalogue requests therefore scale independently of CJ's request
  limit.
- Catalogue search uses prefix tokens, categories and cursor pagination.
  Multi-word search deliberately uses the longest word as the primary broad
  match, allowing sellers to discover nearby results without a third-party
  search service. Released apps retain bounded page-number compatibility.
- CJ returns product and freight prices in USD. The backend obtains a current
  USD/ZAR reference rate, applies the configured FX reserve (3% by default),
  and performs integer-minor-unit conversions server-side. It accepts both
  documented Frankfurter response formats, caches a valid rate and fails closed
  when neither source has a recent rate.
- Transient supplier, network and rate-limit failures never become cached
  “not deliverable” results. Only explicit stock/product/no-route failures can
  deactivate a catalogue product.
- `users/{storeId}/products/{productId}` remains the compatible seller product
  projection. CJ listings add `supplierId`, `sourceProductId`,
  `sourceVariantId`, `supplierSku`, product/delivery cost estimates,
  `markupMinor`, `sellPriceMinor`, `fulfilmentMode`, `isDropshipListing`,
  `commerceListingId`, `checkoutUrl`, and `shippingNotes`. Existing product,
  stock and reporting code can continue reading `cost` and `sellingPrice`.
  Dropship projections omit an owned-stock quantity, so they do not trigger
  low-stock alerts or inflate inventory-value reports.
- `commerceListings/{listingId}` is the server-owned ordering projection. It
  stores the seller's fixed markup and CJ identifiers. A buyer cannot alter it
  by editing the compatible seller product document.
- `commerceOrders/{orderId}` is the dropshipping order source of truth. It
  contains buyer and delivery data plus immutable snapshots of CJ product cost,
  freight, origin, delivery service, USD amounts, FX rate/reserve, landed cost,
  selling price, payment fee, margin and amount due. Manual orders snapshot a
  zero payment fee.
- `commerceCheckoutAttempts/{hash}` deduplicates repeated checkout submissions.
  `payments/paystackCommerce/processed/{reference}` deduplicates verified
  Paystack callbacks. Both are server-only.

The catalogue and listing price is an estimate. When the buyer supplies a South
African postal code, the server obtains one authoritative CJ stock/freight
quote, reapplies the seller's fixed markup, validates the margin, and snapshots
the order. Historical orders are never repriced.

## Compliance and payment activation gate

Digital payment is intentionally disabled until Spaza One completes provider
onboarding and compliance approval. `COMMERCE_PAYMENTS_ENABLED` defaults to
false and only the exact value `true` activates Paystack checkout.

While the gate is off:

- sellers browse the Spaza One supplier catalogue, set markup and publish the
  result as a normal seller product;
- supplier-fulfilled products use the same Promote action and existing
  WhatsApp catalogue/storefront flow as seller-owned products; no special
  product checkout link is exposed;
- the buyer opens the seller's normal WhatsApp storefront and chooses the
  listing from the same catalogue as the seller's other products;
- the bot collects the buyer's delivery address and payment preference without
  sending them to a webpage;
- the authenticated bot backend live-quotes CJ delivery and creates the order
  request without taking an online payment;
- Spaza One snapshots the live CJ landed cost, selling price, zero payment fee
  and seller margin in an isolated `commerceOrder`;
- the seller arranges payment using their existing manual process and confirms
  it under Customer → Orders; and
- only then can the seller place the CJ order and continue fulfilment.

Paystack code remains dormant and no Paystack API is called while the flag is
false. The gate is a release control, not a substitute for Paystack's own
compliance or account activation checks.

The existing Sales → Online implementation is separately gated by Remote
Config key `FEATURE_ONLINE_SALES_ENABLED`, which defaults to false. Until an
approved provider is live, that surface explains that automatic online payment
and sales reporting are coming soon; Cash sales continue unchanged.

## Security boundary

- Catalogue search, cached product detail, legacy quote compatibility and
  listing creation callables require authentication and active access to the
  selected store. Catalogue/cache/queue/gate documents deny every client read
  and write, including administrators using the app client.
- Listing creation accepts only CJ product/variant identifiers and a markup.
  The backend ignores client prices and reads product, image, cost, freight and
  FX values from the verified server snapshot. A live quote is still required
  when a buyer order is created.
- The authenticated bot endpoint accepts listing, buyer and address details but
  ignores any client amount, cost, margin, seller or supplier values. It checks
  the bot secret, confirms that the listing belongs to the routed shop and
  reprices the CJ variant from the delivery postal code.
- Public browser order creation fails closed while digital payments are
  disabled. The public checkout page is retained only for a future approved
  digital-payment release and does not expose a manual order form.
- Buyer payment initialization is a dedicated commerce operation. It does not
  call wallet top-up endpoints, credit a wallet, or write a manual Sale.
- A verified Paystack event still fails closed unless the commerce-payment gate
  is enabled and the stored order was initialized as Paystack with the exact
  provider and reference. It then checks ZAR, amount, order, seller and listing
  metadata and applies `paid` in one Firestore transaction with its
  processed-reference marker. A manual WhatsApp order can never pass this
  boundary.
- Sellers and active store operators can read only their store's orders. Direct
  client writes to canonical listings, orders, checkout attempts, payment
  markers and supplier integration state are denied.
- Fulfilment actions use an explicit transition table. Skipping or reversing a
  state is rejected server-side.

## Lifecycle and responsibility

`pending_payment → paid → submitted_for_fulfilment → shipped → delivered`

For the current manual flow, `pending_payment` means the buyer sent an order
request and the seller still needs to confirm payment. This confirmation is an
audited server-side transition; it does not create a manual Sales record or
credit a wallet.

For the MVP, the seller—not a Spaza One administrator—places and pays for the
supplier order using the snapshotted SKU, variant, buyer address and chosen
logistics shown under that customer's Orders tab. After ordering, the seller
selects “Mark supplier order as placed”, then adds tracking and marks delivery.
CJdropshipping is disclosed to the seller inside operational Supplier details,
but buyer-facing pages and catalogue branding say “Spaza One supplier”.

Cancellation is allowed from `pending_payment`, `paid`, or
`submitted_for_fulfilment`. A paid cancellation sets order status `cancelled`
and payment status `refund_pending`; once the manual or provider refund is
completed, the store owner records it and the order becomes `refunded`.

## Deployment configuration

- Store the CJ key with
  `npx firebase-tools@latest --project pasella-ledger functions:secrets:set CJ_API_KEY`.
  Never place it in Flutter, Firestore, source control, or a command argument.
- Keep the existing `PASELLA_BOT_TOKEN` value aligned between the Spaza One bot
  and Functions Secret Manager. Despite the legacy identifier, it secures
  Spaza One server-to-server requests.
- `CJ_FX_BUFFER_BPS` optionally changes the default 3% FX reserve. `300` means
  300 basis points. This protects the landed-cost quote from FX/payment spread;
  every applied value is snapshotted on the order.
- `COMMERCE_CHECKOUT_BASE_URL` is not used by the current WhatsApp-only manual
  flow. Configure it only when testing the future approved digital checkout.
- Keep `COMMERCE_PAYMENTS_ENABLED=false` in production until Spaza One has
  completed compliance approval and Paystack onboarding. Manual order requests
  continue working with the flag off.
- The dedicated `verifyCommercePaystackTransaction` endpoint is deliberately
  not exported from `functions/src/index.ts` and must not appear in the scoped
  manual-MVP deploy list. Enabling an environment variable alone is not an
  approved payment launch.
- Before the manual-MVP release, verify the deployed Functions inventory also
  has no `verifyCommercePaystackTransaction`. Removing a source export does not
  delete an older deployed Function; if one exists, its explicit removal is a
  separate production action requiring the normal identity, backup and
  action-time approval gate.
- Keep `FEATURE_ONLINE_SALES_ENABLED=false` until approved automatic payment
  collection and reconciliation are ready. The previous Online reporting code
  remains intact behind this switch.
- After approval, configure the Paystack secret through Secret Manager, verify
  test-mode checkout/webhooks/refunds, explicitly re-export and scope-deploy
  `verifyCommercePaystackTransaction`, then set
  `COMMERCE_PAYMENTS_ENABLED=true` in the same controlled release.
- The existing `verifyPaystackTransaction` webhook may receive a verified
  `commerce_order` event through the account's shared webhook URL, but the
  commerce gate and stored Paystack binding are still mandatory before it can
  reach the isolated order transition. It never falls through to wallet/Sales
  mutation.
- Confirm Twilio, WhatsApp and SMS credentials are available to Functions.
  Confirm Paystack only as part of the approved activation release.
  Notification failure is recorded but does not roll back payment or
  fulfilment state.
- Roll out the coupled backend in this order: deploy the two managed
  `commerceOrders` indexes and wait until both are `READY`; publish and verify
  the updated WhatsApp bot with its commerce source guards; then deploy only
  the scoped catalogue, commerce-order/tracking and promotion-image Functions.
  Never expose commerce orders to the older bot, which could route reorder or
  cancellation through legacy Sales. Let the default categories warm and
  smoke-test a supplier-product promotion image before releasing the app. No
  migration of manual Sales, existing products, stock or wallets is required.

## Manual QA checklist

### Before payment approval

- Leave `COMMERCE_PAYMENTS_ENABLED` unset or false and confirm catalogue search,
  product opening and listing creation work without live supplier requests.
- Create a supplier listing and confirm its Products-card Promote action opens
  the same campaign flow as a seller-owned product. Confirm no supplier-only
  checkout URL or direct-product ordering link is shown.
- Open the seller's normal WhatsApp storefront, select the listing from the
  catalogue and confirm the bot asks for the South African address, payment
  preference and final confirmation entirely in WhatsApp.
- Confirm Spaza One creates one manual `commerceOrder`, snapshots zero payment
  fee and never calls Paystack or creates a manual Sales record.
- Confirm the buyer receives one in-conversation order reference and total,
  with the seller's existing manual payment instructions where available.
- Under the matching customer → Orders, confirm manual payment with a
  method/reference, then place the supplier order and record its order number.

The digital-payment checks require an approved test account and
`COMMERCE_PAYMENTS_ENABLED=true` in a non-production environment.

### Seller catalog and listing

- Sign in as a store owner and active operator; open Products → Catalogue.
- Search several categories and confirm every returned card has a recent South
  Africa delivery estimate. Confirm category chips, broad global search,
  landed-cost sorting, delivery-time sorting and cumulative cursor-based “Load
  more products” all remain usable with more than 150 cached products.
- Confirm `supplierCatalogProducts`, `supplierCatalogJobs`,
  `supplierCatalogDemand`, and `supplierIntegrationState` cannot be read or
  written by a client and no supplier credentials are exposed.
- Select a product and confirm it opens immediately with one delivery-ready
  option, its landed-cost estimate and a visible Add product footer above the
  Android system navigation. It must never show “Product needs a fresh check”.
- Confirm opening products and adding a listing do not call CJ. Simulate a
  transient CJ/rate-limit error in the worker and confirm it retries without
  marking the product unavailable. Confirm an explicit no-route result is
  hidden and scheduled for a later refresh.
- Enter a markup and confirm estimated selling price, payment fee and margin.
- With manual payments, confirm any positive markup is accepted and the payment
  fee snapshot is zero. With digital payments enabled, confirm markup below the
  estimated provider fee is rejected.
- Create the listing and confirm it appears in Products as supplier fulfilled
  without changing an existing seller product. Confirm it is available in the
  same WhatsApp catalogue and promotion picker as other listed products.
- Confirm Products has only Products, Catalogue and Report tabs; there is no
  separate seller-wide Orders destination.

### WhatsApp buyer ordering

- Promote the listing to a phone that has no Spaza One seller session, then
  enter through the seller's existing WhatsApp storefront. Confirm the buyer
  stays inside WhatsApp throughout the order request.
- Select the supplier listing from the normal catalogue and confirm the bot
  associates the order with the intended shop and listing, including when an
  old unfinished bot order existed in that chat.
- Enter a South African delivery address in the requested comma-separated
  format. Confirm the backend obtains a fresh CJ freight quote before creating
  the manual order request.
- Confirm mixed carts, quantity above one, malformed addresses and a listing
  belonging to another shop are rejected.
- Add fake price/cost/margin fields with an HTTP client; confirm they are
  ignored.
- Confirm out-of-stock, unsupported delivery and unavailable FX/provider states
  fail before the order is created with customer-safe messages.
- Open the dormant browser checkout while payments are disabled and confirm it
  shows WhatsApp-only guidance instead of a buyer-details form.
- Open that buyer in Customers → Orders. Confirm the dropship order appears in
  the same filtered list as existing customer orders and can be fulfilled from
  there. Confirm an order notification opens this customer Orders tab.

### Payment and snapshots

- For the current flow, confirm the seller—not the buyer client—can transition
  an order from awaiting manual confirmation to paid.
- Confirm the order stores `paymentMethod: manual`, a zero fee and the manual
  confirmation audit details.
- Complete a Paystack test payment and confirm the return page moves from
  pending to paid only after the verified webhook (post-approval only).
- Confirm the order stores CJ product and freight USD values, FX rate/date and
  reserve, converted landed cost, fee, selling price and margin snapshots.
- Replay the webhook and confirm one paid transition, no wallet credit and no
  manual Sales document (post-approval only).
- With `FEATURE_ONLINE_SALES_ENABLED=false`, open Sales → Online and confirm the
  Spaza One payments-partner coming-soon explanation appears with no date
  filters or misleading empty online-sales report.

### Seller fulfilment

- Confirm the paid order shows supplier SKU, variant, delivery service, buyer
  address, supplier breakdown and snapshot margin. CJ is visible only within
  the operational Supplier details section.
- Place the order in CJ using the buyer address and seller funding; select
  “Mark supplier order as placed”.
- Mark it shipped with carrier/tracking, then delivered. Confirm invalid state
  skips are rejected and buyer/seller notification attempts are recorded.

### Cancellation, access and regression

- Cancel an unpaid order and confirm no refund is required.
- Cancel a paid order and confirm it becomes `refund_pending`; record the
  manual or provider refund reference/note and confirm `refunded`.
- Confirm another seller and the public cannot read the order or canonical
  listing, while the owning store can.
- Recheck normal products, stock, manual Sales, reports, wallets, existing
  Paystack top-ups and existing WhatsApp ordering. A normal product must still
  use the existing cart/`checkoutCart`/Sales path.

## Automation follow-up

After the seller-funded MVP is validated, use CJ's order APIs to create and pay
supplier orders idempotently, persist the CJ order ID, consume tracking updates,
and reconcile supplier cancellations and disputes. Fully automatic ordering
requires an explicit funding model: a prefunded Spaza One CJ balance, seller
wallet deduction, or another approved settlement arrangement. Existing order
price/margin snapshots must remain immutable when automation is added.

Catalogue browsing no longer depends on CJ throughput, but each real buyer
order still needs a live supplier quote. Before order volume approaches the
account's physical request/point allowance, upgrade the CJ API tier or move
order quoting to an idempotent asynchronous reservation flow. A managed search
index can later add typo tolerance and relevance ranking without changing the
server-owned catalogue or order snapshot model.
