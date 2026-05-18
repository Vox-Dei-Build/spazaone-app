# Connect Thread Tenant Isolation & Bot Transparency — Plan

Status: Locked for execution
Owner: TBD
Related fix already shipped: removal of body-content filter in
`lib/services/twilio_service.dart` (visibility of Botpress/Twilio replies).

## Locked decisions

- **Inbound routing lookback window:** 30 days. Tunable knob, not a
  hardcoded constant. Revisit after the first two weeks of real inbound
  data.
- **Ambiguous-inbound policy:** Option D — best-guess + audit. The webhook
  picks the most-recent-outbound merchant and writes the inbound under
  only that merchant. Every routing decision is recorded on the message
  doc as `routing.rule` (`active-thread` | `most-recent-outbound` |
  `first-contact`) plus `routing.candidates: [merchantUid…]` so ops can
  trace and correct misattributions. Cross-merchant collisions are
  explicitly being treated as an edge case for the initial release;
  ambiguity is expected to decay over time because once a thread exists
  in Firestore under a specific merchant, subsequent inbounds attach to
  that existing thread rather than being re-guessed from scratch.
- **Rollout shape:** shadow-mode writes first (functions live, client
  still reads from Twilio), then backfill, then flag-gated read-path
  cutover, then credential removal + token rotation. New merchants from
  the marketing push flip to the new read path on day one; existing
  merchants migrate gradually.
- **Subaccounts:** not required. Not on the roadmap unless a future
  Twilio-layer ops/compliance need surfaces.

---

## 1. Problem

Pasella's Connect tab shows the SMS/WhatsApp/Botpress thread for a given
customer of a given merchant. Today all message reads go directly to the
Twilio REST API using a **single shared Twilio account** (one
`TWILIO_ACCOUNT_SID` / `TWILIO_AUTH_TOKEN`, one `TWILIO_NUMBER`, one
`TWILIO_MESSAGING_SERVICE_ID`, loaded from Remote Config for every merchant).
Thread scoping is purely by phone number: `Messages.json?To=<customer>` and
`Messages.json?From=<customer>`.

This produces three real, observed problems:

1. **Cross-merchant leak (confirmed in production).** When two merchants have
   ever messaged the same end-user number, each merchant's Connect thread
   for that customer shows the *union* of both merchants' outbound traffic.
   Twilio has no field on the message resource that ties it back to "which
   merchant sent this," because from Twilio's perspective there is only the
   one account and one sender. No `From=` / `MessagingServiceSid` filter can
   separate them; they are literally identical on the wire.

2. **Historical mess.** Every message ever sent or received through this
   account already lives in Twilio with no merchant tag. Any future
   tenant-isolation scheme has to decide what to do with that history.

3. **Bot transparency gap.** Merchants need to see the conversation between
   their customer and the Botpress bot inside Connect. Today the bot side is
   fetched separately from Botpress and merged in the client. When the bot
   sends via the shared Twilio account, those messages also surface to *other*
   merchants who have ever messaged the same customer. From a single
   merchant's point of view it is impossible to distinguish "bot replied to my
   customer" from "another merchant replied to this person." Even the AI
   badge gets misapplied — outbound WhatsApp defaults to `isAI=true` in the
   merge layer.

## 2. Goals & non-goals

### Goals
- Each merchant sees only their own customers' threads, with no cross-merchant
  leakage.
- Each thread shows the merchant's outbound, the customer's inbound, and the
  Botpress bot's contributions (when the bot acted on this merchant's behalf
  for this customer), in correct chronological order, with correct
  attribution.
- Historical messages from before the cutover remain visible to the merchant
  who legitimately owns them (best-effort), and are *not* visible to other
  merchants.
- No regression to media handling, ordering, or read-state heuristics.
- Twilio account credentials stop being shipped to client devices via Remote
  Config (defense-in-depth — addressed alongside, not after).

### Non-goals (for this plan)
- Per-merchant Twilio Subaccounts are **not required** by this design. With
  Firestore as the source of truth for reads and the `sendMessage` function
  as the source of truth for writes + attribution, the shared Twilio account
  becomes a transport detail. Whether that transport is one account or N
  subaccounts has no effect on correctness, on tenant isolation, on the read
  model, or on security rules. Subaccounts would only add Twilio-layer
  *operational* isolation (per-merchant billing visibility, per-merchant
  quota/throttling, abuse containment, regulatory separation). Revisit only
  if one of those ops needs materialises.
- Re-implementing Botpress payload rendering. The blank-bubble fallback work
  on `main` remains.
- Search, indexing, or analytics over conversation history (future).

## 3. Chosen direction

**Move the Connect thread to a Firestore-backed message store, written by
server-side functions on every send/receive, and stop reading conversation
history directly from Twilio on the client.**

Path summary:

```
Send path  (client)  --calls-->  Cloud Function "sendMessage"
                                   - authenticates merchant
                                   - calls Twilio
                                   - writes Firestore record under
                                     users/{merchantUid}/customers/{customerId}/messages/{sid}

Inbound    (Twilio webhook) -->  Cloud Function "twilioInboundWebhook"
                                   - resolves merchant by routing rules (see §5)
                                   - writes Firestore record under that merchant's customer

Bot path   (Botpress webhook / bridge) -->
                                  Cloud Function "botpressEventWebhook"
                                   - resolves merchant from conversation tags
                                   - writes Firestore record with channel='botpress'
                                     and senderRole='bot' under that merchant's customer

Read path  (client)  --streams--> users/{merchantUid}/customers/{customerId}/messages
                                   - ordered by dateSent
                                   - merchant can only see their own subtree
                                     (Firestore security rules)
```

This solves all three problems at once: tenant isolation is enforced by
Firestore rules; bot messages are recorded with explicit merchant attribution
at write time; and the historical-messages question is reduced to a one-time
backfill (§7).

## 4. Data model

### 4.1 Firestore path
```
users/{merchantUid}
  customers/{customerId}
    messages/{messageId}
```

`messageId` rules:
- For Twilio-originated rows: use Twilio `sid` (idempotent, dedup-friendly).
- For Botpress-originated rows: use Botpress `messageId` prefixed with `bp_`
  so it cannot collide with a Twilio sid.

### 4.2 Document schema
```jsonc
{
  "id": "SMxxxx" ,             // matches messageId / doc id
  "channel": "sms" | "whatsapp" | "botpress",
  "direction": "outbound" | "inbound",
  "senderRole": "merchant" | "customer" | "bot",
  "body": "…",                 // rendered text (Botpress payload rendering already handled on main)
  "payload": { … },            // optional, raw provider payload for Botpress / rich types
  "mediaUrls": ["https://…"],  // resolved URLs; may be empty
  "dateSent": Timestamp,
  "status": "queued" | "sent" | "delivered" | "failed" | "read",
  "twilio": {                  // present when channel != "botpress"
    "sid": "SMxxxx",
    "from": "+27…",
    "to":   "+27…",
    "messagingServiceSid": "MGxxxx"
  },
  "botpress": {                // present when channel == "botpress"
    "conversationId": "…",
    "messageId": "…",
    "userId": "…"
  },
  "isAI": false,               // explicit, written by the function — no client guessing
  "createdAt": serverTimestamp,
  "updatedAt": serverTimestamp,
  "schemaVersion": 1
}
```

Notes:
- `senderRole` removes the current ambiguity where the client has to *guess*
  AI vs merchant from message body / template-match.
- `isAI` is derived once at write time (`senderRole == 'bot'`) and never
  recomputed on the client.
- `status` updates flow through a separate Twilio Status Callback webhook
  (§5.3); the function does a targeted update of the same document.

### 4.3 Indexes
- Composite index on `(customerId asc, dateSent asc)` is implicit because the
  collection is already scoped under the customer. No extra indexes needed
  for the default view.
- For the badge / unread count (`users/{uid}.unreadMessages`) keep the current
  document, but update it from the function rather than the client.

### 4.4 Security rules (sketch)
```
match /users/{uid}/customers/{cid}/messages/{mid} {
  allow read: if request.auth != null && request.auth.uid == uid;
  allow write: if false; // writes only from privileged backend
}
```
Client cannot write directly; only Cloud Functions (admin SDK) can.

## 5. Backend functions

### 5.1 `sendMessage` (HTTPS Callable)
Replaces the current client-side Twilio send. Inputs:
`{ customerId, channel: 'sms'|'whatsapp', body, mediaUrls? }`.

Steps:
1. AuthN: must have a Firebase auth uid; uid == merchant.
2. AuthZ: read `users/{uid}/customers/{customerId}` to confirm ownership.
3. Resolve the customer's E.164 from Firestore (not from the client request).
4. Call Twilio `Messages.create` with the shared account creds.
5. Write the Firestore message doc with `senderRole='merchant'`,
   `direction='outbound'`, `status='queued'`, the returned `sid`, etc.
6. Return `{ sid }`.

Effect: removes Twilio creds from the client send path entirely.

### 5.2 `twilioInboundWebhook` (HTTPS)
Configured as the Twilio inbound webhook on `TWILIO_NUMBER` for both SMS and
WhatsApp.

Routing problem (the hard part): the inbound payload tells you
`From=<customerE164>`, `To=<TWILIO_NUMBER>`. That does **not** identify a
merchant on its own. Resolution rules, applied in order, first match wins:

1. **Active-thread rule.** Look at outbound messages to that `From` number
   in the last N days (start with 30) across all merchants. If exactly one
   merchant has any outbound to that number in the window, write the inbound
   under that merchant. (This is the dominant case in practice.)
2. **Bot-handover rule.** If a Botpress conversation is currently open for
   that number, and the conversation's tags record the originating merchant
   (see §5.4), write under that merchant.
3. **Ambiguity.** If two or more merchants both have recent outbound to that
   number, write the inbound under **each** of them, with
   `routing.ambiguous: true` and the list of candidates. A merchant seeing
   an ambiguous inbound gets a small UI affordance ("This message could not
   be conclusively attributed"). This is rare but must not be silently
   dropped or silently misattributed.
4. **No match.** Write to a dead-letter collection
   `inboundUnattributed/{sid}` and alert. Never lose the message.

The active-thread query is bounded and cheap if we maintain a small
`customerNumberIndex/{e164}` mapping (latest merchant, last contact time,
candidates). The function updates that index on every outbound send.

### 5.3 `twilioStatusWebhook` (HTTPS)
Configured as the Twilio status callback. Updates `status` on the matching
Firestore doc by `sid`. Idempotent.

### 5.4 `botpressEventWebhook` (HTTPS)
Configured on Botpress to forward inbound/outbound conversation events.
Botpress conversations already carry `tags['whatsapp:userPhone']`. We will
extend tagging at conversation-creation time to also include
`tags['pasella:merchantUid']`. Resolution:

- For events with `pasella:merchantUid` tag: write under that merchant.
- For events without (legacy conversations): apply the same routing rules as
  §5.2 (active-thread / ambiguity / dead-letter).

Bot replies are written with `channel='botpress'`, `senderRole='bot'`,
`isAI=true`. Customer messages inside the bot conversation are written with
`senderRole='customer'`, `direction='inbound'`. This is what gives the
merchant the transparency they currently lack.

## 6. Client changes

### 6.1 `ConnectManagementViewModel`
Replace the `Future.wait([twilioTo, twilioFrom, botpress])` plus client-side
merge/dedup with a single Firestore stream:

```dart
FirebaseFirestore.instance
  .collection('users').doc(currentUserId)
  .collection('customers').doc(customerId)
  .collection('messages')
  .orderBy('dateSent')
  .snapshots()
```

The existing `MessagesListView` / `MessageCard` already render whatever the
viewmodel emits, keyed off `direction`, `isWhatsApp`, `isAI`, `mediaUrl`,
`message`. We only need to adapt the field names where they differ (e.g.
`channel` vs `isWhatsApp`). Render code stays.

Remove:
- `TwilioService.fetchMessagesToCustomer` / `fetchMessagesFromCustomer` from
  the read path (the service stays for any remaining administrative use, or
  can be deleted once Connect is migrated).
- `BotpressService.fetchBotpressMessages` from the read path (same).
- The client-side merge/dedup/normalize block in `ConnectManagementViewModel`
  (~50 lines). Server is the source of truth.
- `looksLikeBotpressAccountReply` / `isTemplateMessage` AI inference on the
  read path. `isAI` is now an authoritative field.

### 6.2 Send path
Calls to `SMSMessagingService.sendSMS` / `WhatsAppMessagingService.send` are
replaced with a call to the `sendMessage` callable. Remote-Config Twilio
credentials are removed from the client app config.

### 6.3 Read-state heuristics
`_applyReadHeuristics` in the viewmodel becomes a no-op or is replaced by a
`status` field on each message. The `users/{uid}.unreadMessages` counter is
maintained by the function on inbound write.

## 7. Historical backfill

Existing Twilio history must be attributed to merchants and copied into the
new store. One-shot migration job (Cloud Function or Cloud Run task,
operator-triggered):

1. Build the `customerNumberIndex` from `users/*/customers/*.number`. Detect
   collisions (same E.164 owned by multiple merchants) and produce a report
   for ops.
2. Page through Twilio `Messages.json` for the account (no `To`/`From`
   filter — the full account log). For each message:
   - Resolve candidate merchants by `From=customer`→inbound or
     `To=customer`→outbound against the index.
   - Apply the same routing rules as §5.2.
   - Write to the new collection with `schemaVersion: 1` and
     `backfilled: true`.
   - For collision cases, write under each candidate merchant with
     `routing.ambiguous: true`.
3. Persist a Twilio cursor so the job is resumable.
4. Botpress historical conversations are walked similarly, using current
   `tags['whatsapp:userPhone']` to map to E.164 and then to merchant(s).
5. After backfill verifies, flip the client read path to Firestore. Run both
   in shadow mode for one release cycle to compare counts per thread.

Acceptance for backfill:
- For a sampled set of 20 known-clean threads, the new store matches the
  current Connect rendering 1:1 (after the visibility fix already shipped).
- For threads currently exhibiting the cross-merchant leak, the new store
  correctly separates them — verified by spot-checking that each merchant
  sees only their own outbound.
- No message in Twilio history is unaccounted for: every `sid` is either in
  a merchant's collection, in `inboundUnattributed`, or in the ambiguity
  bucket.

## 8. Rollout

1. Ship functions in shadow mode: writing to Firestore on every new send /
   inbound / Botpress event, but client still reads from Twilio/Botpress
   directly. Verify writes look correct for 1–2 weeks.
2. Run backfill against history. Verify (§7).
3. Flip a Remote Config flag `connect_read_source = firestore` per merchant,
   starting with internal accounts. Client viewmodel branches on this flag.
4. After a release with no regressions, remove the Twilio/Botpress read code
   paths from the client and the flag.
5. Remove `TWILIO_ACCOUNT_SID` / `TWILIO_AUTH_TOKEN` from client Remote
   Config; rotate the tokens.

## 9. Risks & open questions

- **Routing rule N-day window.** Picking N too short loses inbound
  attribution after a quiet period; too long increases false ambiguity in
  high-collision customer numbers. Start at 30 days, tune from real data.
- **Ambiguity UX.** What does the merchant see when an inbound is genuinely
  ambiguous? Proposal: render the bubble normally but with a subtle
  "attribution uncertain" badge, and never count it in unread until
  resolved.
- **Botpress legacy conversations without `pasella:merchantUid` tag.**
  These will route via the same active-thread rule. We should backfill the
  tag where we can.
- **Send path migration risk.** Switching sends through a Cloud Function
  introduces a new failure mode (function cold-start, regional outage).
  Mitigation: keep the message-queue retry layer that already exists in
  `lib/services/message_queue.dart`, point it at the callable.
- **Cost.** Firestore reads on a long thread are paginated; default page
  size of 50 with reverse-chronological order is plenty for the Connect UI.
  Functions invocations are bounded by send/inbound volume — small.
- **Compliance / data residency.** Conversation content now lives in
  Firestore in addition to Twilio. Confirm this is acceptable under any
  existing customer agreements.

## 10. Out of scope (tracked separately)

- Removing Botpress payload-rendering edge cases beyond what `main` already
  ships.
- Full text search over message history.
- Export / GDPR-style retention controls.
