# Botpress multi-store selection contract

The Firebase endpoint `fetchMerchantDetails` is the source of truth for a
merchant-operator phone number. Every request must include
`X-Pasella-Bot-Token`.

## Resolve an operator

```http
GET /fetchMerchantDetails?number=whatsapp:%2B27821234567
X-Pasella-Bot-Token: <secret>
```

One active store returns the existing `merchantDetails` response. Multiple
active stores return HTTP 200:

```json
{
  "requiresStoreSelection": true,
  "prompt": "Which store would you like to use?",
  "stores": [
    {
      "merchantId": "store-a",
      "shopName": "Alpha Shop",
      "role": "admin",
      "choice": "1"
    },
    {
      "merchantId": "store-b",
      "shopName": "Beta Shop",
      "role": "operator",
      "choice": "2"
    }
  ]
}
```

Choices are sorted by shop name and then store ID, so a numbered retry is
deterministic. Resolve the reply using either:

```http
GET /fetchMerchantDetails?number=...&storeChoice=1
GET /fetchMerchantDetails?number=...&storeId=store-a
```

An unassigned `storeId` returns 403. A disabled membership is absent from the
choices and cannot be selected.

## Workflow behavior

1. Call the endpoint at the start of a merchant conversation and after a
   `switch store` intent.
2. If `requiresStoreSelection` is true, render `prompt` and the numbered store
   labels. Store the returned choices in conversation state; do not infer a
   store from list position without using the returned `choice` value.
3. Accept only an exact choice value or store label match. On ambiguity, repeat
   the list. Never default to the first store.
4. Resolve again with `storeChoice` or `storeId`. Persist the returned
   `merchantDetails.merchantId` as the active store for that conversation.
5. Pass that merchant/store ID to every downstream catalog, ledger, order,
   promotion, and unread-message endpoint.
6. Clear active-store state when the operator asks to switch, the conversation
   expires, or access resolution returns 403/404.
7. Do not expose raw phone hashes, invite IDs, or other operators to the user.

## Bot release test matrix

- legacy phone with no v2 metadata resolves through the existing fallback;
- one active store resolves without a new prompt;
- two active stores prompt in deterministic order;
- numeric choice selects the intended store;
- explicit allowed store ID succeeds;
- unassigned store ID returns 403;
- disabled membership disappears immediately;
- store switch replaces all downstream merchant IDs;
- malformed choice repeats the prompt and performs no mutation;
- bot secret missing/incorrect returns 401.

## Current Botpress scope

The two bots currently present in the Pasella Botpress workspace are
customer-commerce bots. Their shop selection is customer-facing: they resolve
merchant candidates and prompt when more than one shop is available. They are
not merchant-operator surfaces and must not be repurposed or published with an
operator workflow for this release.

The operator contract above is implemented in the Firebase endpoint and in the
prepared Botpress source branch `codex/multistore-operators-bot`. The backend
client accepts an explicit `storeId`/`storeChoice`, models the selection-required
response, and refuses to choose the first store when more than one operator
membership is returned. This keeps a future merchant-operator bot safe without
changing the live customer bot.

For this release, the bot gate is:

1. keep both deployed customer bots unchanged;
2. verify customer shop selection still prompts for multiple candidates;
3. run the source tests, type checks, Botpress build, and ADK validation;
4. do not deploy the prepared operator integration until a dedicated
   merchant-operator bot or intent is approved and the Firebase backend is live.

When that dedicated surface exists, complete the operator matrix above in a
non-production Botpress pilot before any channel is attached.
