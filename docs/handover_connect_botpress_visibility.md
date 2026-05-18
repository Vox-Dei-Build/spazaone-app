# Handover — Connect Botpress/Twilio Visibility Investigation

Date: 2026-05-18
Worktree: `pas-botpress-twilio-visibility-2026-05-18`
Branch: `investigate/pas-botpress-twilio-visibility-2026-05-18`

## TL;DR

- **One real fix landed in this worktree**: removing a body-content filter
  in `lib/services/twilio_service.dart` that was silently dropping legitimate
  outbound Twilio messages from the Connect thread (Botpress balance/statement
  replies, card menus, media-only messages, etc.).
- **Botpress messages are still not appearing** for at least one test
  customer (`+27648370009`). The visibility fix does **not** address this —
  Botpress goes through a completely separate fetch path
  (`BotpressService.fetchBotpressMessages`) that was never modified.
- The Botpress failure mode is silent: errors are caught and the UI just
  receives an empty list. The likely culprits, in order of probability, are
  listed in §3 below.
- A **locked execution plan** for proper multi-tenant isolation (the deeper
  cross-merchant leak problem) is at `docs/connect_thread_tenant_isolation_plan.md`.
  That work is independent of debugging the current Botpress no-show and
  should not block it.

## 1. What is in this worktree right now

```
git status
  modified:   lib/services/twilio_service.dart
  new file:   docs/connect_thread_tenant_isolation_plan.md
```

### 1.1 `lib/services/twilio_service.dart` — the visibility fix

**Root cause it addresses.** `fetchMessagesToCustomer` was filtering outbound
Twilio rows by whether the message body contained `customerData['name']` OR
`merchantData['shopName']`. Any row that didn't was dropped before reaching
the Connect viewmodel's merge step. Botpress replies, AI free-form responses,
card/menu payloads, and media-only messages routinely fail that check, so
they never reached the UI.

**Change made.**
- Removed the `messageText.contains(customerName) || messageText.contains(shopName)` filter.
- Removed the two now-dead Firestore helpers (`_fetchCustomerDetails`, `_fetchMerchantDetails`).
- Removed the `cloud_firestore` import that only existed to feed those helpers.
- Kept everything else unchanged: chronological ordering, media URL resolution, the existing `isAI = true` flag for non-template outbound WhatsApp, inbound fetching, and the downstream merge/dedup in `ConnectManagementViewModel`.

**Why it's safe within a single merchant.**
- Twilio's `?To=<customerE164>` query is server-side enforced; every returned row is destined for this customer's number.
- Downstream merge keys on Twilio `sid` (globally unique), so no cross-customer collisions are possible.
- Only one caller (`ConnectManagementViewModel._fetchMessages`).

**Known limitation.** Cross-merchant leakage on the shared Twilio account is **not** fixed by this patch. See `docs/connect_thread_tenant_isolation_plan.md`.

**Verification done.**
- `dart format` — clean.
- `flutter analyze lib/services/twilio_service.dart` — one pre-existing `http` lint that also exists on `main`, unrelated.
- Not exercised end-to-end against a live thread.

### 1.2 `docs/connect_thread_tenant_isolation_plan.md`

Locked plan for solving cross-merchant tenant isolation properly via:
- Firestore-backed message store at `users/{merchantUid}/customers/{customerId}/messages/{sid}`.
- Cloud Functions for `sendMessage`, Twilio inbound webhook, Twilio status webhook, Botpress event webhook.
- Backfill of historical Twilio data with explicit per-message merchant attribution.
- Shadow-mode rollout → backfill → flag-gated read cutover → credential removal.

Locked decisions captured at the top of the doc:
- Inbound routing lookback window: **30 days**, tunable.
- Ambiguous-inbound policy: **Option D** (best-guess + audit log).
- Subaccounts: **not required**.
- Cross-merchant collisions treated as an **edge case** for the initial release.

This is independent of the Botpress no-show bug below.

## 2. The remaining bug — Botpress messages not appearing for `+27648370009`

Symptom reported: Twilio messages show up in Connect for this customer, Botpress messages do not.

The visibility fix would not have affected this. Botpress fetch is a different code path entirely (`lib/services/botpress_service.dart` → called from `ConnectManagementViewModel._fetchMessages` at line 93).

### 2.1 Why it fails silently

`BotpressService.fetchBotpressMessages` (lines 38–97 of `lib/services/botpress_service.dart`) has multiple silent failure points:

| # | Location | Failure mode | UI sees |
|---|---|---|---|
| 1 | Outer `try/catch` at line 91 | Any exception during mapping (e.g. `DateTime.parse` on an unexpected `createdAt` format) | empty list, only `print` to console |
| 2 | `_findConversationId` returns `null` (line 45) | No conversation has `tags['whatsapp:userPhone'] == userPhoneNoPlus` | empty list, no log at all |
| 3 | `_findConversationId` non-200 (line 232) | Auth failed / wrong bot id / network | empty list, single `❌` print |
| 4 | `_fetchMessages` non-200 (line 262) | Conversation found, but message fetch fails | partial list, single `❌` print |
| 5 | Downstream cutoff in `ConnectManagementViewModel._fetchMessages` line 103, 111 | `dateSent` is null or before 2024-01-01 | message silently dropped from merge |

### 2.2 Most likely culprit

Phone-tag format mismatch (failure mode #2).

The code at `lib/services/botpress_service.dart:8-13` does:
```dart
String normalizeMsisdnForBotpressTag(String e164) {
  if (e164.isEmpty) return e164;
  final digits = e164.replaceAll(RegExp(r'[^\d]'), '');
  return digits;
}
```

So `+27648370009` → `27648370009`. The conversation search then compares this exactly against `tags['whatsapp:userPhone']` (line 243). If Botpress is storing the tag in any other format — with the leading `+`, with a `whatsapp:` prefix, with double zeros instead of `+`, without country code, etc. — the loop never matches and the function returns `null`, and `fetchBotpressMessages` returns `const []`.

### 2.3 How to confirm in one run

Earlier in this session I prepared and then reverted a one-shot diagnostic that adds `print` statements at every silent failure point. To re-apply it, edit `lib/services/botpress_service.dart` and:

1. In `fetchBotpressMessages`, log:
   - the resolved `customerNumber` and `userPhoneNoPlus`
   - whether `_apiToken` and `_botId` are non-empty (don't print the token itself)
   - whether `_findConversationId` returned `null` or an id
   - the number of raw messages returned by `_fetchMessages`
   - the count of mapped messages, the count surviving a 2024-01-01 cutoff, and the inbound/outbound split

2. In `_findConversationId`, log:
   - page count and total conversations scanned
   - the status code if non-200
   - on no-match, the list of `whatsapp:userPhone` tag values that share the **last 6 digits** of the lookup number. This is the key diagnostic — it shows what format Botpress is actually using.

3. In `_fetchMessages`, log batch/page sizes and any non-200.

Prefix every line with `🔎 BP-DIAG ` so it's easy to grep and easy to revert.

### 2.4 Interpretation guide for the diagnostic output

| Observed log line | Likely cause | Fix |
|---|---|---|
| `tokenLen=0 botIdLen=0` | Remote Config didn't load Botpress keys | Check `Botpress_Keys` / `BOTPRESS_BOT_ID` in Firebase Remote Config for this environment |
| `❌ conversations 401` or `403` | Token wrong, expired, or scoped to a different bot | Rotate token; verify `BOTPRESS_BOT_ID` matches the bot that holds the conversation |
| `❌ conversations 404` | Wrong bot id | Same |
| `tagsContainingLast6Digits=["+27648370009"]` | Botpress stored the tag **with** the `+` | Adjust `normalizeMsisdnForBotpressTag` or the match comparison |
| `tagsContainingLast6Digits=["whatsapp:+27648370009"]` | Botpress stored the tag with a `whatsapp:` channel prefix | Strip the prefix in the match comparison |
| `tagsContainingLast6Digits=["0027648370009"]` | Double-zero international prefix | Normalize both sides before compare |
| `tagsContainingLast6Digits=[]` | Conversation doesn't exist on this bot at all | Either the bot never engaged this number, or it's on a different bot id |
| `resolved conversationId=... batch=0 runningTotal=0` | Conversation exists but is empty | Botpress side issue, not app side |
| `mapped=X afterCutoff(2024-01-01)=0` | All Botpress messages predate the cutoff in the viewmodel | Loosen the cutoff at `connect_management_view_model.dart:103` |
| `🔥 Botpress fetch error: FormatException ...` | A specific `createdAt` value fails `DateTime.parse` | Harden the parse (the diagnostic version I drafted already does this with a per-row try/catch fallback to `DateTime.now()`) |

### 2.5 Things deliberately not changed

I did not touch:
- `lib/pages/contact/view_model/connect_management_view_model.dart` — the merge/dedup logic, cutoff, and read heuristics. Functional and correct given current message shapes.
- `lib/pages/contact/connect/widgets/message_card.dart` or the list view — render pipeline already handles whatever the viewmodel emits.
- `lib/templates/sms_message.dart` — `isTemplateMessage` is fine; not relevant to the Botpress no-show.
- `lib/pages/contact/view_model/customer_management_view_model.dart` — not on the Connect fetch path; only owns the unread-badge counter.

If the diagnostic shows Botpress is fine end-to-end but messages still aren't visible, look next at the 2024-01-01 cutoff at `connect_management_view_model.dart:103, 111` and the date parsing on the Botpress side. Those are the only other places a Botpress row could be silently discarded.

## 3. Suggested next steps for whoever picks this up

1. **Re-apply the BP-DIAG diagnostics** described in §2.3 (don't ship them; this is a local-only investigation aid).
2. **Run the app in debug mode**, open the Connect tab for `+27648370009`, and collect the `🔎 BP-DIAG`, `❌`, and `🔥` log lines.
3. **Match the output against the table in §2.4** to identify the failure mode.
4. **Apply the minimal fix** (almost certainly a one-line change to `normalizeMsisdnForBotpressTag` or the tag match comparison; possibly a Remote Config correction).
5. **Verify with a second customer** who is known to have Botpress traffic, to confirm the fix isn't specific to one number's data.
6. **Revert the BP-DIAG prints** before committing.
7. **Independently**, the tenant-isolation work described in `docs/connect_thread_tenant_isolation_plan.md` should start whenever bandwidth allows. The Botpress no-show is a bug fix; the tenant isolation is the structural change that makes the system actually correct for multiple merchants.

## 4. Things that are NOT the cause (already ruled out)

- The body-content filter — already removed in this worktree.
- The `looksLikeBotpressAccountReply` keyword heuristic from the original hypothesis — discarded as fragile; it never affected visibility, only the AI badge.
- Render-side filtering in `MessageCard` / `MessagesListView` — no such filter exists; once a message reaches the viewmodel it is rendered.
- The merge/dedup logic — keys on `sid` / `id`, Botpress ids cannot collide with Twilio `sid`s, both copies always survive.
- Cross-customer leakage within a single merchant — Twilio `To=`/`From=` scoping makes this impossible for distinct customer phone numbers.

## 5. Files & line references

| Concern | File:line |
|---|---|
| Visibility fix (already applied) | `lib/services/twilio_service.dart` (whole file) |
| Botpress phone normalization | `lib/services/botpress_service.dart:8-13` |
| Botpress conversation match | `lib/services/botpress_service.dart:243` |
| Botpress silent catch | `lib/services/botpress_service.dart:91-96` |
| Botpress fetch caller | `lib/pages/contact/view_model/connect_management_view_model.dart:93` |
| Merge + cutoff | `lib/pages/contact/view_model/connect_management_view_model.dart:102-145` |
| Date cutoff | `lib/pages/contact/view_model/connect_management_view_model.dart:103, 111` |
| Tenant isolation plan | `docs/connect_thread_tenant_isolation_plan.md` |

## 6. Open questions

- Does `+27648370009` actually have an active Botpress conversation, and on which `BOTPRESS_BOT_ID`? Without that confirmation, "no conversation found" could be correct rather than a bug.
- Are there other customers with the same symptom, or is this isolated to one number? If isolated, suspect data; if widespread, suspect format/normalization.
- Is the Remote Config in the running app actually loading non-empty `Botpress_Keys` and `BOTPRESS_BOT_ID`? Easy to confirm with the diagnostic.

Good luck.
