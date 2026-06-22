# Activation nudges

Activation nudges are FCM-only reminders for merchants who stall before the
first value loop:

1. Add first customer.
2. Add first product.
3. Share a WhatsApp ordering link.
4. Link a product to a customer Pay Later credit.
5. Build toward 10 saved customers.

The scheduled function is `sendActivationNudges` in
`functions/src/notifications/activation_nudges.ts`.

## Rollout controls

The function is safe by default:

- `ACTIVATION_NUDGES_ENABLED=false`
- `ACTIVATION_NUDGES_DRY_RUN=true`
- `ACTIVATION_NUDGES_AUDIENCE=opt_in`

Recommended prerelease rollout:

1. Deploy with `ACTIVATION_NUDGES_ENABLED=true` and
   `ACTIVATION_NUDGES_DRY_RUN=true`.
2. Mark internal/beta merchants with either `activationNudgesOptIn=true` or
   `releaseChannel='beta'`.
3. Review `users/{uid}/activationNudges/*` records for candidate quality.
4. Flip `ACTIVATION_NUDGES_DRY_RUN=false` for the prerelease cohort.
5. Move to `ACTIVATION_NUDGES_AUDIENCE=all` only after open and completion
   rates are healthy.

## Frequency caps

- Max one sent nudge per merchant per 24 hours.
- Max three sent nudges per merchant per Johannesburg calendar week.
- Same nudge type cannot repeat within three days.

Dry-run records do not consume caps.

## Privacy rules

Push title/body must never include customer names, phone numbers, balances,
transaction amounts, OTP data, or product names. Payload data only carries:

- `route`
- `activationAction`
- `nudgeType`
- `nudgeId`
- optional `customerId` for opening Add Credit

`customerId` is used only by the authenticated app to fetch the merchant-owned
customer document before opening the Add Credit screen.

## Measurement

Backend writes each candidate/send under:

`users/{uid}/activationNudges/{nudgeId}`

Client captures `activation_nudge_opened` when a notification tap is routed.
Milestone completion is measured by existing events:

- `customer_created` with `customer_count_bucket`
- `product_created`
- `ordering_link_created`
- `ordering_link_shared`
- `sale_completed` with `is_credit=true`, `customer_is_existing=true`, and
  `has_products=true`
