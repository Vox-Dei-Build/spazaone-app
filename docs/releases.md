# Releases

Pasella ships from `main` directly, tag-driven, no release branches. This
file is the canonical reference for shipping a build to the stores. If
anything here disagrees with `codemagic.yaml`, the YAML wins and this
file is wrong.

## TL;DR

```bash
# 1. Edit code on main, commit and push as much as you like.
#    Plain pushes do NOT trigger any build.
git push

# 2. When ready to ship, bump the version in pubspec.yaml, commit, push.
$EDITOR pubspec.yaml          # bump e.g. 3.0.3+47 -> 3.0.3+48
git commit -am "fix: 3.0.3+48 — <what changed>"
git push

# 3. Tag with the same version prefixed by 'v'. Pushing the tag fires
#    BOTH workflows in parallel: Android -> Play Internal, iOS -> TestFlight.
git tag -a v3.0.3+48 -m "Release 3.0.3+48"
git push origin v3.0.3+48
```

## Branch model

- `main` is the only long-lived branch. No release branches, no fix
  branches. Solo dev, ships from trunk on demand.
- The default branch on GitHub is `main`.
- Worktree directories under `pasella-app-worktrees/` may exist for
  parallel feature work but are not part of the release flow; tags must
  be cut from `main`.

## CI triggers

`codemagic.yaml` declares both workflows with:

```yaml
triggering:
  events:
    - tag
  tag_patterns:
    - pattern: 'v*.*.*+*'
      include: true
```

Implications:

- Pushing commits to `main` does NOT trigger a build. This is
  intentional. Iterate freely without burning Mac builder minutes.
- Only tags matching `v<major>.<minor>.<patch>+<buildNumber>` (e.g.
  `v3.0.3+48`) fire builds. Anything else (`release-3.0.3`,
  `v3.0.3-rc1`, plain `3.0.3+48`) is ignored.
- Both workflows fire in parallel from the same tag. There is no way
  to ship Android-only or iOS-only from a tag; if you need that,
  trigger one workflow manually from the CodeMagic dashboard.

## Version source of truth

`pubspec.yaml` `version:` is the single source of truth for both
platforms.

- **Android**: `android/app/build.gradle` reads `flutterVersionName`
  and `flutterVersionCode` from the Flutter tooling, which derives
  them from `pubspec.yaml`.
- **iOS**: `ios/Runner.xcodeproj/project.pbxproj` is wired to
  `$(FLUTTER_BUILD_NAME)` and `$(FLUTTER_BUILD_NUMBER)` for the Runner
  target across all three configurations (Debug, Profile, Release).
  The Xcode project no longer carries hardcoded version strings.

The "Verify version code matches the git tag" step in both workflows
fails fast if `pubspec.yaml` `3.0.3+48` doesn't match tag `v3.0.3+48`.
This catches the `git tag without bumping pubspec` mistake before
either store sees a build.

## Pre-flight checks (run before tagging)

Optional but cheap:

```bash
# Local IPA privacy check (run after a local IPA build, not strictly
# required since CI runs the same check).
./scripts/verify_ios_privacy.sh build/ios/ipa/*.ipa

# Local strip dry-run (verifies the script still finds the bad
# manifest in pub-cache).
./scripts/strip_badger_privacy.sh
```

## What the iOS workflow does

In order:

1. **Materialise .env** from secure `DOTENV_FILE` env var.
2. **Flutter pub get / analyze / test**.
3. **Verify version code matches the git tag**.
4. **Set up code signing**: generates a fresh RSA private key, mints
   an Apple Distribution cert via App Store Connect API, fetches /
   creates a provisioning profile for `com.tsepo.pasella`, writes
   `$HOME/export_options.plist`. (Apple caps Distribution certs at 2
   per team. Revoke an unused cert in the Apple Developer portal
   before re-running if both slots are full.)
5. **Strip flutter_app_badger_plus invalid privacy manifest**: runs
   `scripts/strip_badger_privacy.sh`. See [Privacy manifest strip](#privacy-manifest-strip)
   below.
6. **Pod install** with `--repo-update`, fresh Podfile.lock and Pods/.
7. **Build IPA** using `$HOME/export_options.plist`.
8. **Verify IPA privacy manifests are valid**: unzips the IPA and
   asserts the bad bundle is absent + scans every remaining
   `PrivacyInfo.xcprivacy` for the empty-`<dict/>` antipattern that
   triggers Apple ITMS-91056. This is belt-and-braces against the
   strip step silently failing.
9. **Publish to App Store Connect** -> TestFlight. `submit_to_app_store`
   is `false`; promotion to App Store review is manual from App Store
   Connect after QA.

## What the Android workflow does

In order:

1. **Materialise .env** from `DOTENV_FILE`.
2. **Materialise google-services.json** from `GOOGLE_SERVICES_JSON_BASE64`
   (base64-encoded; CodeMagic mangles raw JSON env vars).
3. **Materialise Android signing**: writes
   `android/app/release-key.keystore` from `ANDROID_KEYSTORE_BASE64`
   and `android/key.properties` from `ANDROID_KEY_PROPERTIES`. The
   dashboard `android_signing` block was tried previously and produced
   unsigned AABs; env-var materialisation is now the single source of
   truth. See [Android signing](#android-signing) below.
4. **Flutter pub get / analyze / test**.
5. **Verify version code matches the git tag**.
6. **Build signed AAB** with pre-flight assertions that
   `google-services.json`, `.env`, `release-key.keystore`, and
   `key.properties` all exist before invoking Gradle.
7. **Verify 16 KB page-size compliance**: extracts arm64-v8a `.so`
   libs from the AAB and asserts ELF LOAD segments are 16 KB-aligned.
   Same gate Play applies post-upload; failing here saves the round
   trip.
8. **Publish to Google Play** -> Internal track. Promotion to
   Production is manual from Play Console.

## Privacy manifest strip

`flutter_app_badger_plus` 1.0.1 (Dart) / 1.3.0 (podspec) ships an
invalid `PrivacyInfo.xcprivacy` containing empty `<dict/>` entries in
`NSPrivacyAccessedAPITypes` and `NSPrivacyCollectedDataTypes`. Apple
rejects the IPA with ITMS-91056 ~45 minutes after upload. The plugin
only sets a `UIApplication` notification badge — not in Apple's
required-reasons list, so no manifest is required at all.

`scripts/strip_badger_privacy.sh`:

- deletes the manifest from both `$HOME/.pub-cache/hosted/pub.dev/`
  and `ios/.symlinks/plugins/`
- patches the podspec to remove the `s.resource_bundles` line so
  CocoaPods never declares the `flutter_app_badger_plus_privacy`
  bundle target — the manifest cannot resurface in any IPA
- is idempotent: a re-run on already-stripped state passes
- fails loudly if no podspec is found at all, or if any podspec /
  manifest remains unpatched after the strip

If a future bump of `flutter_app_badger_plus` ships a valid manifest,
delete the strip step from `codemagic.yaml` and remove
`scripts/strip_badger_privacy.sh`. The IPA verification step will
keep catching regressions in any other plugin's manifest.

History: builds 3.0.3+44 and +45 shipped to Apple before this was
caught (each a 45-min round-trip). +46's first attempt at the strip
was a Ruby block in `ios/Podfile`'s `post_install` hook with two path
bugs (`__dir__` resolution and `~` expansion on the CodeMagic
builder); +47 replaced it with the shell script.

## Android signing

`android/app/release-key.keystore` and `android/key.properties` are
both gitignored. Without them, `android/app/build.gradle`'s
`signingConfigs.release` block is skipped (its `if (keystoreProperties
File.exists() && keystoreProperties['storeFile'])` guard fails) and
Gradle silently produces an UNSIGNED release AAB. Play rejected
3.0.3+44 with "All uploaded bundles must be signed" — same root cause.

The CodeMagic dashboard `android_signing: pasella_upload_keystore`
reference produced "Certificate issuer: None / Certificate subject:
None" in the upload step on this builder image, meaning the dashboard
reference did not actually inject `key.properties`. We now materialise
both files from secure env vars so the YAML is the single source of
truth (matches the `.env` and `google-services.json` patterns).

Required env vars in the `pasella_android_credentials` group, all
marked **Secure**:

- `ANDROID_KEYSTORE_BASE64` — `base64 -i android/app/release-key.keystore`
- `ANDROID_KEY_PROPERTIES` — full contents of `android/key.properties`:
  ```
  storeFile=./release-key.keystore
  storePassword=...
  keyAlias=...
  keyPassword=...
  ```

`storeFile=./release-key.keystore` is resolved by Gradle relative to
`android/app/` (where `build.gradle` lives), not `android/`.

## Required env vars summary

In `pasella_android_credentials` (Secure):

| Var | Source |
| --- | --- |
| `DOTENV_FILE` | full contents of local `.env` |
| `GOOGLE_SERVICES_JSON_BASE64` | `base64 -i android/app/google-services.json` |
| `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` | Play service account JSON |
| `ANDROID_KEYSTORE_BASE64` | `base64 -i android/app/release-key.keystore` |
| `ANDROID_KEY_PROPERTIES` | contents of `android/key.properties` |

In `pasella_app_store_credentials` (Secure):

| Var | Source |
| --- | --- |
| `DOTENV_FILE` | full contents of local `.env` |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | App Store Connect API Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect Issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | full `.p8` contents |

## Recovery: a build failed in CI

| Step that failed | What to check |
| --- | --- |
| Verify version code matches the git tag | `pubspec.yaml` version vs tag name. Bump pubspec, commit, delete the tag, re-tag. |
| Set up code signing | Apple Distribution cert slot full (max 2). Revoke an unused cert in Apple Developer portal. |
| Strip flutter_app_badger_plus invalid privacy manifest | Plugin moved or removed. Update `scripts/strip_badger_privacy.sh` search patterns or remove the step. |
| Pod install (Mantle clone) | Transient; restart the build. |
| Verify IPA privacy manifests are valid | A new plugin shipped a broken `PrivacyInfo.xcprivacy`. Add a strip step or pin the plugin to the previous version. |
| Build signed AAB pre-flight (file missing) | One of the secure env vars is unset or the materialise step failed. Check the materialise step logs above. |
| Verify 16 KB page-size compliance | A native lib in the AAB is not 16 KB-aligned. Bump the offending dependency or rebuild against the 16 KB-aligned NDK. |

## Recovery: rejected by store post-upload

| Symptom | Cause | Fix |
| --- | --- | --- |
| Apple ITMS-91056 (Invalid privacy manifest) | A `PrivacyInfo.xcprivacy` in the IPA has invalid structure | Patch the offending plugin via the same shell-script approach used for `flutter_app_badger_plus` |
| Play "All uploaded bundles must be signed" | Signing config skipped during build | Verify `ANDROID_KEYSTORE_BASE64` and `ANDROID_KEY_PROPERTIES` are present and correct in `pasella_android_credentials` |
| Play 16 KB page-size warning | A native lib not 16 KB-aligned | Same as the CI step above |

## What is intentionally NOT here

- Changelog: not maintained as a separate file. Read `git log` between
  tags: `git log v3.0.3+47..v3.0.3+48 --oneline`.
- Pre-release branch / RC tags: not used. If you need to ship a
  fix without main's WIP, either revert the WIP commits on main and
  tag, or use the CodeMagic dashboard to trigger a workflow on a
  specific commit SHA.
- Hotfix process: same as a normal release. Bump pubspec, commit,
  tag, push. There is no separate hotfix branch.
