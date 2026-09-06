# Development phone build — 6 September 2026

## Build prepared

- Project/entity: Spaza One / Vox Dei. GitHub authority verified as
  `Vox-Dei-Build/spazaone-app` through the registered `TsepoVoxDei` identity.
- Current authority `main` verified remotely at
  `7078080079bf63410484b3440917de2036b52dcb`.
- Build checkout:
  `/Users/admin/.codex/worktrees/2f79/pasella-app-dev-install`.
  It starts at that authority revision, with the reviewed redesign, crash,
  onboarding and banking client/test changes overlaid. Backend, rules, indexes
  and environment deployment configuration retain the authority revision.
  The original redesign checkout remains intact at its earlier base.
- App: **SpazaOne Dev**, package `com.tsepo.spazaone.dev`, version
  `4.8.4-dev`, version code `100`, debug runtime. Production's separate package
  `com.tsepo.pasella` is not an install target.
- Flavor: `development`; build define:
  `SPAZAONE_ENVIRONMENT=development`; no Firebase emulator define.
- Registered native development configs were copied locally from the canonical
  authority checkout; `tool/materialize_development_env.rb` generated the
  ignored development `.env`. Configuration values were not logged or committed.

Original tested APK:
`/Users/admin/.codex/worktrees/2f79/pasella-app-dev-install/build/app/outputs/flutter-apk/app-development-debug.apk`

SHA-256:
`5d0eeabbca50c5a10c5fbbccb216d526255660cd7529f4aed993b0b8085ee905`

Installed APK (same application content, matching the existing dev signature):
`/Users/admin/.codex/worktrees/2f79/pasella-app-dev-install/build/app/outputs/flutter-apk/spazaone-development-4.8.4-dev-100.apk`

Installed APK SHA-256:
`f48df8fc905cdbc02a8eb15f796ac799318f1e7978807ff26099b285af2edc5b`

## Verified locally

- All **689 Flutter tests pass** with the materialized development environment.
  This includes the previously failing Firebase identity configuration test.
- Analysis of 225 changed/new Dart files: **0 errors, 0 warnings**;
  96 retained informational lints.
- Android development debug APK built successfully and its signature verified.
- APK manifest confirms the development package/name/version. Both packaged
  Flutter Firebase project values and the compiled Android native `project_id`
  are `spazaone-dev`.
- `git diff --check` passes. The development checkout's backend/rules/indexes
  match authority `7078080`; no cloud deployments or data mutations occurred.

Logs: `/tmp/spazaone-dev-install-apk-build.log`,
`/tmp/spazaone-dev-install-full-tests.log`,
`/tmp/spazaone-dev-install-analysis.log`.
Overlay manifest: `/tmp/spazaone-dev-install-source-manifest.json`.

## Phone installation

**Verified installed and launched** on Samsung SM-A556E (`RZCY116F92J`),
6 September 2026. Device package readback reports `4.8.4-dev`, code `100`,
updated at 12:31:20 device local time. Android launch reports `Status: ok`;
the development activity is resumed and its process remains running. The
process log check found no fatal exception, Firebase project mismatch or
unhandled Flutter exception. This is a startup check, not authenticated
end-to-end verification of every feature.

USB debugging initially blocked installation; the user approved the phone's
prompt. A subsequent attempt found that the existing dev version `4.8.2+95`
was signed with the configured release key. Its public certificate matched
the canonical historical development release APK. The tested debug APK was
signed using that existing key, without changing keys or certificates. All
application and asset ZIP entries were verified byte-identical before/after
signing; only signing metadata changed. The installed signature SHA-256 is
`472dd3f2af68649cd2870712601f25d0bf16ae47615914079b6156963fdc1b44`.
The debug runtime and debug App Check behavior are preserved.

`adb install -r` then returned **Success**. No uninstall, app-data clear,
debugging-key reset, device trust reset, or production-package update occurred.
Signing passwords were passed only through the signing child process's
environment, never printed or placed in command arguments or new files.

## Live development versus production audit

Read-only checks at 2026-09-06 10:09 UTC used explicit Firebase projects and the
registered CLI account `tsepo.ntsaba@thedelta.io`. Environment contracts,
Functions inventories and Remote Config were read; no provider action was run.

| Evidence | Development | Production |
| --- | --- | --- |
| Firebase project | `spazaone-dev` | `pasella-ledger` |
| Reported environment-function build | `c277f1a174f4d88ee32a1d77c3f6d1a5f40b4b34` | `ba39230648261bf354a6fba3bea82b282d124120` |
| API/schema contract | `2026-08-12` / `2` | Same |
| Active Functions | 161 | 162 |
| `getWhatsAppCatalogSyncStatusV2` | Missing | Active |
| Remote Config | v5, August 14 | v69, September 4 |
| Paystack / CJ / Botpress modes | Test | Live |
| Twilio reported mode | Live | Live |

Development is isolated by app/project identity, but its deployed capabilities
are **not fully aligned** with production. In particular, the redesigned client
calls catalogue status V2, which is absent from development; the catalogue
panel will report unavailable until that backend is updated separately.

Some Remote Config differences are intentional: development enables commerce
and payments globally; production uses approved build cohorts. Balance payout
is off in dev versus on in production. Dev lacks the explicit catalogue-status
flag, so the client uses its enabled default. Twilio's reported live mode means
development must not be described as entirely sandboxed.

The environment-function revision is not proof that all functions were deployed
together. Live Firestore/Storage rules, indexes, merchant capabilities and
provider credentials were not inspected; their parity remains unverified.
Updating the dev backend is a separate external action from installing this APK.
