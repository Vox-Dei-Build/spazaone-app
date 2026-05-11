# Pasella SMS — Remote Config change-set (QW-0)

**Lane:** `pas-sms-01-template-segment-audit`
**Date:** 2026-05-10
**Owner:** Firebase Remote Config console operator (Pasella admin)
**Risk:** very low — replaces a single typographically similar character (U+2013 EN DASH `–` → U+002D HYPHEN-MINUS `-`) in three RC strings. No customer-visible copy change at typical handset rendering. No code deploy required. Reversible by editing the same RC values back.

## Scope: Firebase Remote Config only — do NOT change the Twilio Content Templates

Pasella maintains two parallel copies of every transactional message:

- **SMS body** lives in **Firebase Remote Config** (`SMS_CREDIT_CONFIRMATION_SHORT`, etc.). The Flutter client reads this string, substitutes placeholders client-side, and sends the raw body via Twilio Programmable SMS. The SMS path is GSM-7/UCS-2 segmented, so the en-dash matters.
- **WhatsApp body** lives in a separate **Twilio Content Template** (referenced by SID — `TWILIO_CREDIT_TRANSACTION_TID`, etc.) and is approved by Meta. Twilio renders the WhatsApp template server-side. There is no GSM-7/UCS-2 segmentation on WhatsApp, so the en-dash there costs nothing and is not worth touching given the WhatsApp template-re-approval workflow (24-48h Meta review, possible rejection).

**This change-set touches Firebase RC only.** The two channel bodies will remain manually-synced in voice and structure but will diverge by a single character (`–` on WhatsApp, `-` on SMS). That divergence is intentional and invisible to merchants/customers in practice.

## Why

Three of four production `SMS_*_SHORT` Remote Config templates currently end with `"– {shopName}"` where `–` is **U+2013 EN DASH**. That single character is not in the GSM-7 default alphabet, so every credit confirmation, payment confirmation, and onboarding SMS is forced into UCS-2 encoding (70-char segments instead of 160). The result: **every such SMS is currently 2 segments instead of 1**, regardless of customer name length or amount.

Replacing the en-dash with a regular ASCII hyphen makes the skeleton GSM-7-clean. Combined with QW-1 (already shipped on this branch — see `lib/utils/currency_util.dart` `formatForSms`), the typical credit/payment/onboarding SMS drops from 2 segments to 1 segment. At the live rate of **R1.74/segment**, that is **R1.74 saved per send**.

See the full cost analysis in `docs/openclaw/pas-sms-01-template-segment-audit.md` (§5b).

## Exact RC values to write

Copy-paste each block exactly. Do **not** retype the trailing `-` — the only change vs the current production value is `–` (U+2013) → `-` (U+002D) on the line after `"trust."` / `"payment."` / `"joining!"`. Everything else (placeholders, casing, punctuation, spacing) is identical to the current production value.

### `SMS_CREDIT_CONFIRMATION_SHORT`

```
Hi {customerName}, credit of -{amount} at {shopName} recorded. Balance: {balance}. Thanks for your trust. - {shopName}
```

### `SMS_PAYMENT_CONFIRMATION_SHORT`

```
Hi {customerName}, payment of +{amount} at {shopName} recorded. Balance: {balance}. Thanks for your payment. - {shopName}
```

### `SMS_ONBOARDING_SHORT`

```
Hi {customerName}, welcome to {shopName}! Your account is now online. Balance: R0,00. Thanks for joining! - {shopName}
```

### `SMS_REMINDER_SHORT` — **no change**

The reminder template skeleton is already GSM-7 clean. No edit required.

## Verification after publish

1. Trigger a credit confirmation send to a test customer with `amount = R150`. Confirm via the wallet → notifications tab that the recorded `messageCost` is **R1.74** (1 segment) and not R3.48 (2 segments).
2. Repeat for a payment confirmation and an onboarding send.
3. If a charge of R3.48 still appears for any of the three flows on a `< R1 000` amount, **roll back** by pasting the previous RC value (with `–`) and report — it means a different non-GSM-7 character is hiding somewhere in the body.

## Rollback

Edit the same three RC values back to their previous form (with `–` U+2013) and publish. Effective on next RC fetch (typically within minutes for active sessions).

## Coupling with code changes on this branch

- The QW-1 currency formatter change (`CurrencyUtil.formatForSms` in `lib/utils/currency_util.dart`) ships in the same branch. **Either change** captures part of the cost saving on its own; **both together** are needed to drop every transactional SMS to 1 segment for typical rand values.
- Order of deploy is flexible: RC edit can ship before or after the code release.
- If the code release ships first and the RC strings are not yet edited, sends still cost 2 segments (en-dash dominates).
- If the RC edit ships first and the code release is delayed, sends drop to 1 segment for amounts < R1 000 but still flip to 2 segments for amounts >= R1 000 (U+00A0 from `CurrencyUtil.format` still in play).
