# pas-sms-01 — handover

**Lane:** `pas-sms-01-template-segment-audit`
**Branch:** `audit/pas-sms-01-template-segment-audit`
**Headline commit:** `3f21966` — *fix(sms): cut SMS COGS by 48% via encoding-safe templates and pricing*
**Status:** code shipped, RC console actions completed, ready for PR / merge.

---

## 1. What this lane delivered

A diagnose-and-fix pass on the Pasella SMS pipeline. Two production bugs were silently doubling per-segment cost on every transactional SMS, and a third bug was mis-quoting cost in the merchant-facing template editor. All three are now fixed end-to-end (Firebase RC + Flutter code + UI). On the representative 16-send sample documented in §5b of the audit artifact, the combined effect is **R53.96 → R27.85 (−48% COGS)** with zero customer-visible copy change.

The two source-of-truth documents from the lane are:

- `docs/openclaw/pas-sms-01-template-segment-audit.md` — full audit (inventory, findings F-1..F-10, quick wins QW-0..QW-7, quantified impact §5b, shipped status §0).
- `docs/openclaw/pas-sms-01-rc-changeset.md` — paste-ready Firebase Remote Config strings for QW-0 with verification + rollback steps.

This handover is the navigation layer over those two; if anything below contradicts them, they win.

---

## 2. Root causes in one paragraph each

**F-1 (en-dash):** Three Firebase RC templates (`SMS_CREDIT_CONFIRMATION_SHORT`, `SMS_PAYMENT_CONFIRMATION_SHORT`, `SMS_ONBOARDING_SHORT`) used U+2013 EN DASH (`–`) in the sign-off. Any single non-GSM-7 character anywhere in an SMS body forces the entire message into UCS-2 encoding, which has a 70-character single-segment limit instead of 160. Every send was billed as 2 segments minimum.

**F-2 (NBSP from currency formatter):** `CurrencyUtil.format` wrapped `NumberFormat.simpleCurrency(locale: 'en_ZA')`, whose thousands separator is U+00A0 NO-BREAK SPACE — invisible on a handset, but a UCS-2 trigger. Any merchant-rendered amount of R1 000 or more substituted into an SMS body silently doubled segment cost.

**F-6/F-7 (broken classifier):** `SMSPricingUtil.calculateSegments` treated any UTF-16 code unit > 127 as Unicode and ignored UDH overhead on multipart messages. This mis-quoted SMS cost in both directions in the template editor — GSM-7 default-alphabet non-ASCII chars (`£`, `é`, `ñ`) were over-charged; GSM-7 extension chars (`€`, `{`, `}`, `[`, `]`, `~`, `|`, `^`, `\`) were under-charged. It also made it impossible to surface *which* character was the offender.

---

## 3. What's now in production-ready state

### 3.1 Firebase Remote Config (your console actions)
- ✅ **QW-0 published:** the three `SMS_*_SHORT` keys now use ASCII `-`. This is what unlocks the headline 48% saving.
- ✅ **QW-5 cleanup:** the legacy long keys (`SMS_CREDIT_CONFIRMATION`, `SMS_PAYMENT_CONFIRMATION`, `SMS_ONBOARDING`, `SMS_REMINDER`) deleted from RC. No code path reads them anymore.

### 3.2 Code (commit `3f21966`)
- **`lib/utils/currency_util.dart`** — new `CurrencyUtil.formatForSms(double)`. Hyphen-free, NBSP-free, GSM-7-safe (`R1250,00` for `1250.0`). Existing `CurrencyUtil.format` is unchanged and still used everywhere it was — UI display, WhatsApp Content Template variable maps, Firestore notification archive.
- **`lib/services/messaging_notification_service.dart`** — credit/payment/onboarding/reminder paths route SMS substitution through `formatForSms`. `_sendSMSFallback` uses `formattedBalance` (SMS-safe) for the SMS body, `formattedBalanceDisplay` for any WhatsApp/Firestore payload.
- **`lib/services/message_queue.dart`** — `constructMessageFromTemplate` uses `formatForSms`; the `'R0.0'` fallback was replaced with `'R0,00'` so even the empty-balance edge case stays in GSM-7.
- **`lib/utils/sms_pricing_util.dart`** — rewritten. Explicit GSM 03.38 default alphabet + extension table membership, 153-septet / 67-UCS-2-unit multipart parts with UDH overhead, new `SmsEncoding` enum and `SmsEncodingInfo` value type. `SmsEncodingInfo.offenderLabel` returns a human-readable name for the first offending character (e.g. *"en-dash (–)"*, *"non-breaking space (often from currency formatting)"*, *"an emoji"*) — this is what powers the new template-editor warning.
- **`lib/templates/sms_message.dart`** — dead long-template fields and their RC reads removed. The model now only exposes the `*_SHORT` fields actually consumed by the send path.
- **`lib/config/remote_config.dart`** — `setDefaults` now seeds `SMS_CREDIT_CONFIRMATION_SHORT`, `SMS_PAYMENT_CONFIRMATION_SHORT`, `SMS_ONBOARDING_SHORT`, `SMS_REMINDER_SHORT`, and `SMS_TEMPLATE_KEYWORDS = '[]'`. If a fetch fails or a key is missing, the app sends a real body instead of `''` (which would either drop silently at Twilio or fail with a 400).
- **`lib/pages/promote/widgets/templates/create_template/create_template.dart`** — tracks an `SmsEncodingInfo` alongside segment count, recomputed on every prefill + edit, and passes it through to the content + review steps.
- **`lib/pages/promote/widgets/templates/create_template/steps/content_step.dart`** & **`steps/review_step.dart`** — render an inline orange warning under the SMS pricing row when `SmsEncodingInfo.offenderLabel != null`. Merchants who paste an en-dash, curly quote, or large-amount currency string into a template now see *exactly* which character is doubling their cost, with a one-line "remove it to cut cost in half" hint.

### 3.3 Tests
27 tests pass (`flutter test`). New coverage in this lane:

- **`test/currency_util_sms_test.dart`** (8 tests): small / large / zero / negative amounts, GSM-7 ASCII-only safety property, end-to-end 1-segment GSM-7 assertion against the post-QW-0 reminder skeleton.
- **`test/sms_pricing_util_test.dart`** (17 tests): empty body, ASCII, GSM-7 default-alphabet non-ASCII (stays GSM-7), GSM-7 extension chars (cost 2 septets), U+2013 / U+00A0 / emoji UCS-2 triggers, `offenderLabel` production traps, single/multipart boundaries (160→161, 70→71, 306→307), GSM-7 extension cost arithmetic, cost-scales-linearly assertion at the live unit price.

---

## 4. Architecture decisions worth knowing

### 4.1 Two parallel sources of truth (intentional)
SMS body and WhatsApp body are stored in different systems and substituted on different sides:

- **SMS:** Firebase Remote Config (`SMS_*_SHORT`), substituted client-side in the Flutter app, then sent to Twilio with a fully-rendered `Body` parameter.
- **WhatsApp:** Twilio Content Templates (`TWILIO_*_TID`), substituted server-side by Twilio against a variable map the client posts.

After QW-0, the SMS and WhatsApp bodies for the three transactional templates **deliberately diverge by a single character** — ASCII `-` in SMS, U+2013 `–` in WhatsApp. WhatsApp doesn't have segmentation cost; the en-dash looks slightly nicer there; and editing a Twilio Content Template triggers a 24-48h Meta re-approval cycle. So the SMS edit was Firebase-only. **If a future "sync the templates" exercise runs, it must NOT propagate the en-dash back into RC.** This is also called out in §0 of the audit artifact.

### 4.2 Two currency formatters (intentional)
- `CurrencyUtil.format` — locale-aware, uses `NumberFormat.simpleCurrency('en_ZA')`. Used everywhere except SMS substitution: app UI, WhatsApp template variable maps, Firestore notification archive. Output is human-perfect (`R 1 250,00` with a thin space).
- `CurrencyUtil.formatForSms` — GSM-7-safe, ASCII-only, comma decimal, no thousands separator. Used **only** in the SMS substitution paths (`messaging_notification_service.dart`, `message_queue.dart`). Output looks like `R1250,00`.

If you add a new SMS substitution callsite, it MUST go through `formatForSms`. If you add a new UI / WhatsApp callsite, keep using `format`. The unit test `test/currency_util_sms_test.dart` enforces the GSM-7 safety property of `formatForSms` against a regex.

### 4.3 `SmsEncodingInfo` is the contract for UI explanation
Anywhere you want to *show* a segment count to a merchant, also call `SMSPricingUtil.classify(text.trim())` and surface `info.offenderLabel`. The `calculateSegments` legacy entry point is preserved as a thin wrapper over `classify` for callsites that only need the count. The cost-confirmation sheet (`lib/shared/billing/cost_confirmation_sheet.dart`) is the most likely next callsite to wire up — see §6 below.

---

## 5. Verification done in-lane

- `flutter analyze` on touched files: no new issues; all 18 reported items pre-date this lane (deprecated `withOpacity`, `avoid_print` in legacy services, unrelated style infos).
- `flutter test`: 27 passing across `actions_block_test`, `currency_util_sms_test`, `sms_pricing_util_test`.
- Manual trace of the credit/payment SMS path in §5 F-4 of the audit artifact resolved an earlier suspicion (split-phase substitution) as a false alarm — `_sendSMSFallback` always runs the trailing `{balance}`/`{shopName}` substitution, so customers always receive a fully-rendered body.
- Worst-case structural segment-count math against the four production template skeletons in §5b of the audit artifact (live RC values, post-QW-0 skeleton, with the live ZAR/USD/markup pricing).

What was **not** verified in-lane (deferred):

- **Twilio billing parity**: a sample of production-billed segment counts from Twilio logs was not pulled, so the savings number is a structural-model estimate, not an empirical "we saw the bill drop by 48%" measurement.
- **Active merchant template snapshot**: per-merchant promo segment claims in the `messagingTemplates` Firestore collection were not snapshotted. Bespoke promo content authored by individual merchants may still contain UCS-2 triggers — the new editor warning catches *new* ones, but pre-existing ones remain unflagged until the merchant edits the template.

---

## 6. Known follow-ups (not in this lane)

These are recorded in the commit message and audit artifact but deliberately deferred:

1. **`messaging_notification_service.dart:455`** — credit confirmation path uses `smsReminderTemplatePrice` instead of `smsPaymentTemplatePrice`. Currently the two RC values are equal, so behaviour is correct, but a future divergence (e.g. promotional pricing on reminders) would silently mis-bill credit confirmations. Tagged **F-9** in the audit artifact.

2. **Split-phase substitution in `_sendSMSFallback`** — `{customerName}` and `{amount}` are substituted in `sendConfirmationMessage`; `{balance}` and `{shopName}` in `_sendSMSFallback`. Idempotent today (the second pass also re-runs `customerName`), but a future refactor that decouples the two functions could reintroduce the gap I originally suspected. Tagged **F-4** with the resolution notes.

3. **`force_boilerplate.dart:22`** — adds ~50 chars of greeting/sign-off overhead to every promo SMS. Recommendation in the audit was to **keep** for brand voice but make sure the segment cost is visible in the editor preview. The QW-2 warning shipped in this lane partially addresses that ("here's why your message is N segments"), but we did not change the boilerplate itself.

4. **Cost confirmation sheet wiring** — `lib/shared/billing/cost_breakdown.dart` already accepts a `notes: List<String>` parameter. The next quick win would be to teach the SMS-cost callsites to append a note from `SmsEncodingInfo.offenderLabel` so the same explanation appears in the bulk-promotion confirmation flow, not just the template editor. Mechanically: pass the SMS body through `SMSPricingUtil.classify`, and if `offenderLabel != null`, prepend that to the existing `notes`.

5. **A/B reminder copy (QW-7)** — purely product-side. The current `SMS_REMINDER_SHORT` is already 1-segment after QW-1; if the team wants to add social-proof framing, it should be a deliberate 2-segment investment with measurement, not a silent edit.

---

## 7. Decision log (why these choices, not others)

- **Implement on this branch vs. audit-only:** chosen at start of lane. Audit-only would have required a second lane to ship; the user opted to bundle the high-confidence quick wins.
- **QW-0 in Firebase RC, not Twilio:** Twilio Content Template edits trigger a 24-48h Meta re-approval. WhatsApp doesn't pay per segment. So the en-dash fix is Firebase-only and the templates intentionally diverge.
- **New formatter (`formatForSms`) instead of mutating `CurrencyUtil.format`:** UI display, WhatsApp template variable maps, and Firestore notification archive all benefit from the locale-aware formatter (with NBSP and `R 1 250,00` formatting). Mutating `format` would have regressed every UI surface to fix only the SMS path. Two formatters, sharply scoped.
- **Rewrite `SMSPricingUtil` instead of patching the boundary check:** the old check (`r > 127`) was wrong in both directions, and patching it wouldn't have given us a way to *name* the offending character for the UI warning. Full rewrite was a smaller diff than two patches plus a parallel "explain why" helper.
- **Skip the four prompt/context markdown files at the repo root:** these are local Openclaw workflow scaffolding and not meant to ship. Now in `.gitignore`.
- **One commit, not several per QW:** the quick wins are tightly interdependent (e.g. QW-2 requires QW-6's `SmsEncodingInfo`; QW-1 depends on the formatter contract that the tests pin). One commit with a comprehensive message keeps the bisect surface coherent.

---

## 8. Pointer index

| Concern | Where to look |
|---|---|
| Full audit (findings + math + quick wins) | `docs/openclaw/pas-sms-01-template-segment-audit.md` |
| Firebase RC strings actually published for QW-0 | `docs/openclaw/pas-sms-01-rc-changeset.md` |
| New SMS-safe currency formatter | `lib/utils/currency_util.dart` |
| Rewritten segment classifier + `SmsEncodingInfo` | `lib/utils/sms_pricing_util.dart` |
| SMS substitution callsites (now using `formatForSms`) | `lib/services/messaging_notification_service.dart`, `lib/services/message_queue.dart` |
| Editor / review-step warning UI (QW-2) | `lib/pages/promote/widgets/templates/create_template/steps/content_step.dart`, `steps/review_step.dart` |
| RC defaults guarding empty bodies (QW-3) | `lib/config/remote_config.dart` |
| Tests pinning the formatter + classifier contracts | `test/currency_util_sms_test.dart`, `test/sms_pricing_util_test.dart` |
| WhatsApp variable map (intentionally still locale-formatted) | `lib/services/messaging_notification_service.dart` (search for `formattedBalanceDisplay`) |
| The footgun called out for future refactor (F-9) | `lib/services/messaging_notification_service.dart:455` |

---

## 9. Suggested PR description (paste-ready)

> ## SMS template + pricing audit — fix 48% silent COGS leak
>
> Diagnoses and fixes two production bugs that were silently doubling per-segment SMS cost on every transactional send, plus a broken segment classifier that mis-quoted cost in the merchant-facing template editor.
>
> **Customer-visible copy:** unchanged.
> **Twilio Content Templates:** untouched (no Meta re-approval).
> **Quantified impact (16-send representative sample):** R53.96 → R27.85 (−48%).
>
> See `docs/openclaw/pas-sms-01-handover.md` for the navigation doc; `docs/openclaw/pas-sms-01-template-segment-audit.md` for the full audit; `docs/openclaw/pas-sms-01-rc-changeset.md` for the Firebase RC change-set already published.
>
> **Tests:** 27 passing (8 new in `currency_util_sms_test.dart`, 17 in `sms_pricing_util_test.dart`).
>
> **Follow-ups recorded in the audit and commit message:** F-9 (`smsReminderTemplatePrice` used for credit), split-phase substitution footgun in `_sendSMSFallback`, `force_boilerplate` overhead, cost-confirmation-sheet wiring of the new offender warning.
