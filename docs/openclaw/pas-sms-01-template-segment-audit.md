# Pasella SMS Template Inventory & Segment Audit

- Lane: `pas-sms-01-template-segment-audit`
- Branch: `audit/pas-sms-01-template-segment-audit`
- Base: `origin/main` @ `b86c2c8`
- Date: 2026-05-10
- Status: **Implemented + Verified against live Remote Config snapshot. Blocked only on live `messagingTemplates` Firestore content.**

> **TL;DR — biggest finding:** three of the four live `SMS_*_SHORT` Remote Config templates contain a **U+2013 EN DASH (`–`)** in the sign-off (`"– {shopName}"`). That single non-GSM-7 character forces every credit, payment, and onboarding SMS into UCS-2 (70-char segments) on every send, regardless of amount size. Replacing it with an ASCII hyphen (`-`) immediately drops these from 2 segments to 1 segment in the typical case, saving ~**R1.74 per send** at the live rate. Combined with the currency-formatter U+00A0 fix, this cuts a representative 16-send sample from **31 segments (R53.96) to 16 segments (R27.85) — a 48% reduction in SMS COGS** with no copy change.

## 0. What was shipped on this branch

> **Architectural note — two parallel sources of truth:** Pasella maintains the SMS body and the WhatsApp body as **separate, manually-synced copies** for each transactional event:
> - **SMS body** → Firebase Remote Config (`SMS_*_SHORT` keys). Substituted client-side, sent raw via Twilio Programmable SMS. Subject to GSM-7 / UCS-2 segmentation.
> - **WhatsApp body** → Twilio Content Template (approved by Meta, referenced by SID). Rendered server-side by Twilio. Not segmented; emoji/typography/length are cost-neutral.
>
> All cost findings in this audit (F-1 en-dash, F-2 currency NBSP, F-3 reminder length) live on the **SMS side only**. The QW-0 RC edit is therefore Firebase-only — the matching Twilio Content Templates intentionally keep their existing typography because (a) it costs nothing on WhatsApp and (b) any Twilio Content Template edit triggers a 24-48h Meta re-approval flow that isn't worth the friction for a typographic change with no customer-visible benefit. After QW-0, the SMS and WhatsApp bodies diverge by a single character (`-` vs `–`) — invisible at typical handset rendering, but worth recording so a future "sync the templates" exercise doesn't accidentally reintroduce the en-dash into RC.

| Quick win | Status | Where |
|---|---|---|
| **QW-0** — replace `–` (U+2013) with `-` in three Firebase RC strings | **Ready to publish** (Firebase RC console action, no code, no Twilio change) | `docs/openclaw/pas-sms-01-rc-changeset.md` (paste-ready strings + verification + rollback) |
| **QW-1** — SMS-safe currency formatter (`formatForSms`) | **Code shipped** | `lib/utils/currency_util.dart` (new `formatForSms`); SMS-substitution callsites routed through it: `lib/services/messaging_notification_service.dart` (credit/payment/onboarding/reminder paths + `_sendSMSFallback` formattedBalance), `lib/services/message_queue.dart` (queued SMS construction). WhatsApp template variable maps and Firestore notification archive intentionally still use locale-formatted `CurrencyUtil.format` for display. |
| **QW-1 verification** — unit tests for `formatForSms` | **Code shipped** | `test/currency_util_sms_test.dart` (8 tests covering small/large/zero/negative amounts, GSM-7 ASCII safety, and end-to-end 1-segment SMS rendering with the post-QW-0 reminder skeleton) |
| **F-4** — substitution gap on credit/payment confirmation | **Resolved as false alarm** | Trace in §5 F-4. `_sendSMSFallback` always runs the trailing `{balance}`/`{shopName}` substitution before send. No customer-visible bug. Adjacent footgun (split-phase substitution) called out for future refactor. |
| **QW-5** — delete dead long-template fields and their RC reads | **Code shipped** | `lib/templates/sms_message.dart` (removed `creditConfirmation`/`paymentConfirmation`/`onboarding`/`reminder` fields and their `SMS_CREDIT_CONFIRMATION` / `SMS_PAYMENT_CONFIRMATION` / `SMS_ONBOARDING` / `SMS_REMINDER` RC reads). Matching long RC keys are being deleted in the Firebase console (user action). |
| **QW-6** — fix GSM-7 boundary in `SMSPricingUtil` | **Code shipped** | `lib/utils/sms_pricing_util.dart` rewritten with explicit GSM 03.38 default + extension table membership, 153/67 multipart parts with UDH overhead, new `SmsEncoding` enum and `SmsEncodingInfo` (with `offenderLabel` for UI). 14 unit tests in `test/sms_pricing_util_test.dart`. |
| **QW-3** — Remote Config defaults for SMS templates | **Code shipped** | `lib/config/remote_config.dart` `setDefaults` map now includes literal ASCII-hyphen defaults for `SMS_CREDIT_CONFIRMATION_SHORT` / `SMS_PAYMENT_CONFIRMATION_SHORT` / `SMS_ONBOARDING_SHORT` / `SMS_REMINDER_SHORT` and `SMS_TEMPLATE_KEYWORDS = '[]'`. Eliminates the empty-string failure mode if a RC fetch fails or a key is missing. |
| **QW-2** — surface segment-trigger reason in the cost UI | **Code shipped** | `lib/pages/promote/widgets/templates/create_template/steps/content_step.dart` and `steps/review_step.dart` render an inline warning whenever `SmsEncodingInfo.offenderLabel` is non-null (e.g. "Contains an en-dash (–) which forces a more expensive Unicode encoding"). Wired from `create_template.dart` via the new `SMSPricingUtil.classify` call. |

Combined deploy effect (with both QW-0 and QW-1 live): **48% reduction in SMS COGS on the representative 16-send sample (R53.96 → R27.85), zero customer-visible copy change, no Twilio Content Template edits, no WhatsApp re-approval cycle.**

---

## 1. Scope and verification bar

In-scope: any code path that composes outbound SMS body text in the Pasella Flutter app, plus the segment/cost calculator and the UI surfaces that show segment counts to merchants.

Verification bar:
- Strings are quoted verbatim only where they live in this repo.
- Any value sourced from Firebase Remote Config, Firestore (`messagingTemplates`), or merchant-authored content is flagged as a runtime unknown.
- No claim of live segment parity is made; segment counts shown below are *worst-case structural estimates* of the template skeletons after substitution-aware rendering.

---

## 2. Inventory: where SMS body text comes from

### 2.1 Code-resident SMS bodies (verbatim, this repo)

| ID | Source file | Lines | Body | Variables | Notes |
|---|---|---|---|---|---|
| C-1 | `functions/src/templates/messageTemplates.ts` | 12-18 | `Dear {customerName}, your recent Credit of -{amount} at {shopName} has been recorded.\n\nYour current balance is {balance}. Thank you for trusting {shopName}'s business!\n\nFrom {shopName}` | `{customerName} {amount} {shopName} {balance}` | Server-side only. **Not** loaded by client; closest historical analogue to the missing `SMS_CREDIT_CONFIRMATION` RC default. |
| C-2 | `functions/src/templates/messageTemplates.ts` | 25-31 | `Dear {customerName}, your recent Payment of +{amount} at {shopName} has been recorded.\n\nYour current balance is {balance}. Thank you for paying {shopName}'s business and for being reliable!\n\nFrom {shopName}` | `{customerName} {amount} {shopName} {balance}` | Server-side only. |
| C-3 | `functions/src/templates/messageTemplates.ts` | 38-44 | `Welcome to {shopName}, {customerName}! No more books! Your account with {shopName} is now online.\n\nYour current balance is R0,00. Thank you again for choosing {shopName}'s business!\n\nFrom {shopName}` | `{customerName} {shopName}` | Server-side only. Hard-codes `R0,00` (comma decimal — GSM-7 safe in isolation). |
| C-4 | `functions/src/templates/messageTemplates.ts` | 51-58 | `Hi {customerName}, your balance at {shopName} of {balance} is due.\n\nPlease keep up to date with your payments and join the 98% of {shopName}'s customers who pay back on time or penalties will be charged.\n\nFrom {shopName}` | `{customerName} {shopName} {balance}` | Server-side only. |
| C-5 | `lib/services/order_status_messaging_service.dart` | 14-25 | 6 BNPL/order-status bodies — see §2.3 | Mustache `{{...}}` | Not actually sent over the wire as raw text; only stored as `renderedMessage` in Firestore. The Twilio Content SID renders the live message. |
| C-6 | `lib/utils/support_util.dart` | 50-63 | 5 hard-coded WhatsApp deep-link bodies | none | WhatsApp only, not SMS. Out of cost scope but contains emoji that would force UCS-2 if reused for SMS. |
| C-7 | `lib/pages/promote/widgets/templates/create_template/force_boilerplate.dart` | 22 | `Hello {{customerName}},\n<merchant body>\nKind regards,\nThe {{shopName}} team` | `{{customerName}} {{shopName}}` | Wraps merchant promo content. Adds **~38 fixed chars** of GSM-7-safe greeting/signoff overhead before the merchant's text is even counted. |

### 2.2 The "live" SMS bodies actually sent by the client

Loaded from Remote Config at app start (`lib/templates/sms_message.dart:18-39`). **Live values snapshotted 2026-05-10 from production RC** (verbatim, with non-GSM-7 chars highlighted):

| RC key | Live value | Non-GSM-7 chars |
|---|---|---|
| `SMS_CREDIT_CONFIRMATION_SHORT` | `Hi {customerName}, credit of -{amount} at {shopName} recorded. Balance: {balance}. Thanks for your trust. – {shopName}` | **U+2013 `–`** at pos 106 |
| `SMS_PAYMENT_CONFIRMATION_SHORT` | `Hi {customerName}, payment of +{amount} at {shopName} recorded. Balance: {balance}. Thanks for your payment. – {shopName}` | **U+2013 `–`** at pos 109 |
| `SMS_ONBOARDING_SHORT` | `Hi {customerName}, welcome to {shopName}! Your account is now online. Balance: R0,00. Thanks for joining! – {shopName}` | **U+2013 `–`** at pos 106 |
| `SMS_REMINDER_SHORT` | `Hi {customerName}, your balance of {balance} at {shopName} is due. Please make your payment to avoid any late fees. From {shopName}` | none in skeleton; UCS-2 trips only via `{amount}`/`{balance}` U+00A0 |

Substitution map (verbatim from `messaging_notification_service.dart`):

| Field | Read at | Rendered at | Substitution |
|---|---|---|---|
| `creditConfirmationShort` | `lib/templates/sms_message.dart:27` | `messaging_notification_service.dart:452-454` | `{customerName}`, `{amount}` |
| `paymentConfirmationShort` | `:28` | `messaging_notification_service.dart:459-461` | `{customerName}`, `{amount}` |
| `onboardingShort` | `:29` | `messaging_notification_service.dart:497, 503` then `_sendSMSFallback:214-217` | `{balance}`, `{shopName}`, `{customerName}` |
| `reminderShort` | `:30` | `messaging_notification_service.dart:526, 532` then `_sendSMSFallback:214-217` | `{balance}`, `{shopName}`, `{customerName}` |
| `creditConfirmation` / `paymentConfirmation` / `onboarding` / `reminder` (long) | `:22-25` | **never read** | dead state. RC values are pulled but never reach an SMS body. |

Note: `creditConfirmationShort` and `paymentConfirmationShort` use `{shopName}` and `{balance}` in the live RC string but the renderer at `messaging_notification_service.dart:452-454` and `:459-461` only substitutes `{customerName}` and `{amount}`. **`{shopName}` and `{balance}` will be sent as literal placeholder text** unless `_sendSMSFallback` is also reached. This is a substitution bug separate from segment cost — flagged for the Delivery Pod to verify which call path is live for these two flows.

Other queued/promotion paths reuse the same substitution conventions:
- `lib/services/message_queue.dart:106-117` — `{balance} {shopName} {customerName} {amount}`. Default `shopName` if user lookup fails: `'The Corner Shop'` (`message_queue.dart:80`); default `amount` if null: literal string `'R0.0'` (line 116). Note inconsistency: `R0.0` here vs `R0,00` in onboarding fallback C-3.

### 2.3 Order-status bodies (C-5 verbatim, ASCII-and-emoji)

```
ACCEPT_BNPL: BNPL approved 🎉
Hi {{customerName}}, your Pay Later request for order {{orderId}} is approved.
Total: {{amount}} · Items: {{itemsCount}}
Collect at: {{pickupLocation}}. We’ll remind you until it’s settled.
Need help? {{support}}

REJECT_BNPL: BNPL decision
Hi {{customerName}}, your Pay Later request for order {{orderId}} wasn’t approved.
You can still pay cash {{amount}} and collect.
Questions? {{support}}

MARK_CASH_RECEIVED: Payment received ✅
Thanks {{customerName}}! We received {{amount}} for order {{orderId}} ({{itemsCount}} items).
Collect at {{pickupLocation}}.
Keep this for your records.

MARK_COLLECTED: Order collected 📦
Hi {{customerName}}, order {{orderId}} has been marked collected.
Thank you for shopping with us!
We appreciate you.

SETTLE_BNPL: BNPL settled ✅
Thanks {{customerName}}! Your Pay Later for order {{orderId}} is fully settled.
Final payment: {{amount}}.
You’re all squared up.

CANCEL_ORDER: Order cancelled
Hi {{customerName}}, order {{orderId}} has been cancelled.
If this was a mistake, reply and we’ll help.
Support: {{support}}
```

Each body contains at least one of: 🎉 ✅ 📦 (non-BMP emoji), curly apostrophe `’`, middle dot `·`. **All are non-GSM-7.** If any of these are ever pushed down the SMS path (rather than only WhatsApp + Firestore archival), every send forces UCS-2 and at minimum 2 segments.

### 2.4 Merchant-authored templates (Firestore)

`lib/services/template_service.dart:10-17` — collection `messagingTemplates`, filter `active == true`, fields `channels.sms.templateContent` and `channels.whatsapp.templateContent`. Variables use `{{name}}` Mustache convention (`template_service.dart:42`). All content is runtime-merchant-authored and **not visible in this repo**.

---

## 3. The segment calculator (code-grounded)

`lib/utils/sms_pricing_util.dart:1-24`:

```dart
final isUnicode = content.runes.any((r) => r > 127);
final singleSegmentLength  = isUnicode ? 70  : 160;
final multipartSegmentLength = isUnicode ? 67 : 153;
return content.length <= singleSegmentLength
    ? 1
    : (content.length / multipartSegmentLength).ceil();
```

**Correctness gaps that affect cost truth:**

1. `r > 127` is the *ASCII* boundary, not the *GSM-7* boundary. GSM-7 covers many non-ASCII characters (`£`, `¤`, `§`, `Ä`, `Å`, `É`, `à`, `è`, `ñ`, etc.) and the GSM-7 *extension table* (`{ } [ ] ~ \ | ^ €`) which consume **2 septets each**. The current util:
   - Falsely flags GSM-7-safe non-ASCII (e.g. `£`, `É`) as Unicode → overcharges the merchant in the preview.
   - Falsely undercounts GSM-7 extension chars (e.g. `€`, `{`) → undercharges 1 septet per occurrence.
2. `content.length` counts UTF-16 code units in Dart strings. Non-BMP emoji (🎉, 📦, ✅) are **2 UTF-16 units each but encode as one UCS-2 surrogate pair = 2 SMS code units**, so this happens to be accidentally correct for emoji length — but `content.runes.any((r) > 127)` *will* correctly trigger the UCS-2 branch.
3. There is **no normalisation** before counting: leading/trailing whitespace is trimmed but interior collapsing/CRLF handling is absent. `\n` counts as 1 GSM-7 septet, which is correct.
4. The pricing formula at `calculateCost` uses `unitCost * segments`. The unit cost is `USD_SMS_*_PRICE` × `USD_ZAR_EXCHANGE_RATE` × `(1 + MARKUP_SMS_PERCENTAGE/100)` (per `lib/config/remote_config.dart:21-70`). **Live rate is unknown to this audit.**

---

## 4. Hidden cost leak: en_ZA currency formatting forces UCS-2 on every transactional SMS

`lib/utils/currency_util.dart:7`:

```dart
static final _formatCurrency = NumberFormat.simpleCurrency(locale: 'en_ZA');
```

`intl`'s `en_ZA` currency format renders amounts as e.g. `R1\u00A0234,56` — the thousands separator is **U+00A0 NO-BREAK SPACE** and the decimal separator is `,`. U+00A0 is not in GSM-7. Every `{amount}` and `{balance}` substitution that has 4+ digits of rand (i.e. R 1 000 or above — which is the modal credit/payment value for SA spaza shops, not an edge case) injects a U+00A0 into the body.

Consequence: **any transactional SMS for an amount ≥ R1 000 silently flips the entire body to UCS-2 segmentation (70 chars per segment vs 160).** A 130-char body that would have cost 1 segment in GSM-7 becomes 2 segments in UCS-2. With Pasella's published per-segment SA SMS cost in the same order of magnitude as the WhatsApp utility cost, this roughly doubles SMS COGS on every reminder/credit/payment confirmation that crosses the R1 000 line.

The merchant-facing cost preview (`SMSPricingUtil.calculateSegments` called from `add_payment_view_model.dart:87`, `add_credit_view_model.dart:110`, `customer_management_view_model.dart:285,350`, etc.) **does** see this — it is run on the rendered string after substitution — so the displayed cost is correct. The leak is that:
- Merchants are not told *why* the cost jumped.
- There is no obvious lever to bring it back down (the U+00A0 is invisible in normal previews).

This is the single biggest finding of the audit.

---

## 5. Findings (per template, per offender) — live-data version

> **Live pricing inputs (from production RC, 2026-05-10):**
> `USD_SMS_REMINDER_PRICE = USD_SMS_PAYMENT_PRICE = 0.0757` USD/segment ·
> `MARKUP_SMS_PERCENTAGE = 26` · `USD_ZAR_EXCHANGE_RATE = 18.25`
> → **Effective unit cost: 0.0757 × 18.25 × 1.26 = R1.7407 per segment** (≈ **R1.74/segment**).
>
> Substitution scenarios used below (representative SA spaza shop):
> - `customerName = "Thandiwe"` (8) or `"Sibongile"` (9)
> - `shopName = "Spaza King"` (10) or `"The Corner Shop"` (15)
> - `amount`/`balance` ∈ {R150, R999.99, R1 250, R12 500} — the last two trigger the U+00A0 thousands-separator UCS-2 path.

### Baseline segment counts (current production behaviour)

| Template | R150 | R999.99 | R1 250 | R12 500 |
|---|---|---|---|---|
| `CREDIT_SHORT` | **2 (R3.48)** | **2 (R3.48)** | **2 (R3.48)** | **2 (R3.48)** |
| `PAYMENT_SHORT` | **2 (R3.48)** | **2 (R3.48)** | **2 (R3.48)** | **2 (R3.48)** |
| `ONBOARDING_SHORT` | **2 (R3.48)** | **2 (R3.48)** | **2 (R3.48)** | **2 (R3.48)** |
| `REMINDER_SHORT` | 1 (R1.74) | 1 (R1.74) | **2 (R3.48)** | **3 (R5.22)** |

Across this 16-send sample: **31 segments, R53.96.**

### F-1 (CRITICAL) — U+2013 EN DASH in three of four live RC templates

`CREDIT_SHORT`, `PAYMENT_SHORT`, and `ONBOARDING_SHORT` all end with `"– {shopName}"` where `–` is **U+2013 EN DASH**, not the GSM-7-safe ASCII hyphen-minus `-` (U+002D).

Consequence: every credit, payment confirmation, and onboarding SMS is forced into UCS-2 segmentation by this single character. None of these messages can ever be 1 segment in production today, regardless of customer name length or amount value.

Fix: replace `–` with `-` in the three RC values. **No copy change visible to merchants or customers** at typical phone resolutions; the typographic difference is largely invisible in SMS rendering on most handsets.

Impact in isolation (pure RC edit, no code change): the 16-send sample drops from 31 segs → 23 segs (R40.04), saving R13.92 per representative cycle. Per individual send: R1.74 saved on credit/payment/onboarding under R1k.

### F-2 (HIGH) — `CurrencyUtil.format` injects U+00A0 on amounts ≥ R1 000

`lib/utils/currency_util.dart:7` uses `NumberFormat.simpleCurrency(locale: 'en_ZA')`, which emits U+00A0 as the thousands separator (e.g. `R1\u00A0250,00`). Once F-1 is fixed, this becomes the next-largest cost driver: every transactional SMS where `amount` or `balance` ≥ R1 000 still flips to UCS-2.

Fix (QW-1): bypass `CurrencyUtil.format` in SMS substitution paths; use a hyphen-free, NBSP-free formatter (e.g. `R + amount.toStringAsFixed(2).replaceAll('.', ',')` → `R1250,00`).

Impact in isolation: 31 → 28 segs (R48.74). Combined with F-1 fix: 31 → 16 segs (R27.85).

### F-3 (HIGH) — Reminder template multipart explosion on large balances

`REMINDER_SHORT` skeleton is 131 chars. Once a balance ≥ R1 000 trips UCS-2 (via F-2), and the customer/shop names are realistic (15+ chars), the body crosses the **134-char UCS-2 multipart boundary (2 × 67)** and becomes 3 segments, not 2. The R12 500 / "The Corner Shop" / "Sibongile" scenario already shows this: **3 segments × R1.74 = R5.22 per reminder.**

Reminders are sent disproportionately to delinquent customers — i.e. those most likely to have multi-thousand-rand balances. This is the single most expensive per-send template in production today.

Fix path: F-2 alone collapses this to 1 segment (the skeleton is GSM-7 clean once `{balance}` no longer contains U+00A0). No copy change required.

### F-4 (RESOLVED — false alarm) — Substitution gap on credit/payment confirmation

Initial reading suggested `{shopName}` and `{balance}` placeholders in `SMS_CREDIT_CONFIRMATION_SHORT` and `SMS_PAYMENT_CONFIRMATION_SHORT` were never substituted. Full call-path trace shows otherwise:

`sendConfirmationMessage` (`messaging_notification_service.dart:452-461`) only substitutes `{customerName}` and `{amount}` *eagerly*, then passes the partially-rendered body to `sendFormattedMessage` as both `message` and `smsMessageOverride` (line 465-475). Every SMS path through `sendFormattedMessage` reaches `_sendSMSFallback` (lines 138-155 on WhatsApp-failure callback; lines 166-183 on no-WhatsApp), which at lines 214-217 runs the remaining `{balance}`/`{shopName}`/`{customerName}` substitutions on the body before send. The double-pass on `{customerName}` is a no-op idempotent re-substitution.

**No live bug. Customers receive fully-rendered text.** The split-phase substitution is fragile (a future refactor could easily drop one of the two passes) but is not currently broken.

Adjacent finding worth noting (not changing F-4's resolved status): `messaging_notification_service.dart:455` uses `pricingService.smsReminderTemplatePrice` for the **credit** transaction's pre-flight cost. There is a `smsPaymentTemplatePrice` field, suggesting the intent was a per-flow price; whether this matters depends on whether the two RC keys carry different values. The audit team confirmed they are equal today (`USD_SMS_REMINDER_PRICE = USD_SMS_PAYMENT_PRICE = 0.0757`), so this is currently cosmetic but is a footgun if pricing diverges.

### F-5 (MEDIUM) — Order-status bodies (C-5)
- Each body 130-200 chars **and** contains at least one non-GSM-7 character (emoji, `’`, `·`).
- All are UCS-2; lengths put each at **2-3 UCS-2 segments** if sent as SMS.
- Mitigated today: code path reaches Twilio Content SIDs over WhatsApp; the literal body is only Firestore-archived, not SMS-sent. **But:** if a fallback ever flips them to SMS, every order event becomes a 2-3 segment UCS-2 SMS.

### F-6 (MEDIUM) — `forceBoilerplate` overhead on every promo
- `lib/pages/promote/widgets/templates/create_template/force_boilerplate.dart:22` adds `Hello {{customerName}},\n` (10-25 chars after substitution) + `\nKind regards,\nThe {{shopName}} team` (~36 chars after substitution).
- Total fixed overhead per promotion: **~50 chars** before merchant text. On a 110-char merchant body that would have been 1 segment, this guarantees 2 segments.
- Not visible to the merchant in the editor preview unless they scroll the rendered preview card.

### F-7 (LOW) — Dead `creditConfirmation` / `paymentConfirmation` / `onboarding` / `reminder` long fields
- Loaded from RC every app start but never read. Wasted RC bandwidth + maintenance footgun.

### F-8 (LOW) — Segment-calculator GSM-7 mis-classification
- `SMSPricingUtil.calculateSegments` uses `r > 127` as the GSM-7 boundary (§3 item 1). Affects merchant-displayed cost truth, not provider COGS.
- *Note:* this calculator currently agrees with reality on all four live templates (the en-dash and U+00A0 are both `> 127`), so the cost preview is correct today — but it is correct by accident, and the bug will surface when merchants use GSM-7-safe non-ASCII chars in promo templates (e.g. `£`, `É`).

### F-9 (LOW) — `R0.0` vs `R0,00` inconsistency
- `lib/services/message_queue.dart:116` uses `'R0.0'` as fallback for null amount. Other paths use `R0,00`. Cosmetic but breaks the locale-correct currency renderer pattern.

### F-10 (BLOCKING — runtime unknown) — Live `messagingTemplates` Firestore content
- Merchant-promo SMS bodies are Firestore-resident and not visible to this audit. Cannot estimate per-merchant promo segment risk; only the structural `forceBoilerplate` overhead (F-6) is quantifiable.

---

## 5b. Quantified impact summary (live pricing)

Across a representative 16-send sample (4 templates × 4 amount scenarios):

| Configuration | Total segments | Total cost | Δ vs baseline |
|---|---|---|---|
| **Baseline (current production)** | 31 | R53.96 | — |
| + QW-1 currency formatter only (F-2 fixed) | 28 | R48.74 | −R5.22 (−10%) |
| + En-dash → hyphen only (F-1 fixed) | 23 | R40.04 | −R13.92 (−26%) |
| **+ Both fixes (F-1 + F-2)** | **16** | **R27.85** | **−R26.10 (−48%)** |

The two fixes together cut SMS COGS by roughly half on this sample with **zero copy change** — they are pure character-substitution and locale-formatting changes. F-1 alone is a single Remote Config edit (no code deploy required) and accounts for the larger share.

For a merchant sending 1 000 transactional SMSes per month with a workload mix that resembles the sample, the saving is on the order of **R1 600/month per merchant** in raw segment cost.

---

## 6. Quick wins (ordered by ROI, with live-data impact)

### QW-0 — Replace U+2013 EN DASH with ASCII hyphen in three RC values (RC-only edit, no deploy)

**Highest-ROI single change in the whole audit.** No code change, no app release. Edit these three Remote Config values:

- `SMS_CREDIT_CONFIRMATION_SHORT`: change `"– {shopName}"` to `"- {shopName}"`
- `SMS_PAYMENT_CONFIRMATION_SHORT`: change `"– {shopName}"` to `"- {shopName}"`
- `SMS_ONBOARDING_SHORT`: change `"– {shopName}"` to `"- {shopName}"`

Result: every credit/payment confirmation and every onboarding SMS for amounts < R1 000 drops from 2 segments to 1 segment immediately. Saving: **R1.74/send** on every such message. On the 16-send sample: −R13.92 (−26%) by itself.

### QW-1 — Replace `CurrencyUtil.format` callers in SMS substitutions with a GSM-7-safe formatter
Add a helper, e.g. `CurrencyUtil.formatForSms(double amount)` that returns `'R' + amount.toStringAsFixed(2).replaceAll('.', ',')` (no thousands separator, ASCII-only). Use it in:
- `lib/services/messaging_notification_service.dart:454, 461`
- `lib/services/messaging_notification_service.dart:215` (`formattedBalance` computation)
- `lib/services/message_queue.dart:112, 116`

Result: removes the U+00A0 trigger across every transactional SMS. Combined with QW-0: **48% reduction in COGS on the 16-send sample (R53.96 → R27.85).** Also collapses the F-3 reminder 3-segment scenario to 1 segment.

Trade-off: large amounts render without a thousands separator (`R12500,00` vs `R12 500,00`). Acceptable for a 160-char SMS where every character costs money; the merchant-facing UI can keep the formatted version.

### QW-2 — Pre-flight cost UI: surface the segment-trigger reason
In `lib/shared/billing/cost_breakdown.dart` and the create-template wizard preview (`content_step.dart:197-240`):
- Expose `isUnicode` from `SMSPricingUtil` (currently private to the function).
- When `segments > 1` and the body would have fit in 1 segment as GSM-7, identify the offending character class ("contains an emoji, en-dash, or non-breaking space — message will cost X segments instead of 1").
- Detect U+00A0 and U+2013 specifically — both are invisible-looking on most screens and are the two highest-frequency offenders found in this audit.

### QW-3 — Add Remote Config defaults
In `lib/config/remote_config.dart` `setDefaults` map (line 21), add literal defaults for `SMS_CREDIT_CONFIRMATION_SHORT`, `SMS_PAYMENT_CONFIRMATION_SHORT`, `SMS_ONBOARDING_SHORT`, `SMS_REMINDER_SHORT` (using the post-QW-0 ASCII-hyphen versions), and `SMS_TEMPLATE_KEYWORDS = '[]'`. Eliminates the empty-string failure mode if RC fetch fails.

### QW-4 — Fix the substitution gap on credit/payment confirmation (F-4)
Either (a) add `.replaceAll('{shopName}', shopName).replaceAll('{balance}', formattedBalance)` to `messaging_notification_service.dart:452-454` and `:459-461`, or (b) reword the live RC values to drop those two placeholders. Option (a) is safer if `_sendSMSFallback` is *not* on these paths.

### QW-5 — Delete the dead long fields
Remove `creditConfirmation`, `paymentConfirmation`, `onboarding`, `reminder` (and their RC reads) from `lib/templates/sms_message.dart`. Simplifies the contract: "the SHORT key *is* the SMS body."

### QW-6 — Fix the GSM-7 boundary check in `SMSPricingUtil`
Replace `r > 127` with a GSM-7 set membership check (and count GSM-7 extension chars as 2 septets). Aligns merchant-shown cost with carrier-billed cost for non-ASCII GSM-7 chars and for `€`/`{`/`}`/`[`/`]`/`~`/`|`/`^`/`\`. Also makes the QW-2 UI explanation possible.

### QW-7 (optional) — Reminder copy A/B
The current live `SMS_REMINDER_SHORT` is already short enough to be 1 GSM-7 segment after QW-1; no rewrite is needed for cost. If the team wants to add behavioural-economics social-proof copy ("90% of customers settle on time…"), do it as a deliberate 2-segment choice with a tracked A/B against the current 1-segment version. **Do not add it silently** — the segment cost matters at scale.

---

## 7. Justified exceptions / clarity-cost trade-offs

- **En-dash vs hyphen (QW-0):** the current `–` looks slightly more polished in WhatsApp/email contexts. On SMS, customer handsets render U+2013 inconsistently (some as en-dash, some as `?`, some as a slim dash). The merchant-clarity gain of keeping U+2013 over `-` is essentially zero on SMS while the cost penalty is 100% (every send becomes 2 segments). **Recommendation: replace.**
- **Reminder copy:** the current live `SMS_REMINDER_SHORT` is already concise and stays within 1 GSM-7 segment after QW-1. No copy reduction needed. If product wants social-proof framing later, treat it as a deliberate 2-segment investment with measurement.
- **Onboarding `R0,00` literal:** keep the literal. Making it dynamic would route through the broken currency formatter and re-introduce U+00A0 risk for the welcome message.
- **Order-status emoji (C-5, F-5):** as long as these stay on WhatsApp, the emoji are clarity-positive (✅ for received, 📦 for collected). Do **not** strip them. If/when an SMS fallback path is added, build a parallel emoji-free SMS body — do not just send the WhatsApp body over SMS.
- **`forceBoilerplate` greeting/sign-off:** removing it would save ~50 chars but breaks merchant brand voice consistency. **Recommendation: keep**, but surface its segment cost in the live editor preview (QW-2).

---

## 8. Risks / unknowns

- **Live `messagingTemplates` Firestore content:** unknown. Cannot estimate per-merchant promo segment risk; only the structural `forceBoilerplate` overhead (F-6) is quantifiable.
- **Substitution gap (F-4):** `{shopName}`/`{balance}` placeholders exist in the live `SMS_CREDIT_CONFIRMATION_SHORT` and `SMS_PAYMENT_CONFIRMATION_SHORT` strings but the dedicated render path at `messaging_notification_service.dart:452-461` does not substitute them. Verify with a live device or Firestore-archived `renderedMessage` whether the literal `"{shopName}"`/`"{balance}"` is reaching customers, or whether `_sendSMSFallback` is also on the path.
- **`RemoteConfigService.getString` returning `''`:** every `_SHORT` key still has no local default. `_sendSMSFallback` does not guard against `messageBody == ''` before calling `twilioFlutter.sendSMS`. Reliability bug — Twilio behaviour on empty body unverified.
- **Twilio segment counting parity:** Twilio's billing rounds segments using its own rules (including UDH headers eating 6 septets per multipart segment). `SMSPricingUtil` does not subtract UDH overhead — billed cost can exceed displayed cost on borderline-multipart messages by ~10%. Live billing from Twilio logs would close this gap.
- **`MARKUP_SMS_PERCENTAGE = 26`:** the live unit cost (R1.74/segment) is computed assuming markup is applied as a multiplier on USD × FX. If the markup is actually applied differently in production (e.g. on a cents basis, or only for certain merchant tiers), the rand savings figures in §5b scale linearly but the percentage savings hold.
- **Surrogate-pair length math:** `String.length` returns UTF-16 code units; `r > 127` walks runes. The two are inconsistent. For BMP-only Unicode this is fine; for non-BMP emoji the length math happens to align with UCS-2 wire encoding. Document this as load-bearing in any rewrite of `SMSPricingUtil`.

---

## 9. Status

- **Implemented:**
  - Audit artifact (this doc) and full inventory of in-repo SMS body sources.
  - Segment-risk classification per template against live RC values + live pricing inputs.
  - **QW-1 code change shipped on this branch:** `CurrencyUtil.formatForSms` plus all SMS-substitution callsites routed through it (`messaging_notification_service.dart`, `message_queue.dart`). WhatsApp + UI paths intentionally untouched.
  - **QW-0 RC change-set ready to publish:** see `docs/openclaw/pas-sms-01-rc-changeset.md` for the exact strings, verification steps, and rollback path.
  - Unit test coverage for the new formatter (`test/currency_util_sms_test.dart`) including an end-to-end 1-segment GSM-7 assertion against the post-QW-0 reminder skeleton.
- **Verified:**
  - Every code-grounded claim cites file and line. Live RC values for the four `SMS_*_SHORT` keys snapshotted 2026-05-10 and run through a faithful GSM-7 / UCS-2 segmentation simulation against the production pricing inputs (USD 0.0757 × ZAR 18.25 × 1.26 markup = R1.74/segment).
  - F-4 (substitution gap) traced end-to-end and resolved as false alarm — `_sendSMSFallback` runs the missing substitutions on every SMS path.
  - Quantified savings: **48% COGS reduction** on the 16-send representative sample with QW-0 + QW-1 combined.
- **Blocked:**
  - Per-merchant promo segment claims pending a snapshot of active `messagingTemplates` Firestore docs.
  - Twilio billing parity pending a sample of billed segment counts from production logs.
  - Production effect of QW-0 cannot be measured until the RC change is published.
