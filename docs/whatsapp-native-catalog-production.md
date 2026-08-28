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

Before deployment, configure and verify a Firestore TTL policy for collection
group `whatsappCatalogCartReplacements` on field `expiresAt`. Correctness and
access control do not depend on TTL deletion, but the 30-day idempotency receipt
retention policy does.

Run the focused contract suite and the Firestore-emulator integration suite:

```text
npm --prefix functions run test:whatsapp-catalog
npm --prefix functions run test:whatsapp-catalog-integration
```
