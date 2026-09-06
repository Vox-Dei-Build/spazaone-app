# Redesign and Crashlytics fixes — 6 September 2026

Implemented locally alongside the approved approachable design and neutral
palette. No commit, push, deployment, app-version change, or production data
mutation was performed.

## Product return: missing catalogue provider

The supplied stack identifies `_StockPageState._openNewProduct` reading
`WhatsAppCatalogStatusController` from a context above its provider after the
Add Product route closes. Released client commit `7ef9a45` contains that exact
code. It also resets the tab controller before checking whether its state is
still mounted.

The stock workspace state now lives below its owned providers. Both Add actions
capture the existing catalogue controller before navigation, then check
`mounted` before resetting tabs or refreshing. The catalogue controller ignores
late request completions and further refresh requests after disposal.

The catalogue summary scrolls with the product list. Server status, refresh,
support and edit actions remain available, with stock warnings shown separately.
The Products preview demonstrates these states with synthetic data.

Sources: [stock workspace](../lib/pages/stock/stock.dart),
[catalogue controller](../lib/services/whatsapp_catalog_status_service.dart),
[navigation regressions](../test/stock_catalog_navigation_test.dart).

## OTP prompt: removed screen context

The supplied stack goes from `lookupAndRoute` through the OTP callback to
`Navigator.of` using a detached `StatefulElement`. The shared dialog now returns
without navigation when its context is unmounted. The number-first flow checks
its lifetime after lookup and verification waits, ignores late callbacks after
leaving/cancelling, and releases pending work on disposal. Loading updates cannot
notify a disposed model.

Once Firebase has accepted a registration, minimum user/referral and wallet
initialization still finishes using `UserCredential.user`, even if the screen
closes during sign-in. Only prompt/navigation work stops. Active registrations
continue to Finish Profile; existing users continue to Dashboard. Manual
verification rechecks its state after telemetry so an automatic result cannot
cause a second prompt pop.

Sources: [auth view model](../lib/pages/auth/view_model/auth_view_model.dart),
[shared OTP dialog](../lib/pages/auth/widgets/otp_code_dialog.dart),
[lifecycle regressions](../test/auth_otp_lifecycle_test.dart).

## Released client features retained

This redesign worktree starts at `1672538`, before the catalogue/PDF client
feature in `7ef9a45` (present in local `authority/main` at `b1309da`). The necessary
released client sources, configuration flags and pinned dependencies were
integrated without overwriting the redesigned presentation or recorded-sales
reader. Dependency resolution completed offline using the released lockfile.

PDF invoice picking, validation, private storage access, rendering, retry and
failure telemetry remain supported. Replacing an invoice now derives its type
from the selected local file; old uploaded metadata is retained for cleanup but
cannot mislabel the replacement as PDF/image. Tests cover PDF to PNG, PDF to
JPEG, and JPEG to PDF.

Newer backend, deployment tooling, Firestore/storage rules and infrastructure
were **not** copied into this older worktree. Before any release, integrate these
client changes on the current Vox Dei authority revision while retaining its
backend lineage. This checkout's older backend tree is not a release source for
the newer catalogue backend.

## Verification

- Full Flutter suite: **661 passed, 1 failed**. The sole failure remains
  `firebase_qa_configuration_test.dart` because the ignored local preview `.env`
  has no operational Firebase identity (expected `pasella-ledger`, actual null).
  The test is unchanged and enabled.
- Focused auth checks: **23 passed**, including late code/automatic callbacks,
  cancellation, route removal, accepted registration after disposal, active
  manual/automatic login, registration routing and responsive auth layouts.
- Catalogue checks: **73 passed** across navigation, disposal, service/cache,
  status actions, flag/telemetry contracts and presentation/previews.
- Invoice/recorded-sales checks: **23 passed**, including replacement types.
- Static analysis of **214 changed/new Dart files**: **0 errors, 0 warnings**;
  74 informational lints remain. Formatting and whitespace checks passed.
- Release web preview built successfully; browser review confirmed the restored
  catalogue summary and product statuses within the neutral design. Native Firebase authentication,
  file picking and PDF rendering were not exercised by the synthetic preview.

Before release, use a configured development build to verify delayed OTP after
Back/route removal, manual and Android automatic verification, new-account
profile routing, Add Product save/Back, catalogue refresh after leaving the
workspace, and native image/PDF picking/rendering/replacement. Production crash
closure requires evidence from a subsequent released build, not only local tests.
