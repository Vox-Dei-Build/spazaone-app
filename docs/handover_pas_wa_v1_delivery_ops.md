# PAS-WA V1 — Manual Delivery Ops Handover

Branch: `feat/pas-wa-v1-delivery-ops`
Bot branch: `feat/pas-wa-v1-delivery-ops`

## Why

V1 already had merchant review + a single `ASSIGN_DRIVER` action, but
the delivery flow stopped there. Once a driver was assigned, the order
sat in `accepted` until a generic "Mark Collected" button — even for a
home delivery — and there was no way to:

- tell the customer the order had departed,
- record an actual delivery completion,
- swap the driver after a wrong allocation,
- contact the assigned driver from the order detail page.

This change closes those gaps with the smallest possible state machine
and keeps the model tunable for V2.

## State machine (post-change)

```
pending_merchant_review
        │ ACCEPT_ORDER                  REJECT_ORDER → rejected (terminal)
        ▼
     accepted ───────────────────────────────────────────────────────┐
        │                                                            │
        │ ASSIGN_DRIVER (delivery only)                               │
        │   • UNASSIGN_DRIVER clears driver, status stays            CANCEL_ORDER → cancelled
        │   • re-running ASSIGN_DRIVER overwrites the driver          (terminal)
        │                                                            │
        │ MARK_OUT_FOR_DELIVERY (delivery only, requires driver)      │
        ▼                                                            │
 out_for_delivery                                                    │
        │   • UNASSIGN_DRIVER walks back to `accepted`                │
        │ MARK_DELIVERED                                              │
        ▼                                                            │
   delivered  (collected=true, deliveredAt, finalises inventory) ────┘

— pickup branch unchanged: accepted → MARK_COLLECTED → collected
— payment branches (cash/transfer/eft, BNPL) unchanged
```

## Merchant actions now supported

| Action | Server path | Visible in app when |
|---|---|---|
| Accept Order | `ACCEPT_ORDER` | `pending_merchant_review` |
| Reject Order | `REJECT_ORDER` | `pending_merchant_review` |
| Assign Driver | `ASSIGN_DRIVER` | `accepted` AND delivery AND no driver |
| Reassign Driver | `ASSIGN_DRIVER` (prefilled dialog) | `accepted`/`out_for_delivery` AND delivery AND has driver |
| Unassign Driver | `UNASSIGN_DRIVER` | `accepted`/`out_for_delivery` AND delivery AND has driver |
| Mark Out for Delivery | `MARK_OUT_FOR_DELIVERY` | `accepted` AND delivery AND has driver |
| Mark Delivered | `MARK_DELIVERED` | `out_for_delivery` AND delivery |
| Mark Collected | `MARK_COLLECTED` | non-delivery only (delivery uses Mark Delivered) |
| Mark Cash/Payment Received | `MARK_CASH_RECEIVED` | unchanged |
| Accept/Reject/Settle BNPL | `ACCEPT_BNPL` / `REJECT_BNPL` / `SETTLE_BNPL` | unchanged |
| Cancel Order | `CANCEL_ORDER` | unchanged |

## What changed in the customer experience

- `ACCEPT_ORDER` template unchanged.
- `ASSIGN_DRIVER` (driver attached): same template as before — driver
  name & phone go to the customer.
- `MARK_OUT_FOR_DELIVERY`: new "On the way 🚗 …" message. Falls back to
  the existing `TWILIO_ASSIGN_DRIVER_TID` template SID if the dedicated
  `TWILIO_MARK_OUT_FOR_DELIVERY_TID` is not configured in Remote
  Config — keeps the customer ping live without a Twilio approval cycle.
- `MARK_DELIVERED`: new "Delivered ✅" message. Falls back to the
  `TWILIO_MARK_COLLECTED_TID` template if the dedicated key is missing.
- `UNASSIGN_DRIVER`: deliberately silent (does not message the
  customer). The next assign re-pings them.
- `MARK_CASH_RECEIVED` template now embeds the fulfillment summary
  verbatim (no longer hardcodes "Collect at …"), so a delivery payment
  receipt no longer says "collect".

## Files touched

### App (`feat/pas-wa-v1-delivery-ops`)

- `functions/src/ecommerce/updateOrderPayment.ts`
  - Adds `UNASSIGN_DRIVER`, `MARK_OUT_FOR_DELIVERY`, `MARK_DELIVERED` to
    the whitelist + transition switch.
  - `MARK_DELIVERED` mirrors `MARK_COLLECTED`'s inventory finalisation
    and flips `collected: true` for legacy reads.
  - `UNASSIGN_DRIVER` clears `driver`/`driverAssignedAt`, walks back
    `out_for_delivery` → `accepted`.
- `lib/pages/ecommerce/orders/data/payment_service.dart`
  - New entries in `actionStateLabels` and `actionTriggersMessage`.
  - `UNASSIGN_DRIVER` is the only silent action.
- `lib/pages/ecommerce/orders/widgets/actions_block.dart`
  - New buttons: Reassign Driver, Unassign Driver (tonal), Mark Out for
    Delivery, Mark Delivered.
  - "Mark Collected" relabels to "Mark Delivered" when the order is a
    delivery — this code path stays for safety even though the gating
    logic now hides it for delivery orders.
- `lib/pages/ecommerce/orders/order_detail_page.dart`
  - New gating booleans (`isOutForDelivery`, `isDelivered`,
    `showReassignDriver`, `showUnassignDriver`,
    `showMarkOutForDelivery`, `showMarkDelivered`).
  - `_assignDriver(reassign:)` prefills the dialog from the existing
    driver.
  - `_confirmUnassignDriver`, `_confirmMarkOutForDelivery`,
    `_confirmMarkDelivered` confirm dialogs.
  - `_DriverCard` widget on the Overview tab. Renders an
    "awaiting dispatch / on the way / delivered" chip and tap-to-call,
    tap-to-WhatsApp, and copy affordances on the driver phone. When
    no driver is set, the card prompts the merchant to assign one.
  - The collection/dispatch pill in the header now says
    "Awaiting Dispatch / Out for Delivery / Delivered" for delivery
    orders, "Collected / Uncollected" for pickup.
- `lib/pages/ecommerce/widgets/order_status.dart`
  - New enum values: `accepted`, `outForDelivery`, `delivered`.
  - Resolver prefers fulfillment terminal states over generic "paid"
    so the header shows "Delivered" / "Out for Delivery" rather than
    "Paid".
  - `buildCollectionPill` is now fulfillment-aware.
- `lib/services/order_status_messaging_service.dart`
  - New template fallback strings for `MARK_OUT_FOR_DELIVERY` and
    `MARK_DELIVERED`.
  - Variables for `MARK_OUT_FOR_DELIVERY` reuse the `ASSIGN_DRIVER`
    `{{1}}/{{2}}/{{3}}` shape so existing approved templates can be
    used as a fallback SID.
  - `MARK_CASH_RECEIVED` no longer hardcodes "Collect at".
- `lib/config/remote_config.dart`
  - New keys `TWILIO_MARK_OUT_FOR_DELIVERY_TID`,
    `TWILIO_MARK_DELIVERED_TID` (default empty → use fallbacks above).
- `test/payment_service_state_labels_test.dart`
  - Whitelist mirror updated. Adds `silentActions` set so
    `UNASSIGN_DRIVER` having `actionTriggersMessage: false` is the
    contract, not a regression.

### Bot (`feat/pas-wa-v1-delivery-ops`)

- `src/backend.ts`
  - `SaleOrder` now exposes `fulfillmentType`, `deliveryAddress`,
    `driver`, `deliveredAt`, `outForDeliveryAt`.
- `src/orders.ts`
  - `statusLabel` recognises `accepted`, `out_for_delivery`,
    `delivered`, `pending_merchant_review`.
  - `formatOrderStatus` surfaces `Driver: <name> · <phone>` to the
    customer when the order is out for delivery (or accepted with a
    driver attached) so a "where's my order" track query returns the
    operationally useful answer.

## Test checklist

Manual (run as a merchant against a real WhatsApp delivery order):

1. **Happy path — pickup unchanged**
   - Customer requests collection; merchant taps Accept → status pill
     shows **Accepted**.
   - Tap Mark Collected → status pill shows **Collected**, customer
     receives the existing "Order collected 📦" message.

2. **Happy path — delivery**
   - Customer requests delivery with an address; merchant taps Accept.
   - Driver Card shows "No driver yet"; bottom action shows **Assign
     Driver** only.
   - Assign driver (name + phone). Driver Card now shows the driver,
     "Awaiting dispatch" chip, Call / WhatsApp / Copy buttons. Bottom
     actions: **Mark Out for Delivery**, **Reassign Driver**,
     **Unassign Driver**.
   - Tap Mark Out for Delivery → confirmation dialog → status pill
     becomes **Out for Delivery**, chip becomes "On the way", customer
     receives the on-the-way message with driver/phone.
   - Tap Mark Delivered → confirmation dialog → status pill becomes
     **Delivered**, chip becomes "Delivered", inventory finalises,
     customer receives the delivered message.

3. **Reassign**
   - From an order that already has a driver (in `accepted` or
     `out_for_delivery`), tap Reassign Driver. Dialog prefills with the
     current driver. Submit a new name/phone. Customer gets a fresh
     driver-assigned message.

4. **Unassign**
   - From `accepted` with a driver: tap Unassign Driver → confirmation
     → driver disappears, Mark Out for Delivery hides, Assign Driver
     reappears. No customer message sent.
   - From `out_for_delivery`: tap Unassign Driver → confirmation →
     status walks back to `accepted`, driver cleared, Mark Out for
     Delivery returns once a new driver is assigned.

5. **Driver contact affordances**
   - On a driver with a phone, Call opens the dialer, WhatsApp opens
     `wa.me/<digits>`, Copy puts the phone on the clipboard.

6. **Server guardrail**
   - Calling `MARK_OUT_FOR_DELIVERY` without a driver returns
     `failed-precondition`; the snackbar surfaces "Assign a driver
     before marking the order out for delivery."

7. **Bot — track order**
   - Customer asks "where's my order" while it's `out_for_delivery`.
     Bot reply now includes `Status: out for delivery` and a
     `Driver: <name> · <phone>` line.

Automated:

```sh
# App
flutter test test/payment_service_state_labels_test.dart   # 4/4
flutter analyze lib/pages/ecommerce/orders \
                 lib/pages/ecommerce/widgets/order_status.dart \
                 lib/services/order_status_messaging_service.dart \
                 lib/config/remote_config.dart \
                 test/payment_service_state_labels_test.dart
# 0 new issues; 3 pre-existing infos remain (avoid_print x2,
# WillPopScope deprecation x1)

# Functions
(cd functions && ./node_modules/.bin/tsc --noEmit)          # clean

# Bot
(cd <bot worktree> && npm run typecheck && npm test)        # 151/151
```

## Tunable / V2 notes

- `TWILIO_MARK_OUT_FOR_DELIVERY_TID` and `TWILIO_MARK_DELIVERED_TID`
  are the right place to attach dedicated Twilio templates once
  product approves them. Until then the fallbacks keep the customer
  ping operationally accurate.
- The `driver.id` field is preserved end-to-end but not yet populated
  by any UI. A V2 driver picker can write it without touching the
  state machine.
- `UNASSIGN_DRIVER` deliberately does not notify the customer. If
  product wants a "your driver was changed" ping, set
  `actionTriggersMessage['UNASSIGN_DRIVER'] = true`, drop
  `'UNASSIGN_DRIVER'` from `silentActions` in the regression test, and
  add a template entry. No server changes required.
- The state machine does not yet model "delivery attempted but
  failed". When the ops volume justifies it, add a
  `MARK_DELIVERY_FAILED` action with a `failureReason` field and a
  retry path back to `accepted`.
