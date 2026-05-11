# PAS-UX-01 Implementation Handover

**Branch:** `ux/pas-ux-01-implementation` in `pasella-app` (off `main` @ `b86c2c8`)
**Status:** Local only, not pushed.
**Scope:** Phase 1 + 2 + 3 of the audit recovery roadmap. 16 commits, one per slice (PAS-UX-06 deliberately scoped down — see decisions).
**Verification:** `flutter analyze` baseline holds at 414 pre-existing info/warn issues across all 16 commits; 0 net-new issues introduced. No real-device verification (PAS-UX-18 blocked).

---

## Commit log (oldest first)

```
e4681dd PAS-UX-03  send-confirmation truth pack
a40e821 PAS-UX-07  destructive-action guard on Delete Customer
5c950ec PAS-UX-08  SA-only phone validator copy unified
0525216 PAS-UX-04  empty Stock tab onboarding rebuild
3e00b2f PAS-UX-05  product upload safety nets + unsaved-changes guard
e52eae0 PAS-UX-09  collapse Run Promotion launch into single launcher
cc7df88 PAS-UX-10  Settings trust polish
497c785 PAS-UX-02  first-session aha checklist on LedgerPage
df4439b PAS-UX-11  surface saved-but-unsent promotions on the list
0801edb PAS-UX-06  Templates 'Use this template' shortcut
3892a03 PAS-UX-12  collapse wallet repayment FutureBuilder fan-out
3f54a68 PAS-UX-13  orders search debounce + cached server result
2b1baac PAS-UX-14  anonymous gate hoisted to screen edge
f6bd37d PAS-UX-15  SaleDetail batch product lookup
a46636c PAS-UX-16  product + customer CRUD telemetry parity
05de4ca PAS-UX-17  filename hygiene + dead code removal
```

---

## Per-slice summary

### Phase 1 — visible-trust slices

**PAS-UX-02 — first-session checklist (`497c785`)**
- New: `lib/shared/widgets/onboarding/onboarding_checklist.dart` mounted on `LedgerPage`.
- Manual ticks (auto-detection deferred to PAS-UX-16 telemetry).

**PAS-UX-03 — send-confirmation truth pack (`e4681dd`)**
- New `CostSheetOutcome` tri-state enum (send / silent / cancel) replaces bool.
- `CostConfirmationSheet.showOutcome(...)` is the canonical API; legacy `show()` retained as shim.
- Cost sheet now quotes both WhatsApp + SMS prices when both are possible (delivery channel decided post-confirm) so the deduction can never surprise.

**PAS-UX-04 — Stock empty-state (`0525216`)**
- Empty Stock tab now an onboarding moment with explicit primary CTA, not a passive blank.

**PAS-UX-05 — product upload safety (`3e00b2f`)**
- Margin warning when `sellingPrice <= cost`.
- Quantity validator rejects negatives.
- `PopScope` blocks back-nav with unsaved changes (form keeps its own `Form`; full migration to `transaction_form_scaffold` deferred — `GlobalKey` conflict).

**PAS-UX-07 — Delete Customer guard (`a40e821`)**
- Wraps the destructive flow in `ConfirmDialog.showDestructive` (canonical helper).

**PAS-UX-08 — SA-only validator copy (`5c950ec`)**
- Centralised `kSAOnlyPhoneMessage` constant; every callsite now uses the same wording.

**PAS-UX-09 — Run Promotion launcher (`e52eae0`)**
- New `RunPromotionLauncher.launch(...)` in `lib/pages/promote/utils/`. Single entry for every "send a promotion" affordance. `templateStatusOf` is the canonical approval reader.

**PAS-UX-10 — Settings trust polish (`cc7df88`)**
- Privacy URL via `lib/constants/app_urls.dart` indirection so the destination can change without touching every screen.

### Phase 2 — performance + safety slices

**PAS-UX-11 — saved-promo surfacing (`df4439b`)**
- "Tap to review and send" hint + pending-send chip in `promotions_tab.dart` for promotions that were saved but never sent.

**PAS-UX-06 — Templates 'Use this template' (`0801edb`)** *(scope reduced)*
- Adds a CTA on `TemplateDetailPage` (only when `status.isUsable`).
- `RunPromotionPage` accepts `initialTemplateId`, applied in `initState`.
- `RunPromotionLauncher.launch` grows the param.
- **Out of scope by user decision:** Save+Send merge, Step-3 collapse, post-send snackbar redesign, dead `RunPromotionPage.edit()` wiring (later removed in PAS-UX-17).

**PAS-UX-12 — wallet FutureBuilder fan-out (`3892a03`)**
- New `WalletBreakdown` value type + `WalletUtils.computeBreakdown` (parallel `Future.wait`).
- Consumers collapsed: `full_repayment_report.dart` 3→1, `suspension_paywall.dart` 4→1 (became StatefulWidget), `wallet.dart` repayment card + bottom sheet 4→2.
- `WalletBreakdown.loading` placeholder mirrors the legacy `'...'` cadence so visuals are unchanged.
- **Deferred:** `WalletViewModel` `ChangeNotifierProvider` hoisting — every tab `new`s its own with internal listeners; needs a separate state-machine slice.

**PAS-UX-13 — orders search debounce + cache (`3f54a68`)**
- 350 ms `Timer` debounce.
- `_allOrders` cache; `_loadOrders({forceServer})` only hits the Cloud Function on first build / pull-to-refresh.
- Status / range / query changes are pure-local `applyClientFilters`.
- Safe because `OrdersRepository.fetchCustomerOrders` only varies by `customerId` (fixed for page lifetime).

**PAS-UX-14 — anonymous gate at screen edge (`2b1baac`)**
- New `gateAndPush(context, push: () => …)` helper in `lib/utils/auth_util.dart`.
- Wraps Add Credit + Add Payment pushes in `action_buttons.dart`.
- `RunPromotionLauncher.launch` runs `isAnonymousGate` before the approval check.
- Submit-time gates retained as defense-in-depth.
- Adds two `use_build_context_synchronously` infos in `gateAndPush` lines 70–71; guarded by `context.mounted` but the analyzer can't see through the closure capture. Pattern is correct.

**PAS-UX-15 — SaleDetail batched product lookup (`f6bd37d`)**
- Single `_productsFuture` in `initState`, chunks at the Firestore 30-element `whereIn` cap.
- Replaces N per-product FutureBuilders with one map-keyed render.

### Phase 3 — observability + hygiene

**PAS-UX-16 — CRUD telemetry parity (`a46636c`)**
- 7 new typed events in `lib/services/analytics_event.dart`: `ProductCreated`, `ProductUpdated`, `ProductDeleted`, `CustomerCreated`, `CustomerCreateBlocked` (sub-event for duplicate-number rejections), `CustomerUpdated`, `CustomerDeleted`.
- Properties are coarse buckets only — group, ZAR price bucket via `amountBucketZAR` helper, `has_image`. **No** product or customer names, **no** free-form merchant data.
- Wired at the VM CRUD boundary in `product_view_model.dart` (saveProduct branches on `docID`; deleteProduct reads `group` BEFORE deletion so the event can carry it without an extra round-trip), `add_contact_view_model.dart` (CustomerCreated + duplicate-number CustomerCreateBlocked), `customer_management_view_model.dart` (CustomerUpdated `hasImage` reflects whether THIS edit attached a new image, not lifetime state; CustomerDeleted).
- All `capture()` calls fire-and-forget (`// ignore: unawaited_futures`) so telemetry can never block the UI / navigator.

**PAS-UX-17 — hygiene (`05de4ca`)**
- Renamed `lib/pages/wallet/widgets/suspenstion_paywall.dart` → `suspension_paywall.dart`. Updated lone import in `dashboard.dart`.
- Removed dead `RunPromotionPage.edit` named constructor + unused `promoToEdit` field. Grep across `lib/` + `test/` found zero callsites; State never read it. Comment block in the file records rationale so it doesn't get speculatively re-added.

---

## Key architectural decisions

- **Canonical helpers introduced** — these are the new single sources of truth, do not duplicate:
  - `CostSheetOutcome` + `CostConfirmationSheet.showOutcome` (PAS-UX-03)
  - `ConfirmDialog.showDestructive` (PAS-UX-07)
  - `kSAOnlyPhoneMessage` constant (PAS-UX-08)
  - `RunPromotionLauncher.launch` (PAS-UX-09)
  - `templateStatusOf` + `.isUsable` (PAS-UX-09 / PAS-UX-06)
  - `AppUrls.*` indirection (PAS-UX-10)
  - `WalletBreakdown` + `WalletUtils.computeBreakdown` (PAS-UX-12)
  - `gateAndPush` (PAS-UX-14)
  - `amountBucketZAR` (PAS-UX-16)
- **PAS-UX-06 nav model:** TemplateDetailPage stays in stack underneath the wizard so cancel returns to preview; deliberately do NOT auto-pop after send.
- **PAS-UX-13:** filtering moved fully client-side because `fetchCustomerOrders` only varies by `customerId`. If that changes, revisit.
- **PAS-UX-14:** prefer the screen-edge `gateAndPush` for new affordances; submit-time gates kept as cheap defense-in-depth (catches mid-session status change).
- **PAS-UX-15:** chunk `whereIn` at 30 defensively even though merchants rarely break 10 line items.
- **PAS-UX-16:** instrument at the VM CRUD boundary, never the UI — exceptions are swallowed there. Never capture names or free-form text.

---

## What was deliberately NOT done

- **PAS-UX-06 reduced scope** (user choice): no Save+Send merge, no Step-3 collapse, no post-send snackbar redesign.
- **PAS-UX-12 deferred:** `WalletViewModel` `ChangeNotifierProvider` hoisting. Each wallet tab still `new`s its own VM with internal listeners. Needs a state-machine slice of its own.
- **PAS-UX-05 deferred:** `ProductForm` migration onto `transaction_form_scaffold` (GlobalKey conflict).
- **PAS-UX-18 blocked:** real-device verification. No live build / seeded merchant in this session. Recommend running through the merchant onboarding funnel (signup → first product → first customer → first sale → first message) on a physical device with the new telemetry events captured to confirm the funnel reads end-to-end.

---

## Risk surface for review

1. **PAS-UX-03 cost sheet** changed every send-confirmation callsite. Audit the legacy `show()` shim usages — they should all be migrated to `showOutcome` or accept the bool fallback consciously.
2. **PAS-UX-13 caching** assumes `fetchCustomerOrders` is pure with respect to `customerId` only. Adding any new server-side filter to that repo method will silently break the cache.
3. **PAS-UX-14 `gateAndPush`** uses `context.mounted` after async; analyzer can't verify through the closure. Verified correct manually but worth a second pair of eyes.
4. **PAS-UX-16 fire-and-forget telemetry.** If the analytics SDK ever throws synchronously from `capture()` it will surface as an unhandled async error. Confirm the `TelemetryService` swallows internally before relying on this.

---

## Files of note

- Audit packet: `docs/openclaw/pas-ux-01-merchant-audit.md`
- Telemetry: `lib/services/analytics_event.dart`, `lib/services/telemetry_service.dart`
- Stock VM: `lib/pages/stock/view_model/product_view_model.dart`
- Contact VMs: `lib/pages/contact/view_model/{add_contact_view_model,customer_management_view_model}.dart`
- Promo wizard + launcher: `lib/pages/promote/widgets/promotions/create_promotions/run_promotion_page.dart`, `lib/pages/promote/utils/run_promotion_launcher.dart`
- Wallet shared types: `lib/utils/wallet_utils.dart`
- Auth gate: `lib/utils/auth_util.dart`
- Cost sheet: `lib/shared/billing/{cost_sheet_outcome.dart,cost_confirmation_sheet.dart,cost_breakdown.dart}`

---

## Next session resumption checklist

1. `cd pasella-app && git checkout ux/pas-ux-01-implementation`
2. `git log --oneline main..HEAD` should show 16 commits ending at `05de4ca`.
3. `flutter analyze` should report 414 issues, 0 errors.
4. Push when ready: `git push -u origin ux/pas-ux-01-implementation`.
5. Open PR; recommend it stays a single PR (audit is one logical recovery, slice-per-commit is the review unit).
6. Run PAS-UX-18 verification on device after merge: walk the onboarding funnel and confirm telemetry events fire in order.
