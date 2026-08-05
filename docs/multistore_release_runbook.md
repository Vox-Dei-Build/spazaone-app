# Multi-store and multi-operator release runbook

Release candidate: SpazaOne `4.4.0+76`

## Release decision

Use an additive schema in the existing Firebase project, with a zero-copy
migration. Existing business data remains under `users/{storeId}`. New metadata
describes stores and operator membership:

```text
users/{storeId}/...                         existing business data (unchanged)
stores/{storeId}                            store metadata
stores/{storeId}/operators/{uid}            authoritative membership
stores/{storeId}/invites/{phoneHash}        private pending-invite mirror
operators/{uid}/stores/{storeId}            operator's store picker
operatorInvites/{phoneHash}/stores/{storeId} private claim record
operatorPhoneLookup/{phoneHash}/stores/...  private bot identity lookup
```

A full Firebase-project clone is not the release path. Cloning Firestore alone
would not safely clone Auth identities, App Check registrations, FCM tokens,
Storage URLs, Functions secrets, Remote Config, Paystack/Twilio webhooks, or
Botpress state. It creates a much larger cutover and rollback surface while the
additive model preserves every existing document ID and integration URL.

Production project: `pasella-ledger`. No command in this runbook may omit an
explicit `--project` argument. The migration is dry-run by default and refuses
production writes without two separate confirmations.

## Authorization model

| Role | Store data | Operate sales/ledger/messages | Invite/remove operators |
| --- | --- | --- | --- |
| Owner | yes | yes | yes |
| Admin | yes | yes | yes, except owner |
| Operator | yes | yes | no |

Membership must have `status == active`. Revocation disables both membership
mirrors, removes the private bot lookup, removes that operator's known device
tokens from the legacy store token set, and excludes disabled membership
devices from v2 notification sends.

Legacy owners retain access through `uid == storeId` while metadata is adopted.
This is required for older app builds and rollback. New stores receive random
store IDs and a zero wallet balance; creating stores cannot repeat the signup
credit.

## Release controls

- Remote Config key: `FEATURE_MULTI_STORE_OPERATORS_ENABLED`.
- Default: `false` in the app and local Remote Config defaults.
- Keep it `false` through backend, rules, migration, bot, and internal-app QA.
- For the pilot, distribute `4.4.0+76` only through the internal testing track
  and use a Remote Config condition for that exact app version and platform.
  The current client does not implement a UID allowlist, so do not describe a
  global boolean as a named-user rollout.
- After pilot sign-off, promote the same tested binary through the store's
  staged rollout. The version condition then enables the feature only for
  users who receive `4.4.0`; old builds continue on the legacy path.
- Turning it off returns app clients to their legacy UID store. Backend
  membership metadata remains additive and can be re-enabled later.

## Rehearsal and QA

Run from the repository root. These tests use only a `demo-` project and local
emulators:

```bash
cd functions
npm ci
npm run build
npm run lint -- --quiet
npm run test:security
npm audit --omit=dev

PASELLA_BOT_TOKEN=emulator-only-secret \
JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.14/libexec/openjdk.jdk/Contents/Home \
npm exec --yes --package=firebase-tools@13.35.1 -- \
firebase emulators:exec --config ../firebase.json \
  --project demo-spazaone-multistore --only firestore,functions \
  "npm run test:bot-http"

JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.14/libexec/openjdk.jdk/Contents/Home \
PATH=/opt/homebrew/Cellar/openjdk@17/17.0.14/bin:/opt/homebrew/bin:/usr/bin:/bin \
npm exec --yes --package=firebase-tools@13.35.1 -- \
firebase emulators:exec --config ../firebase.test.json \
  --project demo-spazaone-multistore --only firestore,auth \
  "npm run test:stores"

JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.14/libexec/openjdk.jdk/Contents/Home \
PATH=/opt/homebrew/Cellar/openjdk@17/17.0.14/bin:/opt/homebrew/bin:/usr/bin:/bin \
npm exec --yes --package=firebase-tools@13.35.1 -- \
firebase emulators:exec --config ../firebase.test.json \
  --project demo-spazaone-multistore --only firestore,storage \
  "npm run test:rules"

JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.14/libexec/openjdk.jdk/Contents/Home \
PATH=/opt/homebrew/Cellar/openjdk@17/17.0.14/bin:/opt/homebrew/bin:/usr/bin:/bin \
npm exec --yes --package=firebase-tools@13.35.1 -- \
firebase emulators:exec --config ../firebase.test.json \
  --project demo-spazaone-multistore --only firestore \
  "npm run test:migration"

cd ..
flutter analyze --no-fatal-infos
flutter test
flutter build appbundle --release
```

From the Botpress source worktree/checkout:

```bash
npm ci
npm test
npm run typecheck
npm run bp:generate -- --confirm
npm run typecheck:bot
npm run bp:build

cd adk-agent
npm ci
npm run build
adk check --format json
```

The prepared bot branch is `codex/multistore-operators-bot`. Its production
dependency audits must have zero critical and zero high findings. Moderate
vendor findings in the Botpress SDK/ADK are recorded separately and are not a
reason to force an untested major-version change into this release.

For a device-level rehearsal, start the full local emulator suite with project
`demo-spazaone-multistore`, then compile an isolated debug build:

```bash
firebase emulators:start \
  --project pasella-ledger \
  --only auth,firestore,functions,storage

flutter run \
  --dart-define=USE_FIREBASE_EMULATORS=true \
  --dart-define=FIREBASE_EMULATOR_PROJECT_ID=pasella-ledger \
  --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2 \
  --dart-define=ENABLE_MULTI_STORE_OPERATORS=true
```

Use `127.0.0.1` instead of `10.0.2.2` for an iOS simulator or desktop target.
The compile-time switch changes the Firebase project namespace and routes both
SDK callables and raw HTTP Function URLs to localhost. It cannot be activated
remotely in a production binary.

The migration test verifies dry-run inertness, additive execution, owner-token
copying, rollback by run ID, and byte-for-byte preservation of the legacy user
document. Store integration covers legacy adoption, second-store creation,
zero signup credit, direct and pending invites, invite claim/cancel, cross-store
denial, token revocation, and the owner-deletion orphan guard.

The release candidate also upgrades the Node 20-compatible Firebase Admin,
Functions, Twilio, and Nodemailer dependency lines. Production dependency
audits for Functions and both Botpress packages must remain at zero critical and
zero high findings. Do not use total audit counts for this gate because the
local build/test toolchains are excluded from deployed production packages.

## Production rollout

1. Keep the feature flag off. Freeze unrelated Firebase/rules deployments.
2. Confirm the selected Firebase project is exactly `pasella-ledger`.
3. Create a managed Firestore export to a dated, retention-protected bucket:

   ```bash
   gcloud firestore export \
     gs://<BACKUP_BUCKET>/multistore-<YYYYMMDD-HHMM> \
     --project pasella-ledger
   ```

   Do not continue until the export reports success and a restore operator has
   verified the output prefix.

4. Deploy Functions first, explicitly scoped. Start with only the six additive
   callables; no released app invokes these names yet:

   ```bash
   firebase deploy --project pasella-ledger --only \
     functions:bootstrapStoreAccess,\
functions:createStore,\
functions:inviteStoreOperator,\
functions:listStoreOperators,\
functions:cancelStoreOperatorInvite,\
functions:removeStoreOperator
   ```

   Smoke-test those callables while the feature flag remains off. Then deploy
   only the existing functions whose store authorization, payment binding,
   notification routing, or bot selection changed:

   ```bash
   firebase deploy --project pasella-ledger --only \
     functions:addPayment,\
functions:calculateUserBalance,\
functions:generateCashflowImpactReport,\
functions:generateReport,\
functions:getBotpressMessages,\
functions:sendTwilioMessage,\
functions:getCustomerOrders,\
functions:getMerchantOrderingLink,\
functions:getMerchantSales,\
functions:getOnlineSalesFromLedger,\
functions:getOrderById,\
functions:notifyOrderEvent,\
functions:markOrdersAsRead,\
functions:onSaleCancelledNotify,\
functions:onSaleCreatedNotify,\
functions:updateOrderPayment,\
functions:deleteTwilioTemplate,\
functions:ensureProductPromotionTemplate,\
functions:fetchMerchantDetails,\
functions:logUnreadMessage,\
functions:runMerchantPromotion,\
functions:createPaystackTransaction,\
functions:verifyPaystackTransaction,\
functions:deleteUserAccount,\
functions:heartbeatMerchantApp
   ```

   Do not use `--only functions`: that would redeploy unrelated production
   schedules, webhooks, and bots from the shared Functions bundle.

5. Run a production **dry-run** and archive its JSON output:

   ```bash
   cd functions
   npm run multistore:migrate -- --project pasella-ledger
   ```

   Gate: `scanned == planned + skipped`; no unexpected user count change;
   `existingUserDocumentsModified == 0`.

6. Execute only after two people compare the dry-run count with the console:

   ```bash
   MULTISTORE_PRODUCTION_CONFIRM=pasella-ledger \
   npm run multistore:migrate -- \
     --project pasella-ledger --execute --allow-production-write
   ```

   Save the returned `runId` immediately.

7. Sample at least ten migrated owners, including stores with missing optional
   fields. Verify the `users/{uid}` document did not change and each owner has
   two active membership mirrors.
8. Deploy Firestore and Storage rules explicitly:

   ```bash
   firebase deploy --project pasella-ledger --only firestore:rules,storage
   ```

9. Verify both deployed Botpress bots remain customer-commerce bots and that
   their existing multi-shop customer route never defaults when several
   merchant candidates exist. Do not publish the prepared operator integration
   into either customer bot. Execute the source QA in
   `docs/botpress_multistore_contract.md`; a dedicated operator bot can be
   piloted later after the backend is deployed.
10. Distribute `4.4.0+76` to internal testers. Add a Remote Config condition
    matching the exact `4.4.0` app version and platform, with default `false`
    and conditional value `true`. At this point only internal testers can
    receive that version, which makes the condition the pilot boundary. Do not
    start store rollout until pilot QA is signed off.
11. Roll out 5% → 25% → 100%, holding at least two hours at each early stage.

## Monitoring gates

Stop expansion and turn the feature flag off if any gate is crossed:

- any cross-store permission denial for a legitimately selected store;
- any successful read/write after membership status becomes disabled;
- wallet or sales balance changes in a non-selected store;
- duplicate signup credit on store creation;
- Paystack amount/metadata mismatch or invalid webhook signature;
- Botpress silently chooses the first of multiple stores;
- Functions error rate exceeds the prior seven-day baseline by 2 percentage
  points for 15 minutes;
- notification delivery continues to a removed operator.

Track callable error codes by function, store-selection events, invitation
claim/cancel counts, membership denials, migration run ID, and Paystack webhook
rejections. Never log full phone numbers or phone hashes in application logs.

## Rollback

1. Set `FEATURE_MULTI_STORE_OPERATORS_ENABLED=false` first.
2. Stop app rollout and Botpress multi-store routing. Do not restore Firestore
   merely because the UI was disabled; the additive metadata is harmless.
3. If failure occurred before any pilot created stores/invites, roll back only
   metadata created by the migration run:

   ```bash
   cd functions
   npm run multistore:migrate -- \
     --project pasella-ledger --rollback <RUN_ID>

   MULTISTORE_PRODUCTION_CONFIRM=pasella-ledger \
   npm run multistore:migrate -- \
     --project pasella-ledger --rollback <RUN_ID> --execute \
     --allow-production-write
   ```

   Review the rollback dry-run before execution. It never deletes or edits a
   `users/{storeId}` document.
4. If real v2 stores were created, preserve them and diagnose; do not downgrade
   or delete them automatically. The feature flag isolates the app while data
   remains recoverable.
5. Restore from the managed export only for confirmed destructive corruption,
   with incident command approval. A restore is not the default rollback.

## Inversion checklist

| Critical failure | Preventive control |
| --- | --- |
| Wrong Firebase project receives a write | explicit project on every command; dynamic app Function URLs; production migration double confirmation |
| Old merchants are locked out | UID/store compatibility in rules and Functions; zero-copy data paths |
| Operator reads another store | membership checks in rules and server endpoints; hostile emulator tests |
| Removed operator still receives data | disabled membership, bot lookup removal, operator-scoped FCM tokens and cleanup |
| Store creation mints money | new-store wallet starts at zero; emulator assertion |
| Payment forged across stores | authenticated initialization, membership check, Paystack HMAC, verified metadata only, atomic idempotency and amount binding |
| Account deletion orphans stores | preflight blocks owners while other active operators remain |
| Bot acts on arbitrary first store | deterministic selection-required response; explicit persisted choice; no operator workflow published into customer bots |
| Stale Store A data flashes in Store B | store-change rebinding/reset for wallet, balances, customer and promotion state |
| Rollback destroys legacy data | metadata-only rollback by migration run ID; legacy document equality test |

## Known compatibility debt

The root `users/{storeId}` profile remains publicly readable because supported
legacy login builds query it before authentication. Nested financial and
customer data is denied to unauthenticated clients. Replace that login lookup
with an App Check-protected callable, force the minimum app version, and then
remove the transitional root-profile read in a follow-up security release.

Build `4.3.1+74` also performs an authenticated collection-group read across
all `transactions` subcollections for its overdue-credit report. The release
rules temporarily preserve authenticated read compatibility for that query;
writes remain store-scoped. Build `4.4.0+76` replaces the global query with
selected-store queries. Remove the compatibility read after `4.3.1+74` is
outside the supported-version window.
