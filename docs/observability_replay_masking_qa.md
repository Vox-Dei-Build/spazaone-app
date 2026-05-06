# Replay Masking QA Checklist

Manual on-device audit to confirm PostHog session replay masks all PII before
any real customer session is recorded. Run this **once per release** that
touches an instrumented surface, and **always** before flipping replay
defaults in production.

## Setup (do once, before testing)

1. Build a fresh debug install on a real device:
   `fvm flutter run --dart-define=POSTHOG_DEBUG=true` (or your usual command).
2. Sign in with a **test merchant account** -- never a live merchant.
3. Open the consent modal on first launch and **opt IN** to:
   - Crash reports (already on)
   - Product analytics
   - **Session replay**
4. Confirm in app logs that PostHog initialised against `eu.i.posthog.com`
   and that `Posthog().isFeatureEnabled` / capture calls are firing.
5. Open PostHog EU project in a second window:
   `Activity -> Session replay`. Keep the most recent session open, refresh
   after each scenario below.

> Replays land in PostHog with a 30-60s lag. Wait, then refresh.

## Global expectation

For **every** screen below:
- Text on masked widgets must render as a **solid block / shimmer** in replay,
  not as readable characters.
- Tap and scroll **events** must still appear on the timeline -- masking
  hides pixels, not interactions.
- Avatars and profile photos must be masked (`maskAllImages = true`).
- Crash events (forced via debug button if you have one, otherwise via a
  deliberately broken flow) must appear in Firebase Crashlytics.

If any masked widget shows **readable text** in replay, stop and file a bug
before continuing -- a single leak is enough to fail POPIA review.

---

## 1. Auth surfaces

Wrapped via `PrivateRegion` -- mobile / OTP / password fields.

- [ ] **Login (`login_ui.dart`)**
  - Type a mobile number. Replay: number masked, keyboard taps visible on
    timeline.
- [ ] **OTP entry (`auth_view_model.dart`)**
  - Trigger SMS code prompt. Replay: 6-digit field masked.
- [ ] **Register (`register.dart`)**
  - Fill name, mobile, business name. Replay: all three masked.
- [ ] **Register anonymous (`register_anonymous.dart`)**
  - Same three fields. Replay: all masked.
- [ ] **Account deletion (`account_deletion_service.dart`)**
  - Trigger delete flow. Replay: password field + 6-digit confirmation
    code both masked.

Events to confirm in PostHog `Events` tab:
- [ ] `SignupCompleted` (×4 paths -- mobile, anonymous, social, email if applicable)
- [ ] `SigninCompleted` (×2 paths)
- [ ] `SignoutCompleted`

---

## 2. Contact / customer management

- [ ] **Add contact (`add_contact.dart`)**
  - Type customer name + phone. Replay: both fields masked.
- [ ] **Edit contact (`edit_contact.dart`)**
  - Edit existing customer. Replay: both fields masked.
- [ ] **Customer profile header (`profile_actions_bar.dart`)**
  - Open a customer profile. Replay: customer name in the actions bar
    Column masked. Action icons (call / message / etc.) still visible.

---

## 3. Ledger / transactions

This is the **highest-risk** area -- name + outstanding balance pairs.

- [ ] **Ledger row (`transaction_tile.dart`)**
  - Open the main ledger list. Replay: every row's name + balance masked,
    profile pictures masked, dividers visible.
  - Tap a row. Tap event must appear on timeline (GestureDetector is
    outside the mask).
- [ ] **Customer transactions list (`transactions_list_view.dart`)**
  - Open a customer profile -> transactions tab. Replay: every transaction
    card (amount + note) masked. Date headers may or may not be masked
    (acceptable either way -- dates are not PII).
  - Tap a card -> transaction detail opens. Tap event recorded.
- [ ] **NPA / customers-owing list (`customer_names_display.dart`)**
  - Open Reports -> customers with outstanding balance. Replay: names +
    balances masked, reminder icons (green / red / grey) **visible** so
    you can audit reminder coverage from replay.

Events to confirm:
- [ ] `SaleStarted` when opening Add Transaction.
- [ ] `SaleCompleted` with `paymentType=cash` and `customerIsExisting`
  boolean.
- [ ] `SaleCompleted` with `paymentType=credit` (from
  `add_credit_view_model.dart`).
- [ ] `amount_bucket_zar` property present on sale events (e.g. `0_50`,
  `50_200`, etc.) -- raw amount must NOT be sent.

---

## 4. Wallet / payouts / topup

- [ ] **Banking details form (`add_banking_details.dart`)**
  - Open wallet -> add bank details. Replay: full ListView (account
    number, branch code, holder name) masked.
- [ ] **Banking summary (`banking_details_tab.dart`)**
  - View saved banking details. Replay: summary Card masked.
- [ ] **Paystack WebView (`paystack_webview.dart`)**
  - Initiate a topup. Replay: WebView surface masked end-to-end (card
    number, CVV, OTP).
- [ ] **Paystack form fallback (`paystack_form.dart`)**
  - If applicable, run a topup via the in-app form path.

Events to confirm:
- [ ] `WalletTopupStarted` at form submit.
- [ ] `WalletTopupCompleted` on success.
- [ ] `WalletTopupFailed` with `failure_code` ∈ {`init_null`, `cancelled`,
  `webview_failed`, `exception`} -- exercise at least `cancelled` by
  closing the WebView mid-flow.
- [ ] `PayoutRequested` when submitting a payout.
- [ ] `PayoutFailed` with `reason='client_submit_error'` -- force by going
  offline before submit.

---

## 5. BNPL

- [ ] **Order detail (`order_detail_page.dart`)**
  - Open an order eligible for BNPL. Replay: any customer name on this
    screen masked (verify via SectionCard wrapping).

Events to confirm:
- [ ] `BnplOfferShown` fires **once** per order open (idempotent guard).
  Re-open the same order -- second fire must NOT appear.
- [ ] `BnplOfferAccepted` on accept.
- [ ] `BnplOfferRejected` on reject.

---

## 6. Comms (WhatsApp + SMS)

These don't have UI to mask -- audit is **event-only**.

- [ ] Send a WhatsApp reminder to a test customer. Wait for delivery
  callback. Confirm `CommsSent` event with `channel='whatsapp'`,
  `templateId` set, `recipientCount=1`.
- [ ] Send an SMS reminder. Confirm `CommsSent` with `channel='sms'` after
  Twilio returns 201.
- [ ] Force a Twilio non-200 (invalid number). Confirm a non-fatal lands
  in Crashlytics with `status_code` context, **no** `CommsSent` event.

---

## 7. Crash / non-fatal coverage

- [ ] Force a wallet view-model failure (e.g. invalid banking details
  payload). Confirm Crashlytics shows a non-fatal with `reason`
  describing the source.
- [ ] Force a reporting service failure (e.g. by going offline during
  report generation). Confirm Crashlytics shows a non-fatal with
  `reason: 'reporting: ...'`.
- [ ] Confirm Firebase Crashlytics dashboard receives all of the above
  within ~5 min.

---

## 8. Consent regression

- [ ] Open settings -> revoke analytics + replay consent.
- [ ] Repeat one ledger interaction. Confirm:
  - No new event appears in PostHog.
  - No new replay session is created.
  - Crashlytics still receives non-fatals (crash consent stayed ON).
- [ ] Re-grant consent. Confirm events resume **without** an app restart
  (PostHog `enable()` path).

---

## 9. Sign-off

When all sections are checked, capture:

- Tester name + date
- App build number
- PostHog session URL of the final all-green run
- Firebase Crashlytics issue list URL for the same window

Paste those into the release ticket. Without a green run of this checklist,
**do not** flip replay defaults to ON in production.
