# Codex QA Handover — Pasella Combined Release

## Release under test

- Branch: `release/pasella-onboarding-whatsapp-2026-06-18`
- Worktree: `/Users/admin/Sites/vox-dei/pasella-app-worktrees/release-onboarding-whatsapp-2026-06-18`
- Base: `2b486df` (`v4.0.3+57`)
- Combined commits:
  - `3e3b014` — number-first authentication flow
  - `35fd7da` — onboarding CTA opens add-product flow
  - `73f0467` — WhatsApp-listed products require an image
- Running device detected: Android emulator `emulator-5554` (Android 16 / API 36)

Do not test the three source worktrees independently. Test this combined release branch so integration and navigation interactions are covered.

## Environment setup

The release worktree does not contain the ignored `.env` file, so Flutter test/build currently stops with:

`No file or variants found for asset: .env`

Use the existing ignored `.env` from `/Users/admin/Sites/vox-dei/pasella-app/.env` without printing or inspecting its contents. Keep it untracked and confirm it is not added to Git.

Use FVM for every Flutter command:

```sh
fvm flutter pub get
fvm flutter test test/phone_entry_validator_test.dart
fvm flutter analyze \
  lib/main.dart \
  lib/pages/auth/login/login.dart \
  lib/pages/auth/register/register.dart \
  lib/pages/auth/view_model/auth_view_model.dart \
  lib/pages/auth/phone_entry/phone_entry_page.dart \
  lib/pages/auth/finish_profile/finish_profile_page.dart \
  lib/pages/dashboard/dashboard.dart \
  lib/pages/stock/view_model/product_view_model.dart \
  lib/pages/stock/widgets/product_form.dart \
  lib/services/analytics_event.dart \
  lib/utils/feature_flags.dart
fvm flutter run -d emulator-5554
```

Analyzer info-level findings that predate or sit outside these exact changes may be reported separately. Any compile error, runtime exception, broken route, failed save, or regression is a release blocker.

## Required simulator QA

### Phase 1 — Number-first onboarding

The feature is gated by `FEATURE_NUMBER_FIRST_ONBOARDING_ENABLED`, default `false`.

Test both flag states. If Remote Config cannot be safely changed, use a temporary local-only override in the release worktree, test it, then restore the file before reporting. Do not commit the override.

Flag off:

- Fresh launch opens the existing login flow.
- Login and registration remain usable.
- POPIA consent remains pre-auth.

Flag on:

- Fresh launch opens the single phone-entry screen.
- Invalid, empty, non-SA, local SA, and `+27` formats behave correctly.
- Offline/lookup failure never falls through to account creation.
- Returning number follows login OTP and lands on dashboard.
- New number follows registration OTP, then the unskippable finish-profile page.
- Android back cannot bypass finish profile.
- Full Name and Business Name validation works with the keyboard visible.
- Logout returns to phone entry through the compatibility redirect.
- Verify the auth-state stream does not render Dashboard before the new-user finish-profile route completes.
- Verify loading indicators clear after cancel, failure, and success.

### Phase 2 — Onboarding product CTA

- Reach the merchant onboarding intro.
- Tap the “start with products” CTA.
- Confirm the Products tab is selected and the add-product page opens directly.
- Back returns to the Products catalogue/empty state.
- Repeated taps do not stack duplicate add-product pages.
- Returning-user dashboard navigation is unchanged.

### Phase 3 — WhatsApp-listed image requirement

- Internal-only product saves without an image.
- WhatsApp-listed product cannot save without an image.
- Turning listing on immediately shows the inline image cue.
- Adding an image clears the cue and permits save.
- Turning listing off clears the cue and permits save without an image.
- Edit an existing listed product with an image and save.
- Edit a no-image product, turn listing on, and confirm save is blocked.
- Confirm no Firestore write occurs for the blocked case.

## Cross-surface regression checks

- Test at narrow mobile width with the keyboard open; no overflow or hidden primary CTA.
- Check Android back behavior on phone entry, OTP dialog, finish profile, add product, and product edit.
- Confirm error and validation copy is readable and does not expose raw phone numbers or backend errors.
- Confirm the `.env` remains ignored and `git status` contains only the QA report, if one is created.

## Required report

Return:

- `PASS`, `FAIL`, or `BLOCKED`
- exact commands run
- device and app build used
- test cases observed, not merely inferred
- defects with severity and file/line references
- screenshots/log excerpts for failures
- residual risks and any cases blocked by OTP, Firebase, Remote Config, or test data

Do not modify product code unless explicitly asked. A QA report file may be created as `CODEX_QA_REPORT.md` in this worktree.
