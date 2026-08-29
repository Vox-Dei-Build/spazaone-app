# Native WhatsApp catalogue production controls

The native catalogue backend is dark by default. It never derives or accepts a
merchant, Meta catalogue, or sender identity from a client-side cart line.

> **Current executor status (2026-08-29): locally wired, externally dormant.**
> No deployment or reconciliation was performed by this migration. The only
> write-capable entry point is the checked high-level launcher
> `functions/scripts/launch-whatsapp-catalog-production.sh`. It requires the
> exact reviewed candidate and frozen current-main commits, an absolute
> no-replace receipt path, an absolute canonical candidate manifest and its
> SHA-256, then a fresh exact challenge on the controlling TTY for that one
> action. Every Firebase deployment lane and reconciliation run remains a
> separately authorized external action. The legacy
> `catalog:deploy:guard` and `catalog:reconcile:production` CLIs remain
> execute-disabled and are read-only validation surfaces.
>
> Receipt schema v4 structural validation alone is not production attestation.
> The zero-export executor owns the real action/readback and carries an opaque
> module-private attestation through receipt persistence. No dependency-injected
> output, imported legacy transport, serialized authorization, or
> caller-supplied self-consistent object/hash can acquire that attestation.

### Same-process one-shot production session

The writer does not accept an authorization receipt, digest, path, environment
variable, or other serialized value as production authority. The high-level
launcher keeps one process alive while it:

1. authenticates the exact Vox Dei candidate manifest and commit/tree;
2. rebuilds that commit from `git archive` with pinned tools and offline
   dependencies, then mounts the resulting provider package kernel read-only;
3. seals the per-session Firebase config and any lane-specific dotenv into a
   second kernel-read-only image whose source paths point only into the reviewed
   package mount; the only writable path is a separately bounded provider
   `TMPDIR`;
4. pauses on `/dev/tty` and presents the exact candidate manifest, candidate and
   governed-main commits, target, operation input, archive/package/evidence-set
   digests, receipt-path digest, recovery lineage, and deadline; and
5. mints an unforgeable module-private object only after that approval. The
   operator must type the complete displayed challenge exactly. The object is
   deleted from its private `WeakMap` before the durable intent and can be used
   once before its deadline.

The package, pending handle, and authorized handle are process memory only.
They are not written to a file, stdout, environment, command argument, or
receipt. A crash/restart loses the handle and requires a new exact package,
fresh readback, and fresh action-time approval. The receipt retains the
existing two authorization-digest fields for schema compatibility; they now
contain only the private session binding and one-shot consumption digests, not
a reusable or serialized capability.

Immediately before a provider write can start, the executor durably creates a
canonical `needs_review` receipt at a deterministic owner-only `0600` recovery
path bound to the intended final receipt path. It keeps that recovery authority
until the final receipt bytes, inode, parent directory, and no-replace link have
all been verified. Any post-dispatch failure reports the recovery path, path
and file digests, possible target path, and the exact expected final-target
file digest when final bytes existed. A second attempt for the same receipt
target is rejected while that recovery authority remains.

Recovery always inspects the possible final target first. A missing recovery
record is closable only when the target is a canonical, fully operation-bound
receipt whose file SHA-256 exactly matches the executor-reported expected
target digest. Otherwise the intact recovery authority is mandatory and the
provider is read back before any continuation decision; it is never blindly
redispatched. The `existing-code` deployment lane remains fail-closed unless
an exact final target was already verified because its pre-write environment
baseline cannot be reconstructed after a crash.

Local code review, builds, tests, and exact-package preparation do not authorize
an external action. Each external write remains a distinct approval:
integration publication, each Firestore or Functions deployment lane, full
catalogue reconciliation, Botpress deploy, WhatsApp cutover, and the controlled
live test. Catalogue reconciliation does not imply Botpress/WhatsApp cutover
authority.

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

## Scoped function deployment and environment isolation

Use the legacy guard for read-only validation and the checked high-level
launcher for an authorized native-catalog write. Together they pin the exact
Firebase CLI and gcloud paths, realpaths, SHA-256 digests, and versions, and
verify the explicit Firebase account/project and a clean Vox Dei authority
checkout. They select project `pasella-ledger` through the registered
`spaza-one` deployment target and reject any source-tree deployment dotenv.
The guard's default is local/pre-dispatch validation. The
`codex-guard firebase-deploy --dry-run` mode prints a governed command but does
not launch Firebase or exercise Firebase predeploy hooks, so independent
lint/build and generated-config tests remain mandatory.

Every helper invocation requires `--expected-app-commit` and
`--expected-current-main-commit`. It rejects a candidate value other than its
exact clean 40-character `HEAD`, or a current-main value other than the frozen
governed revision. The authority check also
requires that commit to descend from frozen app-main base
`1672538112fc4b725cd74169df9ae72802db69eb`. Before an authorized write, the
high-level executor itself queries governed GitHub metadata through the
registered Vox Dei authority and requires current remote `main` to equal that
frozen base, then repeats the check immediately before every write-capable
command. The retained production evidence must independently record the same
governed revision.

Every execute also requires a canonical, LF-terminated candidate
manifest. It binds the exact app commit, frozen governed main, Git tree SHA-1,
immutable target digest, action kind/lane/selector, action-input SHA-256, and
three distinct named SHA-256 receipts for app build/lint, catalogue tests, and
independent production review. Its file must be an absolute, normalized,
owner-controlled regular file with one link and no group/world write bit. The
expected manifest SHA-256 covers its exact canonical bytes including the final
LF. Action-time approval must name that hash and the intended action. The core
resolves authority first, then reopens and validates the manifest as its last
await before every spawn or reconciliation request; a caller-supplied
candidate commit alone is never sufficient.

Create that manifest only with `catalog:candidate:create`. The creator resolves
the clean exact Vox Dei candidate and current `main`, reads the three distinct
owner-only mode-`0600` evidence files itself, hashes their exact bytes, derives
the operation-input hash from the exact source bytes, and creates the manifest
once with mode `0600`. It accepts receipt **paths**, never receipt digests, and
does not replace an existing manifest. The three path arguments are the exact
app build/lint, WhatsApp-catalog test, and independent-production-review
receipts:

Allowed operation kinds are `function_deployment`, `policy_deployment`, and
`full_reconciliation`; the lane determines the exact selector.

```bash
npm --prefix functions run catalog:candidate:create -- \
  --operation-kind <exact-operation-kind> \
  --lane <exact-lane> \
  --expected-app-commit <clean-authority-commit> \
  --expected-current-main-commit <frozen-current-main-commit> \
  --output-path <absolute-new-candidate-manifest-path> \
  --app-build-lint-receipt-path <absolute-owner-only-build-lint-receipt> \
  --app-whatsapp-catalog-tests-receipt-path <absolute-owner-only-test-receipt> \
  --independent-production-review-receipt-path <absolute-owner-only-review-receipt>
```

For a configured Functions lane, pipe the exact non-secret dotenv bytes used by
the deployment into the creator. `existing-code` and policy lanes derive their
input bytes from the checked source and accept no piped bytes. For full
reconciliation, pipe exactly one compact JSON object in this key order, without
a trailing newline; use the same values in the later executor arguments:

```text
{"pageSize":200,"pollMs":65000,"maxSteps":10000,"maxElapsedMs":86400000,"requestTimeoutMs":570000}
```

Candidate creation is local evidence preparation. It does not authorize or
perform a deployment, reconciliation request, catalogue sync, or customer
message.

New native-catalog functions and modified existing functions are deliberately
separate lanes:

- `dark-new` deploys only the twelve new functions. It requires the exact
  non-secret configuration below on standard input. The helper stages that
  configuration with mode `0600`, seals the Firebase config and `configDir`
  into a one-use UDRO image, proves the mounted inputs reject writes with
  `EROFS`, and deletes the image/session scratch in `finally`.
- `existing-code` deploys only `getMerchantCatalogBotHttp`, `checkoutCart`,
  `cancelOrder`, `finalizeOnlinePaid`, and `updateOrderPayment`. It accepts no
  dotenv. Before it can run, the guard verifies both Firebase CLI `15.21.0` and
  that installed CLI's `inferDetailsFromExisting` remote-environment merge.
  It then seals a mode-`0600` Firebase config with no dotenv or `configDir`
  into the same one-invocation read-only provider-input image. If either the
  source dotenv check or pinned-CLI preservation contract cannot be proved,
  the lane fails closed before deployment.
- `sync-enable` later updates only the six synchronization/reconciliation
  functions. It uses the same isolated dotenv mechanism. Native customer
  delivery remains disabled.
- `controlled-delivery-enable` updates only the five newly introduced native
  delivery functions. It requires at least one exact merchant ID and at least
  one keyed recipient digest, keeps all-eligible delivery off, and enables the
  live WhatsApp message provider.
- `all-eligible-delivery-enable` updates those same five new delivery functions
  with empty controlled scopes and the full-delivery switch on.
- `delivery-disable` updates only those five new delivery functions, keeps
  catalogue synchronization live, and turns customer delivery and its message
  provider off.
- `sync-disable` is a separate final rollback lane for only the six sync
  functions. It turns queueing, synchronization, and the catalogue provider
  off. Run it only after `delivery-disable` and a reviewed outbox drain.

`getMerchantCatalogBotHttp` is intentionally absent from every environment
overlay lane. The native Botpress release must call the new merchant-catalogue
endpoints before cutover; this is what makes existing-function environment
preservation mechanically safe rather than an assumption about shared dotenv
replacement.

The checked root `firebase.json` has an unconditional first deny hook for
Functions, Firestore, and Storage. Arbitrary allow/bypass environment variables
cannot release it; guarded lanes use their exact temporary config instead.
This prevents Firebase prepare/deploy mutations through the default root
config, but it is an accidental/governance boundary rather than same-user OS
sandboxing, and Firebase may perform identity/IAM reads before a predeploy hook
stops the command.

Never put a populated `.env`, `.env.pasella-ledger`, or other deployment
dotenv in `functions/`. Never put `PASELLA_BOT_TOKEN`,
`META_CATALOG_ACCESS_TOKEN`, `META_WHATSAPP_ACCESS_TOKEN`, or
`WHATSAPP_CATALOG_RECIPIENT_HASH_KEY` in dotenv or standard input; those values
remain Secret Manager bindings.

For `dark-new`, pipe this exact non-secret payload directly to the helper,
replacing `<clean-authority-commit>` with the clean 40-character `HEAD` that
will be deployed:

```text
SPAZAONE_ENVIRONMENT=production
SPAZAONE_FIREBASE_PROJECT_ID=pasella-ledger
BUILD_COMMIT=<clean-authority-commit>
WHATSAPP_CATALOG_QUEUE_ENABLED=false
WHATSAPP_CATALOG_SYNC_ENABLED=false
WHATSAPP_CATALOG_ID=9415654481779933
WHATSAPP_CATALOG_CANARY_MERCHANT_IDS=
WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED=false
WHATSAPP_CATALOG_MAX_BATCH_SIZE=10
META_CATALOG_PROVIDER_MODE=disabled
META_GRAPH_API_VERSION=v25.0
WHATSAPP_SENDER_NUMBER_ID=343481258858230
WHATSAPP_PRODUCT_LIST_ENABLED=false
WHATSAPP_PRODUCT_LIST_CANARY_MERCHANT_IDS=
WHATSAPP_PRODUCT_LIST_FULL_ROLLOUT_ENABLED=false
WHATSAPP_CATALOG_CONTROLLED_RECIPIENT_HASHES=
WHATSAPP_PRODUCT_LIST_RECIPIENT_COOLDOWN_MS=7000
WHATSAPP_PRODUCT_LIST_MAX_ATTEMPTS=3
WHATSAPP_CATALOG_PAIR_LIMIT_PAUSE_MS=86400000
META_WHATSAPP_MESSAGE_PROVIDER_MODE=disabled
```

The dry-run and authorized execution entry points are:

```bash
npm --prefix functions run catalog:deploy:guard -- \
  --lane dark-new --expected-app-commit <clean-authority-commit> \
  --expected-current-main-commit <frozen-current-main-commit>
functions/scripts/launch-whatsapp-catalog-production.sh deployment \
  --lane dark-new --expected-app-commit <clean-authority-commit> \
  --expected-current-main-commit <frozen-current-main-commit> \
  --execute --receipt-path <absolute-new-receipt-path> \
  --candidate-manifest-path <absolute-canonical-manifest-path> \
  --expected-candidate-manifest-sha256 <approved-manifest-sha256> \
  < /absolute/path/to/reviewed-non-secret.env

npm --prefix functions run catalog:deploy:guard -- \
  --lane existing-code --expected-app-commit <clean-authority-commit> \
  --expected-current-main-commit <frozen-current-main-commit>
functions/scripts/launch-whatsapp-catalog-production.sh deployment \
  --lane existing-code --expected-app-commit <clean-authority-commit> \
  --expected-current-main-commit <frozen-current-main-commit> \
  --execute --receipt-path <absolute-new-receipt-path> \
  --candidate-manifest-path <absolute-canonical-manifest-path> \
  --expected-candidate-manifest-sha256 <approved-manifest-sha256>
```

All lanes other than `existing-code` read their exact 20-key non-secret dotenv
from standard input. Start from the payload above and change only the rows in
this matrix; every unlisted key remains byte-for-byte identical:

| Lane                           | Queue/sync/catalog full | Catalogue provider | Delivery | Delivery full | Controlled merchant/recipient scopes | Message provider |
| ------------------------------ | ----------------------- | ------------------ | -------- | ------------- | ------------------------------------ | ---------------- |
| `dark-new`                     | false                   | disabled           | false    | false         | empty / empty                        | disabled         |
| `sync-enable`                  | true                    | live               | false    | false         | empty / empty                        | disabled         |
| `controlled-delivery-enable`   | true                    | live               | true     | false         | non-empty / non-empty                | live             |
| `all-eligible-delivery-enable` | true                    | live               | true     | true          | empty / empty                        | live             |
| `delivery-disable`             | true                    | live               | false    | false         | empty / empty                        | disabled         |
| `sync-disable`                 | false                   | disabled           | false    | false         | empty / empty                        | disabled         |

Here “queue/sync/catalog full” means all three of
`WHATSAPP_CATALOG_QUEUE_ENABLED`, `WHATSAPP_CATALOG_SYNC_ENABLED`, and
`WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED`. Run every lane once without
`--execute` through its legacy validation CLI; retain that dry-run result, then
use the high-level launcher with the exact candidate and operation input. The
launcher displays and accepts the action-time TTY challenge itself. After it
crosses the write dispatch boundary, any nonzero exit, signal, or process error
is `needs_review` with `retryAllowed=false`; inspect the remote state and do not
repeat the lane.

The successful `dark-new` result includes the exact selector, clean app commit,
dotenv key names, full dotenv SHA-256, and immutable
`targetConfigurationDigestSha256`, but no values or secrets. The target digest
is identical in every function lane; runtime switches are proved by each
lane's separate receipt and fresh backend reads. Controlled-scope receipts
contain only counts and SHA-256 digests. Merchant IDs and keyed recipient
digests from the one-use input must never be copied into release evidence,
logs, shell history, or source.

After every zero-exit function write, the guard performs a fresh
`functions:list` readback through the exact Firebase project/account. It
requires every selected function once in `us-central1`. Configured lanes hash
and compare the exact 20 deployment variables on every selected function;
`BUILD_COMMIT` therefore binds the runtime configuration to the reviewed app
revision. They also require the exact per-function Secret Manager references
declared by source and reject any extra user environment variable or secret
reference. The `existing-code` lane instead captures a pre-write digest of each
selected function's complete non-platform environment and secret references,
then requires the post-write digest to be identical. Readback returns only
counts, selector, region, and digests—never environment values or secret
references. A receipt is closed only when
`closedDeploymentReceipt=true`, `readbackStatus=verified`, and (for dotenv
lanes) `cleanupStatus=deleted`. A zero deploy
exit followed by unavailable or mismatched readback is `needs_review`; do not
repeat the write to obtain a nicer receipt. Likewise, verified remote readback
plus failed ephemeral cleanup remains `receiptStatus=needs_review` and is not a
closed receipt; remove only the reported exact local directory without
re-running the write.

The reviewed candidate must be built before an authorized invocation so its
complete `lib/**/*.js` and `lib/**/*.js.map` output is present. The source
guard rejects a missing generated file, an old output left behind for a removed
TypeScript source, any other uploadable untracked or ignored file, any symlink
or special file, and any tracked byte whose Git blob is not from the exact
reviewed commit. It computes the Firebase package contract both before and
after the command; a difference is `needs_review`, never a retry signal.

The governed wrapper must run from the registered authority checkout, so the
executor preserves the authenticated Firebase `HOME`. It redirects the child
process `TMPDIR` to the session's bounded scratch directory and inventories it
after provider exit. The audit receipt retains only that bounded inventory's
SHA-256, entry count, and total byte count—not filenames or file contents. A
fresh clean-authority recheck catches any provider file
written into the checkout. Credential-store state is not copied into the
session and is never treated as deployable input evidence.
Only the pinned Firebase ignores are applied. In particular, a local
`firestore-debug.log` is uploadable and therefore rejected as an unreviewed
source file; remove it before the final build rather than broadening the ignore
contract.

Firebase CLI `15.21.0` returns normalized endpoints in the JSON output of
`functions:list`; it does not expose update time, Gen 1 build/version IDs, or
Gen 2 build/revision IDs. The guard therefore requires the exact normalized
`gcfv1`/`gcfv2` platform, selected function ID, `us-central1`, `nodejs20`, an
entry point equal to the selected ID, `codebase=default`, and the provider's
40-character lowercase `firebase-functions-hash` SHA-1 label. It also pins the
nine installed firebase-tools files that implement file selection, packaging, runtime
configuration, environment and secret hashing, and label application. The
exact 15.21.0 algorithm is:

1. SHA-1 each uploadable file's bytes, sort those file hashes, concatenate, and
   SHA-1 again for the base source hash. Paths and modes are not hash inputs.
2. For Gen 1, append `.` plus the SHA-1 of Firebase's recursively key-sorted
   `{firebase: adminSdkConfig, ...legacyRuntimeConfig}` serialization. The guard
   reads those values only inside the authorized closure, clears command
   buffers, and retains only this opaque component. Gen 2 uses the base hash.
3. SHA-1 the exact insertion-ordered codebase-level
   `wantBackend.environmentVariables` JSON and the exact source-ordered
   secret-name-to-resolved-version JSON, concatenate them after the applicable
   source hash, and SHA-1 once more. The result must equal the remote label on
   every selected function.

Configured lanes reconstruct the backend environment from the checked 20-key
dotenv followed by `FIREBASE_CONFIG` and `GCLOUD_PROJECT`, in the same order as
Firebase CLI `15.21.0`. The no-dotenv `existing-code` backend environment is
only `FIREBASE_CONFIG` followed by `GCLOUD_PROJECT`. Eventarc's source value and
the existing-code lane's preserved remote endpoint variables are added or
merged after Firebase establishes the codebase-level backend environment; they
are therefore not provider-label inputs. They remain independently covered by
the exact endpoint-environment preservation/readback assertion. The candidate
source contract rejects any `firebase-functions/params` module reference: a
future non-internal resolved parameter would add another backend hash input and
must first be modeled and reviewed explicitly. Secret order is the checked
source declaration order and every version must be the resolved numeric
version returned after deployment. A stale candidate, wrong
selector/codebase/region/runtime/entry point, reordered or wrong secret,
changed backend environment, or wrong provider label makes
`candidateSourceBindingMatches=false` and prevents receipt closure. If a future
Firebase API changes map or array ordering so the exact input cannot be
reconstructed, the guard deliberately stops in `needs_review` rather than
claiming source identity.

Gen 2 identity also includes its safe immutable storage or repository source
fields. Gen 1's normalized endpoint exposes only a signed `sourceUploadUrl`;
the guard neither requires nor retains that URL. Each per-function identity and
the aggregate
`buildIdentitySetSha256` readback field and the enclosing typed-evidence digest
are SHA-256 only, so neither the provider SHA-1 nor a source URL appears in the
receipt. Missing or invalid normalized identity makes
`buildIdentitiesComplete=false` and fails receipt closure. Function evidence
also binds the exact lane, selector, project, region, function count, complete
identity set, exact environment digest, expected environment digest, environment
shape, secret-reference match, candidate source-contract SHA-256, packaged and
generated file counts, and candidate-derived provider-binding-set SHA-256. This
proves that the Firebase deployment label came from the exact candidate
source/config inputs and normalized endpoint identity; it does not claim
unavailable provider build or revision metadata.

Firestore rules evidence binds the exact rules lane, selector, project,
database, local source SHA-256, identical active source SHA-256, and active
ruleset resource identity. Index/TTL evidence binds the exact lane, selector,
project, database, complete local and remote index-configuration digests and
counts, complete field-override counts, complete local and remote TTL contract
digests and counts, and the exhaustive remote TTL count in `ACTIVE` state. Any
hash-only object, missing or extra evidence key, mismatched count or digest, or
evidence tag from another action fails before a receipt can be sealed.

The attested reconciliation evidence input must be the complete finalized
redacted artifact collected inside that high-level closure, not a caller-provided
artifact or hash. Its exact keyset and canonical seal bind the app commit,
immutable target digest, Firebase project, Meta catalogue and sender IDs,
cycle/scan/set-equality/stability/source-count completion, mutation generation,
completion digest, zero incomplete/malformed counts, and a complete drained
outbox status partition. The structural validator already derives and
cross-binds the artifact receipt digest, completion digest, and enclosing
evidence digest, but that validation alone is deliberately insufficient to
persist a verified receipt.

Each helper result is truthful per-invocation evidence, not a composite remote
deployment receipt. Retain the distinct authorized `dark-new` and
`existing-code` results and independently collected remote deployment metadata.
The production readiness evidence must bind both exact selectors plus the
separate Firestore rules deployment and index/TTL-policy receipt; never infer
one completed lane or policy write from another.

A dry-run command failure is a blocked validation failure. After `--execute`,
any process error, signal, or nonzero exit is instead `needs_review` and
ambiguous because Firebase may have applied part of the selector; it must never
be retried blindly. If the Firebase command exits zero but deletion of the
ephemeral directory fails, the deploy result remains truthfully successful and
reports `cleanupStatus=needs_review`, the exact local directory, and the
single-directory cleanup action. Review and remove that directory without
re-running the deployment.

The target digest algorithm is SHA-256 hex over the UTF-8 bytes of
insertion-order `JSON.stringify` for exactly this object (no trailing newline):

```json
{
  "schemaVersion": 1,
  "SPAZAONE_ENVIRONMENT": "production",
  "SPAZAONE_FIREBASE_PROJECT_ID": "pasella-ledger",
  "WHATSAPP_CATALOG_ID": "9415654481779933",
  "WHATSAPP_CATALOG_MAX_BATCH_SIZE": "10",
  "META_GRAPH_API_VERSION": "v25.0",
  "WHATSAPP_SENDER_NUMBER_ID": "343481258858230",
  "WHATSAPP_PRODUCT_LIST_RECIPIENT_COOLDOWN_MS": "7000",
  "WHATSAPP_PRODUCT_LIST_MAX_ATTEMPTS": "3",
  "WHATSAPP_CATALOG_PAIR_LIMIT_PAUSE_MS": "86400000"
}
```

`BUILD_COMMIT`, enable/provider switches, rollout/canary/recipient scope, and
secret bindings are deliberately excluded. The fresh backend configuration
collector must recompute this exact digest from its source-read immutable
values; app deployment and reconciliation receipts use the same local constant
and the readiness gate requires all three values to match. Deploy Firestore
rules and index/TTL policy separately; never add either to a function selector
implicitly.

## Mandatory dark reconciliation

Do not enable production delivery from product-change triggers or the daily
200-product reconciler alone. Existing merchants must first complete the
authenticated, resumable full reconciliation while delivery is dark:

1. Keep `WHATSAPP_PRODUCT_LIST_ENABLED=false` and
   `META_WHATSAPP_MESSAGE_PROVIDER_MODE=disabled`. In a separately authorized
   `sync-enable` deployment, change only
   `WHATSAPP_CATALOG_QUEUE_ENABLED=true`,
   `WHATSAPP_CATALOG_SYNC_ENABLED=true`,
   `WHATSAPP_CATALOG_FULL_ROLLOUT_ENABLED=true`, and
   `META_CATALOG_PROVIDER_MODE=live` in the exact payload above. Pipe it to:

   ```bash
   npm --prefix functions run catalog:deploy:guard -- \
     --lane sync-enable --expected-app-commit <clean-authority-commit> \
     --expected-current-main-commit <frozen-current-main-commit>
   functions/scripts/launch-whatsapp-catalog-production.sh deployment \
     --lane sync-enable --expected-app-commit <clean-authority-commit> \
     --expected-current-main-commit <frozen-current-main-commit> \
     --execute --receipt-path <absolute-new-receipt-path> \
     --candidate-manifest-path <absolute-canonical-manifest-path> \
     --expected-candidate-manifest-sha256 <approved-manifest-sha256> \
     < /absolute/path/to/reviewed-non-secret.env
   ```

   Retain the successful non-dry-run `sync-enable` result separately. It binds
   the exact six-function selector, project target, app commit, isolated dotenv
   SHA-256 and key names, immutable target digest, activation flags, and cleanup
   status. Combine it with independently collected Firebase deployment
   ID/timestamp/hash evidence. Its timestamp must be after both dark deployment
   lanes and the Firestore policy write, and before reconciliation starts; the
   dark deployment receipt is not evidence that this later mutation occurred.

2. Do not use raw `curl` or manually save reconciliation cursors. Run the
   operator helper from the exact deployed app revision:

   ```bash
   npm --prefix functions run catalog:reconcile:production -- \
     --expected-app-commit <clean-authority-commit> \
     --expected-current-main-commit <frozen-current-main-commit>
   functions/scripts/launch-whatsapp-catalog-production.sh reconciliation \
     --expected-app-commit <clean-authority-commit> \
     --expected-current-main-commit <frozen-current-main-commit> \
     --execute --receipt-path <absolute-new-receipt-path> \
     --candidate-manifest-path <absolute-canonical-manifest-path> \
     --expected-candidate-manifest-sha256 <approved-manifest-sha256>
   ```

   It resolves `PASELLA_BOT_TOKEN` internally from Secret Manager using the
   explicit `pasella-ledger` project and registered Firebase account. The
   immutable target digest is derived internally from the same checked local
   constant as the deployment guard; no caller-supplied digest is accepted.
   Every request carries that expected commit and digest. Before any state read,
   enqueue, or write, the server verifies its exact deployed `BUILD_COMMIT` and
   recomputes the immutable target digest from its runtime project, catalogue,
   sender, and fixed configuration. Every successful page echoes the non-secret
   deployed commit, digest, project, catalogue, and sender bindings; the helper
   exact-compares them before accepting a page. The server, not the caller,
   owns the cycle ID, cursor, phase, page size, and page count. A successful
   nonterminal page returns only an opaque SHA-256 continuation-state digest;
   merchant details and cursor paths are stripped before the response. The
   credential and continuation digest stay in process memory only.

   Cycle creation atomically stores the exact deployed commit, immutable target
   digest, project, catalogue, and sender binding in both the global state and
   per-cycle run document. Every inspect, continue, and page transition requires
   both copies to exist and match the current verified runtime. A later app
   deployment cannot adopt a stranded cycle by minting a new continuation
   digest around old state.

   An ambiguous network, timeout, 5xx, malformed-success, oversized response,
   explicit post-page rejection, elapsed limit, or step limit stops immediately
   as `needs_review` with `retryAllowed=false`. Never start a fresh cycle or
   reuse a saved cursor. After inspecting the recorded run and confirming that
   the same exact deployed revision/target should continue, use the one explicit
   reviewed recovery switch:

   ```bash
   functions/scripts/launch-whatsapp-catalog-production.sh reconciliation \
     --expected-app-commit <clean-authority-commit> \
     --expected-current-main-commit <frozen-current-main-commit> \
     --reviewed-resume --execute \
     --prior-needs-review-receipt-path <absolute-prior-receipt-path> \
     --expected-prior-needs-review-receipt-sha256 <prior-receipt-sha256> \
     --receipt-path <absolute-new-receipt-path> \
     --candidate-manifest-path <absolute-canonical-manifest-path> \
     --expected-candidate-manifest-sha256 <approved-manifest-sha256>
   ```

   The recovery phase first performs only an authenticated `inspect_recovery`.
   The same-process session binds a private readback provider before inspection
   and accepts no caller-supplied recovery object or digest. The provider is
   invoked once, its
   exact minimal facts are canonicalized, and the executor derives the SHA-256
   before deciding either completion or continuation. If the server already
   committed `status=complete`, inspection validates both stored bindings and
   the exact zeroed outbox/completion proof, then seals the receipt from the
   original stored cycle start/completion timestamps without another write.
   If the cycle is incomplete—including the important zero-page case in which
   initialization committed but the first page response was lost—the same
   invocation displays a new TTY challenge bound to the exact recovery readback
   and continuation-state digest. Only that fresh one-shot capability can send
   `continue`; restarting the process or reusing an old challenge cannot
   continue it. If recovery proves the cycle already complete, the executor
   persists a `recovered_verified` receipt with
   `remoteWriteAttempted=false` and sends no continuation request.
   Direct, inspected-recovery, and continued runs share the same candidate
   operation-input hash; recovery mode, prior receipt, exact readback, and
   continuation digest are bound separately in the private session and receipt
   lineage. This prevents a caller from self-attesting a different recovery
   candidate.
   The CLI accepts no cycle, cursor, target digest, merchant, recipient, or
   credential argument.
   The authority checkout and governed current-main binding are rechecked
   immediately before every page request. Failure before the first request is
   blocked without server mutation; failure after any acknowledged page is
   `RECONCILIATION_AUTHORITY_RECHECK_NEEDS_REVIEW`, ambiguous, and must not be
   restarted blindly because the cycle is already partially written.

3. Let `syncWhatsAppMerchantCatalog` drain every queued Meta job. Continue the
   same in-memory cycle through verification. `verification_incomplete` is
   expected before Meta has accepted the items; the helper waits between
   verification/drain passes.
4. Continue the cycle through its repeat source scans and verification passes.
   The service detects behind-cursor insertions, source/mapping mutations,
   deleted-product mappings, invalid owner/product mappings, and changes during
   paged merchant verification. Avoid merchant catalogue writes during the
   final stabilization window; any detected change starts another pass.
5. Delivery may be considered ready only when the service returns its strict
   terminal completion and the helper emits a receipt bound to the exact
   `firebaseProjectId`, `appCommit`, and `targetConfigurationDigestSha256`.
   The receipt must contain `scanScope=all_eligible_merchants`, both scan flags,
   `outboxDrained=true`, and the real distinct `pending`, `retry`, `processing`,
   and `submitted` outbox counts at zero as `outboxPendingCount`,
   `outboxRetryCount`, `outboxProcessingCount`, and `outboxSubmittedCount`.
   It must also contain the retained terminal audit-row counts as
   `outboxActiveCount`, `outboxDeletedCount`, and `outboxRejectedCount`, plus
   the actual (possibly non-zero) `outboxTotalCount`, `outboxUnknownCount=0`,
   and `outboxCountsVerified=true`.
   It must also contain `catalogComplete=true`,
   `setEqualityVerified=true`, zero incomplete merchants, zero malformed
   mappings, a non-empty `completionDigest`, start/completion/verification
   timestamps, and `redactedReceiptSha256`. The four in-flight counts, three
   recognized terminal counts, and an unfiltered total are separate Firestore
   aggregate queries. All seven recognized counts must sum to the total; any
   missing, unknown, malformed, or concurrently changing status produces a
   non-zero unknown delta or failed count verification and blocks completion.
   Terminal `active`, `deleted`, and `rejected` audit rows are not jobs still in
   flight and are retained. The receipt is not inferred from a single filtered
   count or an invented worker metric.
   The terminal service result also requires stability, current source counts,
   empty outbox statuses, and exact
   eligible-to-active/Meta-accepted set equality. State and service completion
   are committed atomically.

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

## Delivery cutover and rollback

The dark deployment and reconciliation receipt do not enable customer
delivery. After all required app, Firestore, Botpress, Meta reconciliation, and
configuration-drift evidence is closed, the remaining mechanically guarded
sequence is:

1. With separate cutover authorization, dry-run and then execute
   `controlled-delivery-enable` using the exact tested merchant scope and keyed
   controlled-recipient digests. Verify fresh remote configuration plus the
   controlled multi-merchant/device evidence. Do not put either scope in the
   retained receipt; retain its counts and digests only.
2. With separate all-eligible authorization, dry-run and then execute
   `all-eligible-delivery-enable`. Verify fresh remote configuration shows
   delivery enabled, empty controlled scopes, full delivery enabled, and both
   providers live on the exact five-function selector.
3. To stop customer delivery, dry-run and then execute `delivery-disable` on
   that same five-function selector. This is the first rollback action and does
   not stop catalogue synchronization or mutate catalogue/customer data.
4. Only after fresh aggregate evidence accounts for all `pending`, `retry`,
   `processing`, and `submitted` outbox jobs, matches the unfiltered total, and
   also accounts for retained `active`, `deleted`, and `rejected` terminal rows
   with zero unknown statuses may a separately authorized `sync-disable` run on
   the six sync functions. Never infer drain from one status query and never
   combine delivery disable with sync disable.

Each command uses the same syntax as the earlier examples, replacing `--lane`
with the exact lane above and piping its matrix-conformant dotenv on standard
input. Every execute receipt must bind the exact project, clean app commit,
immutable target digest, selector, dotenv SHA-256, rollout booleans, scope
counts/digests, and cleanup status. If the command result is ambiguous, stop at
`needs_review`; a blind repeat can produce a partial multi-function rollout.
Use the exact recovery fields printed with that result and a fresh closure
receipt path; do not delete or rename the hidden recovery record:

```bash
functions/scripts/launch-whatsapp-catalog-production.sh deployment \
  --recover-needs-review --execute --lane <exact-original-lane> \
  --expected-app-commit <clean-authority-commit> \
  --expected-current-main-commit <frozen-current-main-commit> \
  --prior-needs-review-receipt-path <reported-recovery-path> \
  --expected-prior-needs-review-receipt-path-sha256 <reported-path-sha256> \
  --expected-prior-needs-review-receipt-sha256 <reported-receipt-sha256> \
  --expected-prior-needs-review-receipt-file-sha256 <reported-file-sha256> \
  --prior-target-receipt-path <reported-target-path> \
  --expected-prior-target-receipt-path-sha256 <reported-target-path-sha256> \
  --expected-prior-target-receipt-file-sha256 <reported-target-file-sha256> \
  --receipt-path <absolute-new-closure-receipt-path> \
  --candidate-manifest-path <absolute-canonical-manifest-path> \
  --expected-candidate-manifest-sha256 <approved-manifest-sha256>
```

Omit only the expected target-file argument when the failure report contains
`null` because no final bytes had reached the persistence phase. Configured
function lanes still receive their original exact dotenv on standard input.

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

`firestore.rules` and `firestore.indexes.json` are checked policy sources. Use
the same guard rather than a raw Firebase command. It pins the exact clean app
revision/current governed main, source file SHA-256, project
`pasella-ledger`, database `(default)`, selector, and (for indexes) the exact
three-entry TTL contract digest. Dry-run both sources first, then obtain
separate action-time authorization for each `--execute`:

```bash
npm --prefix functions run catalog:deploy:guard -- \
  --lane firestore-rules --expected-app-commit <clean-authority-commit> \
  --expected-current-main-commit <frozen-current-main-commit>
npm --prefix functions run catalog:deploy:guard -- \
  --lane firestore-indexes --expected-app-commit <clean-authority-commit> \
  --expected-current-main-commit <frozen-current-main-commit>

functions/scripts/launch-whatsapp-catalog-production.sh deployment \
  --lane firestore-rules --expected-app-commit <clean-authority-commit> \
  --expected-current-main-commit <frozen-current-main-commit> \
  --execute --receipt-path <absolute-new-receipt-path> \
  --candidate-manifest-path <absolute-canonical-manifest-path> \
  --expected-candidate-manifest-sha256 <approved-manifest-sha256>
functions/scripts/launch-whatsapp-catalog-production.sh deployment \
  --lane firestore-indexes --expected-app-commit <clean-authority-commit> \
  --expected-current-main-commit <frozen-current-main-commit> \
  --execute --receipt-path <absolute-new-receipt-path> \
  --candidate-manifest-path <absolute-canonical-manifest-path> \
  --expected-candidate-manifest-sha256 <approved-manifest-sha256>
```

Every policy execute is write-capable: a nonzero exit or process uncertainty is
`needs_review`, `retryAllowed=false`, and must not be repeated blindly. A zero
exit is still not a closed policy receipt until readback matches. Rules
readback resolves the active `cloud.firestore` release/ruleset and hashes its
exact `firestore.rules` content. Index readback requires the exact remote TTL
field contract and all three resources in `ACTIVE`. If immediate readback is
still provisioning or unavailable, the execute receipt says
`readbackStatus=needs_review`; repeat only the read-only check later:

```bash
npm --prefix functions run catalog:deploy:guard -- \
  --lane firestore-rules --expected-app-commit <clean-authority-commit> \
  --expected-current-main-commit <frozen-current-main-commit> \
  --readback-only
npm --prefix functions run catalog:deploy:guard -- \
  --lane firestore-indexes --expected-app-commit <clean-authority-commit> \
  --expected-current-main-commit <frozen-current-main-commit> \
  --readback-only
```

For either the immediate or later readback, retain the policy receipt only when
`readbackStatus=verified`, `closedPolicyReceipt=true`, and
`receiptStatus=verified`.

Run the focused contract suite and the Firestore-emulator integration suite:

```text
npm --prefix functions run test:whatsapp-catalog
npm --prefix functions run test:whatsapp-catalog-integration
```

The integration script owns `firebase emulators:exec` for the isolated
`demo-spazaone-native-cart` project. The test itself rejects any invocation
without a loopback `FIRESTORE_EMULATOR_HOST` and that exact demo project before
Firebase Admin initializes; do not bypass the package script with a bare
`node --test` command.

Also retain the completed reconciliation receipt, redacted rollout
configuration comparison, Meta item-level acceptance evidence, and the
delivery monitor result in the release evidence. Rollback is to disable native
delivery first; catalogue synchronization can then be disabled separately
after in-flight jobs are observed and handled. Neither action deletes carts,
orders, products, mappings, or customer data.

For this staged deployment, customer delivery is initially off. If sync must be
rolled back after `sync-enable`, first run `delivery-disable`, then inspect and
account for every nonterminal outbox status before using the separate
`sync-disable` lane; the four in-flight plus three terminal status counts must
also equal the unfiltered total with zero unknown rows. Do not use `dark-new`
as an inferred composite rollback;
its twelve-function selector can create an unnecessary partial-write surface.
Reverting modified
existing-function code requires a separately verified prior Vox Dei commit and
the `existing-code` lane, still with no dotenv overlay. Firestore rules and
index/TTL policy rollback are separate governed actions. Do not delete
functions, reconciliation state, mappings, Meta items, carts, orders, products,
or customer data as a rollback shortcut; any deletion requires its own explicit
destructive authorization.
