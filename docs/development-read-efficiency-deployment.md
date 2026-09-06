# Development read-efficiency deployment

This release uses a dedicated development executor because the repository's normal Firebase configuration intentionally blocks raw function deployments. The executor is fixed to the registered `spazaone-dev` target through `codex-guard --environment firebase_development`; its Firebase predeploy hook checks the exact project and ephemeral configuration paths again before Firebase can write.

The index lane reads the current development index configuration and synthesizes an ephemeral configuration containing that exact baseline plus these two composites:

- `customers`: `isNPA ASC`, `balance ASC`, `__name__ ASC` with collection-group scope
- `paymentIntents`: `purpose ASC`, `status ASC`, `expiresAt ASC`, `__name__ ASC` with collection scope

It does not deploy the full checked-in `firestore.indexes.json`. This preserves all remote indexes and field overrides and avoids activating unrelated local TTL policies. Immediately before dispatch it checks that the remote baseline has not changed, and after dispatch it checks the full remote configuration digest. The function lane remains blocked until both required indexes are configured and report `READY`.

The four functions deploy one at a time with exact selectors, in this order:

1. `getWhatsAppCatalogSyncStatusV2`
2. `scheduledNPAUpdate`
3. `expireAccountSettlementIntents`
4. `getEnvironmentInfo`

Each deployment gets a separate mode-`0600` temporary dotenv. Existing functions inherit only their own live user environment; `BUILD_COMMIT` is changed to the candidate commit. Because V2 does not yet exist in development, its initial environment baseline comes from `getWhatsAppCatalogSyncStatusV1`. A later V2 redeploy uses V2's own live environment. Secret bindings are checked independently and never written to dotenv.

`WHATSAPP_CATALOG_STATUS_CURSOR_SECRET` is required by V2. The executor performs metadata-only Secret Manager lookups before any function dispatch and stops with `MISSING_REQUIRED_DEVELOPMENT_SECRET` when the secret or an enabled version is absent. Creating or changing that secret is a separate credential operation; this executor cannot do it and never accesses a secret payload.

From a clean candidate commit that descends from the local authoritative `origin/main`, preview the index command:

```sh
candidate="$(git rev-parse HEAD)"
npm --prefix functions run development:release:deploy -- \
  --lane indexes \
  --expected-app-commit "$candidate"
```

After the authorized index write, verify readiness with the read-only lane:

```sh
npm --prefix functions run development:release:deploy -- \
  --lane indexes \
  --expected-app-commit "$candidate" \
  --readback-only
```

Once both indexes are `READY` and the required cursor secret has been provisioned through its separately governed process, preview the four exact function commands:

```sh
npm --prefix functions run development:release:deploy -- \
  --lane functions \
  --expected-app-commit "$candidate"
```

An authorized write adds `--execute` to the corresponding indexes or functions command. The executor reruns the authority and clean-checkout check immediately before every dispatch. Function predeploy retains `lint` and `build`; postdeploy readback binds the Firebase project, deployed source hash, per-function provider hash, environment digest, and `BUILD_COMMIT` to the candidate without printing environment values. Temporary configs and dotenv files are deleted after each command.

Focused validation is:

```sh
npm --prefix functions run test:development-release-deploy
```
