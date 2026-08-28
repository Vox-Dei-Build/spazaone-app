# Native WhatsApp catalogue production controls

The native catalogue backend is dark by default. It never derives or accepts a
merchant, Meta catalogue, or sender identity from a client-side cart line.

## Rollout gates

- `WHATSAPP_CATALOG_SYNC_ENABLED` and `WHATSAPP_PRODUCT_LIST_ENABLED` must both
  be true.
- Canary mode is the default. A merchant must be in both canary scopes and the
  recipient must match a configured HMAC-SHA256 digest.
- All eligible merchants and recipients are enabled only when both
  `WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED` and
  `WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED` are true.
- `WHATSAPP_CATALOG_RECIPIENT_HASH_KEY` remains required in every enabled mode
  because delivery, cooldown, and cart records use keyed recipient digests.
- The request `senderPhoneNumberId` and `catalogId` must exactly match the
  configured production sender and catalogue.

Development retains its exact single-merchant canary rule and forbids full
rollout. Turning `WHATSAPP_PRODUCT_LIST_ENABLED` off is the delivery rollback;
it does not alter catalogue or customer data.

## Mandatory dark reconciliation

Do not enable production delivery from product-change triggers or the daily
200-product reconciler alone. Existing merchants must first complete the
authenticated, resumable full reconciliation while delivery is dark:

1. Keep `WHATSAPP_PRODUCT_LIST_ENABLED=false`. Enable the queue, catalogue
   synchronization, and its full-rollout scope.
2. Call `POST runWhatsAppCatalogFullReconciliationBotHttp` with a bounded
   `pageSize` (1–200). Save its returned `cycleId` and `nextCursorPath`; pass
   both back unchanged until each product and reverse-mapping page is scanned.
3. Let `syncWhatsAppMerchantCatalog` drain every queued Meta job. Continue the
   same cycle through verification. `verification_incomplete` is expected
   before Meta has accepted the items.
4. Continue the cycle through its repeat source scans and verification passes.
   The service detects behind-cursor insertions, source/mapping mutations,
   deleted-product mappings, invalid owner/product mappings, and changes during
   paged merchant verification. Avoid merchant catalogue writes during the
   final stabilization window; any detected change starts another pass.
5. Delivery may be considered ready only when the immutable run receipt says
   all of the following: `catalogComplete=true`, `setEqualityVerified=true`,
   `stabilityVerified=true`, `sourceCountsVerified=true`,
   `outboxDrained=true`, `pendingOutboxJobs=0`, `malformedMappings=0`, and has a
   non-empty `completionDigest`. The eligible and active/Meta-accepted totals
   must match. State and receipt completion are committed atomically.

The reverse scan records merchants even when a mapping has a malformed product
identity. Unattributable or non-canonical mapping rows are represented only by
a non-secret count and digest, block completion, and must be safely repaired or
quarantined before another pass; the reconciler never guesses their owner.
`POST getMerchantWhatsAppCatalogCompletenessBotHttp` provides the same exact
per-merchant eligibility, accepted-revision, and transient-outbox evidence used
to gate a new page-zero catalogue session. A previously issued catalogue
version can still serve deterministic More/Back pages; resolution, atomic cart
replacement, and checkout revalidate only the selected items and are not
blocked by an unrelated product still syncing.

## Atomic cart contract

`POST replaceWhatsAppCatalogCartBotHttp` is bot-authenticated. It accepts one to
ten unique lines:

```json
{
  "merchantId": "merchant-id",
  "customerId": "customer-id",
  "recipientPhone": "+27000000000",
  "senderPhoneNumberId": "meta-sender-id",
  "catalogId": "meta-catalog-id",
  "idempotencyKey": "conversation:message",
  "items": [
    {
      "retailerId": "spz_opaque-retailer-id",
      "quantity": 1,
      "expectedPriceMinor": 1000
    }
  ]
}
```

It resolves every retailer ID on the server and validates tenant ownership,
customer/recipient binding, active mapping and revision, canonical minor-unit
price, visibility, and quantity before replacing the cart in one Firestore
transaction. A successful response returns numeric `cart.total`, integer
`cart.totalMinor`, string `catalogRevision` values, and a
`nativeCartFingerprint`. The bot must pass that fingerprint and the shared
idempotency key to `checkoutCart`; checkout revalidates the cart again in the
same transaction that creates the sale.

Every non-2xx response exposes a non-secret uppercase `code`. No failed batch
performs a partial cart write.

## Required platform evidence

Before deployment, configure and verify all three Firestore TTL policies below
from fresh platform metadata in production database `(default)`:

- collection group `whatsappCatalogCartReplacements`, field `expiresAt`;
- collection group `whatsappProductListDeliveries`, field `expiresAt`;
- collection group `whatsappProductListRecipientState`, field `expiresAt`.

All three records carry a future 30-day expiry. Correctness and access control
do not depend on TTL deletion, but the cart-idempotency, native-delivery ledger,
and recipient cooldown/pause retention policies do. An `expiresAt` field in a
document is not evidence that the corresponding Firestore TTL policy is
active. The evidence must show `ACTIVE` for these exact resources; a matching
policy in another database is a failure:

```text
projects/pasella-ledger/databases/(default)/collectionGroups/whatsappCatalogCartReplacements/fields/expiresAt
projects/pasella-ledger/databases/(default)/collectionGroups/whatsappProductListDeliveries/fields/expiresAt
projects/pasella-ledger/databases/(default)/collectionGroups/whatsappProductListRecipientState/fields/expiresAt
```

`firestore.indexes.json` is the checked policy source. From the registered Vox
Dei authority checkout, validate it without writing, then obtain separate
action-time authorization before removing `--dry-run`:

```bash
/Users/admin/.codex/identity-governance/bin/codex-guard \
  firebase-deploy --project spaza-one --dry-run -- \
  --only firestore:indexes
```

After the authorized index-policy deployment finishes, capture fresh read-only
metadata with the project and database explicit:

```bash
gcloud firestore fields ttls list \
  --project pasella-ledger \
  --database='(default)' \
  --format='table(name,ttlConfig.state)'
```

Run the focused contract suite and the Firestore-emulator integration suite:

```text
npm --prefix functions run test:whatsapp-catalog
npm --prefix functions run test:whatsapp-catalog-integration
```

Also retain the completed reconciliation receipt, redacted rollout
configuration comparison, Meta item-level acceptance evidence, and the
delivery monitor result in the release evidence. Rollback is to disable native
delivery first; catalogue synchronization can then be disabled separately
after in-flight jobs are observed and handled. Neither action deletes carts,
orders, products, mappings, or customer data.
