# pas-adk-01 - app release note

Release target: `v3.0.6+51`
Date prepared: 2026-05-15

## Purpose

Prepare the Pasella merchant app for the Botpress ADK pilot lane without
changing the live WhatsApp bot.

## Included changes

- Messages tab performance: polling starts once, duplicate fetches are guarded,
  refresh fetches run in parallel, and long conversations render lazily.
- Order display alignment: totals normalize across `amount`, `total`, and
  `saleTotal`.
- Online sales detail fix: `getOnlineSalesFromLedger` now honors `orderId` and
  `reference` filters.
- Item count fix: merchant sales now sum product quantities.
- Bot-facing backend exports remain in place for account summary, customer
  statement, and merchant catalog access.

## Deployed backend functions

These functions were already deployed to `pasella-ledger`:

- `getOnlineSalesFromLedger`
- `getCustomerOrders`
- `getOrderById`
- `getMerchantSales`

No live WhatsApp bot deploy was performed.

## Verification

- `pasella-app/functions npm run build` passed.
- `pasella-app/functions npm run lint -- --fix=false` had 0 errors; existing
  warnings remain.
- Touched Dart files analyzed with no errors; existing info warnings remain.
- Botpress lane: `npm test`, `npm run typecheck`, `npm run typecheck:bot`, and
  `npm run bp:build` passed.

## Morning checks

1. Confirm CodeMagic builds tag `v3.0.6+51`.
2. Test the messages tab on a long customer conversation.
3. Open an online sale detail and verify it matches the selected order.
4. Check a bot-created order in customer order history.
5. Keep live bot checkout disabled.

## Weekend security track

- Remove Twilio and Botpress credentials from the mobile app.
- Move message fetching to a backend/materialized conversation feed.
- Enforce Firebase Auth/App Check for app endpoints.
- Add bot-only authorization for ADK backend HTTP calls.
- Validate Paystack webhook signatures and tighten sale/payment matching.
