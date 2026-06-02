# PostHog Dashboards -- Pasella v1

Source-of-truth spec for the first set of PostHog (EU Cloud) dashboards.
Each insight here corresponds to one saved query in the PostHog UI; each
dashboard groups the insights a single audience needs.

**Audience**: founders / exec, weekly read.
**Default range**: `Last 30 days` for trends, `Last 7 days` for failure tiles.
**Default aggregation**: weekly buckets on trends, daily on failure tiles.
**Time zone**: `Africa/Johannesburg` (set per dashboard, override Posthog default).

> Event names and property names below come straight from
> `lib/services/analytics_event.dart`. If the code changes, update this file
> first, then the dashboards.

## Conventions

- **Event name**: snake_case as fired by the app.
- **Property**: snake_case property on the event.
- **Math**: PostHog "math" selector (`Total count`, `Unique users`,
  `Unique groups`, `Average`, etc.).
- **Breakdown**: PostHog breakdown property; `none` if there is none.
- **Filter**: extra `WHERE` constraints on the event.
- **Chart**: PostHog visualisation (`Number`, `Line`, `Bar`, `Funnel`,
  `Stickiness`, `Retention`, `Pie`).
- **Pinned to**: which dashboards include this insight.

User identity: PostHog `distinct_id` is the merchant `uid` set by
`TelemetryService.identify()`. "Unique users" therefore means unique
merchants. There is no end-customer-level analytics by design (POPIA).

---

## Dashboard 1 -- Activation funnel

**Goal**: how many new merchants reach their first sale and first payout.
**Owner**: founder.
**Refresh**: weekly Monday read.

### 1.1 Sign-ups per week
- Event: `signup_completed`
- Math: `Total count`
- Breakdown: `method` (`anonymous` / `phone` / `email`)
- Filter: none
- Chart: `Bar` (stacked by method), weekly bucket
- Pinned to: Dashboard 1

### 1.2 New-merchant activation funnel
- Steps (ordered, per `distinct_id`):
  1. `signup_completed`
  2. `sale_completed` (first occurrence)
  3. `payout_requested` (first occurrence)
- Conversion window: 30 days
- Math: `Unique users`
- Breakdown: `method` from step 1 (carry-forward via "Breakdown by event property of first step")
- Chart: `Funnel`
- Pinned to: Dashboard 1

> Why this funnel: signup -> first sale proves the ledger value prop;
> first sale -> first payout proves the wallet value prop. Drop-off
> between 1 and 2 is an onboarding problem; drop-off between 2 and 3 is a
> wallet/banking problem.

### 1.3 Time-to-first-sale (median)
- Event: `sale_completed`
- Math: `Median time since first event` -> first event = `signup_completed`
- Filter: limit to first occurrence per user
- Breakdown: `method` from `signup_completed`
- Chart: `Number` with weekly trend Sparkline
- Pinned to: Dashboard 1

### 1.4 W1 retention by signup cohort
- Cohort event: `signup_completed`
- Returning event: `sale_completed`
- Period: weekly, 8 weeks
- Chart: `Retention`
- Pinned to: Dashboard 1

---

## Dashboard 2 -- Sales health

**Goal**: how much value is flowing through the ledger and where it sticks.
**Owner**: founder + product.
**Refresh**: weekly.

### 2.1 Sales started -> completed conversion
- Steps:
  1. `sale_started`
  2. `sale_completed`
- Conversion window: 1 hour (a sale that does not complete in an hour
  is abandoned, not slow).
- Math: `Total count` (count both starts and completions, not unique users
  -- a merchant can complete many sales per day).
- Breakdown: `entry_point` from step 1
- Chart: `Funnel`
- Pinned to: Dashboard 2

### 2.2 Completed sales by amount bucket
- Event: `sale_completed`
- Math: `Total count`
- Breakdown: `amount_bucket` (`0-50` ... `20000+`)
- Filter: none
- Chart: `Bar` (stacked), weekly bucket
- Pinned to: Dashboard 2

### 2.3 Cash vs credit mix
- Event: `sale_completed`
- Math: `Total count`
- Breakdown: `is_credit` (true/false)
- Chart: `Line` (two series), weekly bucket
- Pinned to: Dashboard 2

### 2.4 Returning vs new customer mix (per merchant)
- Event: `sale_completed`
- Math: `Total count`
- Breakdown: `customer_is_existing` (true/false)
- Chart: `Pie`
- Pinned to: Dashboard 2

### 2.5 Sale abandonment hot spots
- Event: `sale_abandoned`
- Math: `Total count`
- Breakdown: `last_field`
- Chart: `Bar` (horizontal), `Last 30 days`
- Pinned to: Dashboard 2

> Drives form-UX prioritisation. The field with the highest abandonment is
> the next form field to redesign.

---

## Dashboard 3 -- BNPL adoption

**Goal**: is BNPL being offered, accepted, and at what sizes.
**Owner**: founder + risk.
**Refresh**: weekly.

### 3.1 BNPL offer funnel
- Steps:
  1. `bnpl_offer_shown`
  2. `bnpl_offer_accepted`
- Conversion window: 30 minutes
- Math: `Total count`
- Breakdown: `amount_bucket` from step 1
- Chart: `Funnel`
- Pinned to: Dashboard 3

### 3.2 Acceptance rate trend
- Calculated insight: `bnpl_offer_accepted / bnpl_offer_shown`
- Use PostHog "Formula" insight: `A / B` where
  - A = `bnpl_offer_accepted`, math `Total count`
  - B = `bnpl_offer_shown`, math `Total count`
- Chart: `Line` (single series, % format), weekly bucket
- Pinned to: Dashboard 3

### 3.3 Rejection reasons
- Event: `bnpl_offer_rejected`
- Math: `Total count`
- Breakdown: `reason`
- Chart: `Bar` (horizontal)
- Pinned to: Dashboard 3

### 3.4 Term-length preference
- Event: `bnpl_offer_accepted`
- Math: `Total count`
- Breakdown: `term_days`
- Chart: `Pie`
- Pinned to: Dashboard 3

---

## Dashboard 4 -- Wallet reliability

**Goal**: are top-ups and payouts working; if not, where is it failing.
**Owner**: founder + ops.
**Refresh**: weekly review, daily for failures.

### 4.1 Top-up funnel
- Steps:
  1. `wallet_topup_started`
  2. `wallet_topup_completed`
- Conversion window: 15 minutes
- Math: `Total count`
- Breakdown: `method` from step 1
- Chart: `Funnel`
- Pinned to: Dashboard 4

### 4.2 Top-up failures by code (last 7 days)
- Event: `wallet_topup_failed`
- Math: `Total count`
- Breakdown: `failure_code` (`init_null` / `cancelled` / `webview_failed`
  / `exception`)
- Filter: `Last 7 days`
- Chart: `Bar` (horizontal), daily bucket
- Pinned to: Dashboard 4

> `cancelled` is user behaviour, not a defect; investigate when its share
> drops or when `webview_failed` / `exception` rise.

### 4.3 Top-up volume by amount bucket
- Event: `wallet_topup_completed`
- Math: `Total count`
- Breakdown: `amount_bucket`
- Chart: `Bar` (stacked), weekly bucket
- Pinned to: Dashboard 4

### 4.4 Payouts requested
- Event: `payout_requested`
- Math: `Total count`
- Breakdown: `amount_bucket`
- Chart: `Bar` (stacked), weekly bucket
- Pinned to: Dashboard 4

### 4.5 Client-side payout submission failures
- Event: `payout_failed`
- Math: `Total count`
- Breakdown: `failure_code`
- Filter: `Last 7 days`
- Chart: `Number` with weekly Sparkline
- Pinned to: Dashboard 4

> Reminder: completion / settlement of payouts is **not** captured
> client-side by design. If end-to-end payout funnels are needed, add a
> server-side capture call from the payout webhook.

---

## Dashboard 5 -- Comms throughput

**Goal**: are merchants using SMS / WhatsApp reminders, and is the
delivery infrastructure healthy.
**Owner**: founder + ops.
**Refresh**: weekly.

### 5.1 Outbound messages by channel
- Event: `comms_sent`
- Math: `Total count`
- Breakdown: `channel` (`sms` / `whatsapp`)
- Chart: `Bar` (stacked), weekly bucket
- Pinned to: Dashboard 5

### 5.2 Top templates
- Event: `comms_sent`
- Math: `Total count`
- Breakdown: `template_id`
- Filter: `Last 30 days`
- Chart: `Bar` (horizontal, top 10)
- Pinned to: Dashboard 5

### 5.3 Active senders (unique merchants sending comms)
- Event: `comms_sent`
- Math: `Unique users`
- Breakdown: `channel`
- Chart: `Line`, weekly bucket
- Pinned to: Dashboard 5

### 5.4 Delivery infrastructure health
- This is **not** a PostHog insight. Link tile to Firebase Crashlytics
  filtered by `reason` containing `twilio` or `whatsapp`. PostHog cannot
  read Crashlytics; a markdown tile with the Crashlytics URL is fine.
- Pinned to: Dashboard 5 (as a `Text` tile / markdown insight)

---

---

## Firebase Analytics mirror (Google Ads campaign attribution)

PostHog is the primary analytics sink for the full taxonomy above. A small
allow-list of activation events is **also** forwarded to Firebase Analytics
by `TelemetryService._mirrorToFirebase` so that Google Ads (and GA4
audiences / retention reports) can attribute campaigns to real merchant
activation, not just installs.

| App event           | FA event name      | Notes                                                                 |
| ------------------- | ------------------ | --------------------------------------------------------------------- |
| `SignupCompleted`   | `sign_up`          | GA4 standard event. Params: `method`, optional `business_type`, etc. |
| `SigninCompleted`   | `login`            | GA4 standard event. Drives retention cohorts in GA4.                  |
| `CustomerCreated`   | `generate_lead`    | GA4 standard event. Onboarding hop between signup and first sale. Params: `has_image`. No `value`/`currency` -- contact has no revenue yet. |
| `SaleCompleted`     | `purchase`         | GA4 standard. Params: `currency='ZAR'`, `value`=bucket midpoint, `amount_bucket`, `is_credit`, `customer_is_existing`. |
| `PayoutRequested`   | `payout_requested` | Custom. Params: `amount_bucket`, `value`=bucket midpoint, `currency='ZAR'`. |

### Rules

- The `value` parameter is the **midpoint** of `amountBucketZAR`, never the
  raw transaction amount. The mapping lives in
  `TelemetryService._bucketMidpointZAR` and must be updated in lock-step
  with `amountBucketZAR` in `lib/services/analytics_event.dart`.
- `setUserId` is the merchant's Firebase UID, set in
  `TelemetryService.identify` and cleared in `TelemetryService.reset`. This
  is what stitches FA sessions into per-merchant retention cohorts.
- Every other event in the taxonomy stays PostHog-only. Adding a new FA
  mirror is a deliberate edit to `_mirrorToFirebase`, never a default. This
  keeps the GA4 / Google Ads event surface curated and predictable for
  conversion configuration.
- The FA mirror respects the same `analytics` consent flag as PostHog
  (`TelemetryService._enabled`). It does **not** alter Firebase's
  auto-collected events (`first_open`, `session_start`, `app_remove`, etc.),
  which are governed by the SDK's native collection switch — see the
  follow-up below.

### Google Ads / GA4 setup

1. In GA4, mark `sign_up`, `generate_lead`, `purchase`, and
   `payout_requested` as conversions (Admin -> Events -> toggle "Mark as
   conversion").
2. In Google Ads, import those conversions from the linked GA4 property and
   set the optimization target on the campaign accordingly (typically
   `purchase` for ROAS, `sign_up` or `generate_lead` for early funnel scale).
3. Verify in GA4 DebugView using a debug install: signup, add a customer,
   complete a sale, request a payout, confirm all four events arrive with
   the expected params.

### Follow-up (not in this release)

Firebase Analytics auto-collection currently runs irrespective of the
consent modal. Gating auto-collection on `ConsentState.analytics` (via
`FirebaseAnalytics.setAnalyticsCollectionEnabled` plus the
`FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED` / `firebase_analytics_collection_enabled`
native flags) is a separate slice. Do **not** flip this during a live
campaign -- it will reset Google Ads `first_open` attribution.

---

## Cross-cutting -- consent telemetry (do **not** pin to a public dashboard)

Useful for debugging consent flows but not for stakeholder review. Keep
in a private "Engineering" dashboard or saved-insights folder.

- Event: `consent_decided`
- Math: `Total count`
- Breakdown: `surface` (`first_run_modal` / `settings_privacy`),
  secondary breakdown `analytics`, `replay`, `crash`
- Chart: `Bar`

This is the only place where consent rates are visible. Do not surface
percentages to founders unless you can also show denominators
(installs); otherwise the number is misleading.

---

## Provisioning steps

1. In PostHog EU project, create five empty dashboards using the names
   above (`Activation`, `Sales health`, `BNPL adoption`,
   `Wallet reliability`, `Comms throughput`).
2. For each insight in this doc, click **+ New insight** -> pick the chart
   type -> configure event/math/breakdown/filter exactly as listed -> save
   with the insight's section heading as its name (e.g. `1.1 Sign-ups
   per week`).
3. Pin each insight to its target dashboard.
4. Set each dashboard's default date range to `Last 30 days` and time
   zone to `Africa/Johannesburg`.
5. Sanity-check by firing a few events from a debug install and
   confirming counts move.

## Maintenance rules

- New event added to `analytics_event.dart` -> update this doc in the same
  PR before adding insights in PostHog.
- Property renamed -> grep this doc for the old name and patch every
  reference; PostHog insights using the old name will silently return
  zeroes.
- Bucket boundaries in `amountBucketZAR` changed -> warn stakeholders that
  historical bars are not comparable to new bars; consider archiving the
  pre-change dashboard snapshot.
- Quarterly: prune any insight that nobody opened in 90 days (PostHog
  shows last-viewed timestamp on each insight). Dashboards rot fast; one
  unread chart trains people to ignore the rest.
