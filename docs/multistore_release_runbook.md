# Multi-store and multi-operator release runbook

Initial release candidate: Spaza One `4.4.0+76`

Current availability decision: multi-store is a standard Spaza One feature
from `4.6.2+82`. The pilot completed; the Remote Config parameter remains only
as an emergency rollback switch.

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
- Default: `true` in the app, local defaults, and production Remote Config.
- A missing or failed Remote Config fetch must leave multi-store available.
- Set the parameter to `false` only as an emergency rollback action.
- Keep backend, rules, bot routing, and store/operator security tests in every
  release gate because availability is no longer limited to pilot builds.
- Historical pilot process (completed): keep it `false` through backend,
  rules, migration, bot, and internal-app QA.
- For the pilot, distribute `4.4.0+76` only through the internal testing track
  and use a Remote Config condition for that exact app version and platform.
  The current client does not implement a UID allowlist, so do not describe a
  global boolean as a named-user rollout.
- After pilot sign-off, the feature becomes standard-on. Version-specific
  pilot conditions should be removed so later builds cannot silently lose it.
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

For an Android emulator device-level rehearsal, use only the local project
`demo-spazaone-qa`. Never use `pasella-ledger` as an emulator namespace: the
root `.firebaserc` points at production, so every command below carries an
explicit `--project` or `GCLOUD_PROJECT` value.

Use Node 20, matching `functions/package.json`, and Java 21 for the Firestore
emulator. Verify both versions before starting:

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@21
export PATH="/opt/homebrew/opt/node@20/bin:/opt/homebrew/opt/openjdk@21/bin:$PATH"
node --version
java -version
npm --prefix functions run build
```

The Functions emulator loads `functions/.env` automatically. Before starting,
create ignored `functions/.env.local` and `functions/.secret.local` files that
override every populated local production credential. Do not copy real values.
Use inert values such as:

```dotenv
# functions/.env.local (ignored; emulator only)
COMMERCE_PAYMENTS_ENABLED=false
ACTIVATION_NUDGES_ENABLED=false
ACTIVATION_NUDGES_DRY_RUN=true
PAYSTACK_SECRET_KEY=sk_test_emulator_disabled
PAYSTACK_TEST_SECRET_KEY=sk_test_emulator_disabled
TWILIO_SID=<YOUR_TWILIO_ACCOUNT_SID>
TWILIO_TOKEN=emulator-disabled
TWILIO_ACCOUNT_SID=<YOUR_TWILIO_ACCOUNT_SID>
TWILIO_NUMBER=+27000000000
TWILIO_MERCHANT_MESSAGING_SERVICE_SID=<YOUR_MERCHANT_MESSAGING_SERVICE_SID>
TWILIO_CUSTOMER_MESSAGING_SERVICE_SID=<YOUR_CUSTOMER_MESSAGING_SERVICE_SID>
EMAIL_ADMINLOGIN=emulator-disabled
EMAIL_ADMINPASS=emulator-disabled
WHATSAPP_SENDER_NUMBER_ID=emulator-disabled
```

```dotenv
# functions/.secret.local (ignored; emulator only)
CJ_API_KEY=emulator-disabled
PASELLA_BOT_TOKEN=emulator-only-qa
TWILIO_AUTH_TOKEN=emulator-disabled
BOTPRESS_API_TOKEN=emulator-disabled
```

These values prevent real provider authentication; they do not make external
messaging or payment calls meaningful. Do not test actual Twilio, Botpress,
CJ, or Paystack dispatch in this lane. Pub/Sub is intentionally omitted so the
scheduled CJ worker cannot run.

Start the isolated suite from the repository root:

```bash
firebase emulators:start \
  --config firebase.json \
  --project demo-spazaone-qa \
  --only auth,firestore,functions,storage
```

In a second terminal, seed only the local emulators. The script hard-refuses a
non-loopback host, a missing emulator, conflicting project IDs, or any project
that does not begin with `demo-`:

```bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199 \
QA_FIREBASE_PROJECT_ID=demo-spazaone-qa \
GCLOUD_PROJECT=demo-spazaone-qa \
GOOGLE_CLOUD_PROJECT=demo-spazaone-qa \
npm --prefix functions run seed:qa
```

The seed creates two named stores for one local seller, one customer, one
seller-owned comparison product, and twelve fresh schema-v2 South
Africa-deliverable catalogue products. It upserts only deterministic `qa-*`
documents and contains no credentials.

The QA feature defines below are an explicit snapshot of the production Remote
Config read on 6 August 2026: multi-store exists and is `true`; number-first,
deferred consent, OTP auto-submit/resend and Online Sales are absent/false;
merchant onboarding intro uses its `true` default. Re-read production Remote
Config and update every value together if that release state changes.

```bash
flutter run -d emulator-5554 \
  --dart-define=USE_FIREBASE_EMULATORS=true \
  --dart-define=FIREBASE_EMULATOR_PROJECT_ID=demo-spazaone-qa \
  --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2 \
  --dart-define=DROPSHIP_CATALOG_V2=true \
  --dart-define=QA_FEATURE_MULTI_STORE_OPERATORS=true \
  --dart-define=QA_FEATURE_NUMBER_FIRST_ONBOARDING=false \
  --dart-define=QA_FEATURE_DEFER_AUTH_CONSENT=false \
  --dart-define=QA_FEATURE_OTP_AUTOSUBMIT=false \
  --dart-define=QA_FEATURE_OTP_RESEND_IN_DIALOG=false \
  --dart-define=QA_FEATURE_ONLINE_SALES=false \
  --dart-define=QA_FEATURE_MERCHANT_ONBOARDING_INTRO=true
```

The Auth emulator does not inherit Firebase Console test-phone codes. It
generates a random six-digit code, so `123456` is not guaranteed. After the app
requests a code, read the latest pending local code with:

```bash
curl -fsS \
  http://127.0.0.1:9099/emulator/v1/projects/demo-spazaone-qa/verificationCodes \
  | /usr/bin/python3 -c \
    'import json,sys; print(json.load(sys.stdin)["verificationCodes"][-1]["code"])'
```

Use `0648370009` to sign into the seeded existing seller, or another valid SA
test number to exercise brand-new registration. This isolated harness is
Android-only: iOS native Firebase/APNs initialisation still reads the tracked
production plist before Dart starts, so do not claim or run iOS simulator QA
with these defines. The compile-time switch changes the Android Firebase
project namespace and routes SDK callables and raw HTTP Function URLs to
localhost. The app fails closed if the project is not `demo-*`, the host is
not local, the initialized app does not match that demo project, or any QA
feature define is missing.

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

1. Keep `COMMERCE_PAYMENTS_ENABLED=false` and
   `FEATURE_ONLINE_SALES_ENABLED=false`. Leave multi-store standard-on with its
   Remote Config parameter available only as an emergency rollback switch.
   Freeze unrelated Firebase/rules deployments.
2. Confirm the selected Firebase project is exactly `pasella-ledger`.
3. Create a managed Firestore export to a dated, retention-protected bucket:

   ```bash
   gcloud firestore export \
     gs://<BACKUP_BUCKET>/multistore-<YYYYMMDD-HHMM> \
     --project pasella-ledger
   ```

   Do not continue until the export reports success and a restore operator has
   verified the output prefix.

4. Deploy the two `commerceOrders` indexes before any Function can query the
   combined WhatsApp order stream. All Firebase mutations on this Mac must run
   through the registered Vox Dei authority checkout and `codex-guard`; Delta
   is a post-release backup only. First verify the resolved Firebase account and
   target without writing:

   ```bash
   /Users/admin/.codex/identity-governance/bin/codex-guard \
     firebase-deploy --project spaza-one --dry-run -- \
     --only firestore:indexes
   ```

   After explicit action-time production confirmation, repeat without
   `--dry-run`. Then inspect only the coupled collection group:

   ```bash
   gcloud firestore indexes composite list \
     --project pasella-ledger \
     --database='(default)' \
     --filter='COLLECTION_GROUP:commerceOrders'
   ```

   Gate: both query shapes from `firestore.indexes.json` must be present and
   report `READY`: `sellerId + customerId + createdAt`, and
   `sellerId + customerId + status + createdAt`. Do not deploy the bot-facing
   Functions while either index is creating or absent.

5. Publish and verify the updated WhatsApp customer bot from the Vox Dei bot
   authority. Confirm its `PASELLA_BACKEND_TOKEN` still matches the registered
   Functions `PASELLA_BOT_TOKEN` secret without printing either value, and run
   the commerce source-guard QA. The bot must distinguish `source=commerce`
   from legacy Sales before the Functions below can expose supplier orders.

6. Deploy only the manual dropshipping MVP Functions. Verify the guarded target
   first with `--dry-run`, obtain explicit action-time production confirmation,
   then repeat the same command without `--dry-run`:

   ```bash
   /Users/admin/.codex/identity-governance/bin/codex-guard \
     firebase-deploy --project spaza-one --dry-run -- \
     --only \
functions:searchCjSupplierCatalogV2,\
functions:getCjSupplierProductV2,\
functions:createDropshipListingV2,\
functions:syncCjSupplierCatalog,\
functions:productPromotionImage,\
functions:createCommerceOrder,\
functions:verifyCommercePaystackTransaction,\
functions:updateCommerceOrder,\
functions:getCustomerOrders,\
functions:getOpenSale,\
functions:getSaleStatus
   ```

   Keep `verifyCommercePaystackTransaction` deployed so the existing Paystack
   integration is preserved, but keep `COMMERCE_PAYMENTS_ENABLED=false` until
   payment-provider compliance is approved. With the gate closed the endpoint
   returns 503 and cannot mark an order paid. Do not deploy `commerceCheckout`
   or `getCommerceOrderStatus` for the WhatsApp-only manual-payment release.
   Let the scheduled catalogue worker warm the default categories, smoke-test
   a supplier-product promotion image, then run the bot HTTP and commerce
   integration suites against the deployed contract.

7. Deploy the multi-store Functions, explicitly scoped. Start with only the six
   additive callables; no released app invokes these names yet. Run the guarded
   command with `--dry-run` first and remove it only after explicit action-time
   confirmation:

   ```bash
   /Users/admin/.codex/identity-governance/bin/codex-guard \
     firebase-deploy --project spaza-one --dry-run -- \
     --only \
     functions:bootstrapStoreAccess,\
functions:createStore,\
functions:inviteStoreOperator,\
functions:listStoreOperators,\
functions:cancelStoreOperatorInvite,\
functions:removeStoreOperator
   ```

   Smoke-test those callables before promoting the store binaries. Then deploy
   only the existing functions whose store authorization, payment binding,
   notification routing, or bot selection changed:

   ```bash
   /Users/admin/.codex/identity-governance/bin/codex-guard \
     firebase-deploy --project spaza-one --dry-run -- \
     --only \
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

8. Run a production **dry-run** and archive its JSON output:

   ```bash
   cd functions
   npm run multistore:migrate -- --project pasella-ledger
   ```

   Gate: `scanned == planned + skipped`; no unexpected user count change;
   `existingUserDocumentsModified == 0`.

9. Execute only after two people compare the dry-run count with the console:

   ```bash
   MULTISTORE_PRODUCTION_CONFIRM=pasella-ledger \
   npm run multistore:migrate -- \
     --project pasella-ledger --execute --allow-production-write
   ```

   Save the returned `runId` immediately.

10. Sample at least ten migrated owners, including stores with missing optional
   fields. Verify the `users/{uid}` document did not change and each owner has
   two active membership mirrors.
11. Deploy Firestore and Storage rules explicitly. Run the guarded command with
    `--dry-run` first and remove it only after explicit action-time confirmation:

   ```bash
   /Users/admin/.codex/identity-governance/bin/codex-guard \
     firebase-deploy --project spaza-one --dry-run -- \
     --only firestore:rules,storage
   ```

12. Verify both deployed Botpress bots remain customer-commerce bots and that
    their existing multi-shop customer route never defaults when several
    merchant candidates exist. Do not publish the prepared operator integration
    into either customer bot. Execute the source QA in
    `docs/botpress_multistore_contract.md`; a dedicated operator bot can be
    piloted later after the backend is deployed.
13. Distribute `4.6.2+82` through CodeMagic to Play Internal and TestFlight.
    Confirm `FEATURE_MULTI_STORE_OPERATORS_ENABLED=true` (or absent, which uses
    the app's standard-on default) and remove any obsolete version-specific
    `4.4.0` pilot condition. Do not start store rollout until the integrated
    dropshipping, promotion, customer-order and multi-store QA is signed off.
14. Roll out 5% → 25% → 100%, holding at least two hours at each early stage.

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
