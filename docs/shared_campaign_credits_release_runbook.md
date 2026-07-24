# Shared campaign and top-up credits release runbook

Target release: `4.5.0+77`

This runbook supplements `docs/releases.md` and
`docs/multistore_release_runbook.md`. The tag-driven CodeMagic workflows in
`codemagic.yaml` remain the only store release path.

## Product boundary

Only campaign/top-up credits are shared:

| Data or money | Scope |
| --- | --- |
| Campaign/top-up credits (`virtualBalance`) | Shared by explicitly enrolled stores with the same owner |
| Sales proceeds (`salesVirtualBalance`) | Selected store only |
| Payouts and banking details | Selected store only |
| Cash advance and repayments | Selected store only |
| Customers, ledgers, products, orders and reports | Selected store only |
| Top-up history | Store that initiated the top-up |
| Campaign and notification history | Store that sent the message |

The existing `users/{ownerStoreId}/wallet/current.virtualBalance` remains the
authoritative balance. That preserves the released app's primary-store path and
all existing payment/webhook integrations.

New shared-store clients read only
`campaignWalletBalances/{ownerStoreId}`. A secondary-store operator never gets
read access to the canonical wallet document, because that document also holds
the primary store's sales and payout fields.

## Controls

- Campaign/top-up credits are a server invariant for stores with the same
  owner. Creating an additional owned store automatically enrolls the existing
  canonical store and the new store in one transaction.
- The client sends `campaignCreditsMode: shared-v1`. A client that predates
  shared-wallet support is rejected before the store is created, so it cannot
  silently create an isolated `R0` wallet.
- The legacy Remote Config enrollment key and
  `releaseControls/sharedCampaignCredits` allowlist remain readable during the
  staged rollout, but they no longer decide whether an additional owned store
  shares credits.
- Once stores are enrolled, routing is sticky. Splitting a wallet after either
  store spends would duplicate or lose money.
- Existing multi-store owners are enrolled only by the owner-scoped migration
  script. If multiple unshared owned stores are detected, new store creation
  fails closed until that migration is completed.
- The migration requires one explicit `--owner`; it has no "all merchants"
  mode.
- A secondary balance greater than zero requires the separate
  `--allow-balance-merge` confirmation.
- Production execution requires an owner/run-scoped environment confirmation.

## Compatibility

| User/build | Not enrolled | Enrolled |
| --- | --- | --- |
| Released app on primary legacy store | Unchanged | Balance and sends still work; no shared-wallet label |
| Released multi-store app on a secondary store | Unchanged | Do not support: it reads the old isolated secondary balance |
| New shared-credit app | Unchanged | Fully supported |
| Merchant bot campaign send | Unchanged | Debits canonical shared credits |
| Paystack top-up | Unchanged | Credits canonical shared credits, attributed to initiating store |
| Customer ordering/account bot | Unchanged | Store ledgers, orders and customer balances remain isolated |

Do not migrate an existing merchant until every device/operator that may
select a secondary store has installed the shared-credit build. The
`shared-v1` creation capability is the safety gate for new stores. All
single-store merchants remain unchanged.

## Financial failure controls

- Every new-app debit has an idempotency operation ID.
- Top-ups retain Paystack's processed-reference idempotency and also write a
  campaign-credit operation.
- A campaign reserves the server-calculated worst-case cost before contacting
  Twilio. Concurrent campaigns across two stores serialize against the same
  canonical balance and cannot overspend it.
- Unused reservation credit is returned after the campaign.
- A scheduled recovery returns unused credit from reservations left active
  beyond the Function runtime.
- Twilio late-failure refunds use the wallet ID captured with the original
  charge, so a secondary-store campaign refunds the shared wallet.
- Sales-to-campaign-credit transfers debit the selected store's sales wallet
  and credit the canonical campaign wallet in one Firestore transaction.

## Local release gates

Use Java 21 for current Firebase CLI releases:

```bash
cd functions
npm ci
npm run lint -- --quiet
npm run build
npm run test:security

cd ..
JAVA_HOME=/opt/homebrew/opt/openjdk@21 \
PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH \
firebase emulators:exec \
  --project demo-spazaone-multistore \
  --only firestore,auth,storage \
  "cd functions && npm run test:rules && npm run test:stores && npm run test:migration"

flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --no-pub
flutter build appbundle --release
flutter build ios --release --no-codesign
```

Required adversarial assertions:

- a secondary operator can read the campaign-balance projection;
- that operator cannot read the canonical wallet's sales fields;
- adding a second owned store automatically enrolls the canonical and new
  stores without duplicating the balance;
- an old client and an owner with multiple unshared stores both fail before a
  new store document is created;
- concurrent debits and concurrent campaign reservations never go negative;
- duplicate operation IDs debit only once;
- cross-owner wallet pointers fail closed;
- top-up credits the canonical wallet while sale payment credits the selected
  store;
- sales transfer does not change another store's sales balance;
- refund is idempotent and returns to the charged canonical wallet;
- migration dry-run performs no writes;
- non-zero secondary balances cannot merge without explicit confirmation;
- rollback restores exact balances before activity;
- rollback refuses after any campaign-credit operation.

## Production and store rollout

1. Freeze unrelated Firebase deployments and confirm the multi-store app
   rollout state.
2. Confirm the Firebase target is exactly `pasella-ledger`.
3. Complete a managed Firestore export and record the restore location.
4. Deploy only the changed/new Functions:

   ```bash
   firebase deploy --project pasella-ledger --only \
     functions:bootstrapStoreAccess,\
functions:createStore,\
functions:inviteStoreOperator,\
functions:removeStoreOperator,\
functions:debitCampaignCredits,\
functions:transferSalesToCampaignCredits,\
functions:syncCampaignCreditProjection,\
functions:recoverExpiredCampaignReservations,\
functions:runMerchantPromotion,\
functions:messageStatusCallback,\
functions:verifyPaystackTransaction,\
functions:deleteUserAccount
   ```

5. Smoke-test an unshared test merchant. Its wallet path and balance must remain
   unchanged.
6. Deploy Firestore rules explicitly:

   ```bash
   firebase deploy --project pasella-ledger --only firestore:rules
   ```

7. Leave the legacy enrollment flag and allowlist unchanged during rollout.
   New store creation is governed by the server invariant and client
   `shared-v1` capability.
8. Follow `docs/releases.md`: merge the approved release commit to `main`, bump
   `pubspec.yaml`, then push the matching annotated
   `v<version>+<build>` tag. The tag starts both CodeMagic workflows:
   Android to Play Internal and iOS to TestFlight.
9. Install the internal build on every pilot owner/operator device and complete
   the store-switch, direct-message, campaign, top-up, refund, sales-transfer
   and payout-isolation matrix.
10. Run the owner-scoped production dry-run and archive its JSON:

    ```bash
    cd functions
    npm run shared-credits:migrate -- \
      --project pasella-ledger \
      --owner <OWNER_UID>
    ```

11. If `requiresBalanceMerge` is true, reconcile each source balance with
    top-up/campaign history before proceeding. Execute only after two people
    approve the owner, store IDs and exact before/after totals:

    ```bash
    SHARED_CREDITS_PRODUCTION_CONFIRM=pasella-ledger:<OWNER_UID> \
    npm run shared-credits:migrate -- \
      --project pasella-ledger \
      --owner <OWNER_UID> \
      --execute \
      --allow-production-write \
      --allow-balance-merge
    ```

12. Save the `runId`, verify the canonical and projection balances, then run
    one small real top-up and one small campaign from each store.
13. Promote the already-tested CodeMagic artifacts through Play/App Store
    staged rollout. Do not rebuild outside CodeMagic.
14. Confirm old clients receive the update-required error when attempting to
    add a store, while the tested `shared-v1` client creates a shared store.

## Stop and rollback

Stop expansion on any cross-store data leak, wrong-wallet debit/refund,
duplicate operation, projection mismatch, negative balance, or store-scoped
sales/payout movement.

First disable new enrollment and stop the store rollout. Existing enrolled
routing must remain sticky.

Before any campaign-credit operation, rollback can be rehearsed and executed:

```bash
npm run shared-credits:migrate -- \
  --project pasella-ledger \
  --rollback <RUN_ID>

SHARED_CREDITS_PRODUCTION_CONFIRM=pasella-ledger:<RUN_ID> \
npm run shared-credits:migrate -- \
  --project pasella-ledger \
  --rollback <RUN_ID> \
  --execute \
  --allow-production-write
```

After any operation, the script deliberately refuses rollback. Use a reconciled
forward migration; never split balances or restore the entire database merely
to disable the UI.
