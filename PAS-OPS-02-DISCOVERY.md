# PAS-OPS-02 — Staff Operators / Role Management — Discovery Note

- Lane: `PAS-OPS-02 — Staff operators / role management discovery`
- Branch: `audit/pas-ops-02-staff-role-management`
- Date: 2026-06-02
- Status: Discovery (no code changes in this worktree)
- Adjacent context: release-tomorrow pressure for campaign readiness; PAS-AI and PAS-UX lanes in flight

---

## 1. TL;DR (the honest read)

The Pasella app is built on a hard assumption that **one Firebase UID = one merchant = one shop**. There is currently:

- No role / staff / team / member / invite concept anywhere in `lib/` or `functions/src/`.
- **No `firestore.rules` file in the repo** — tenant isolation lives off-repo in the Firebase Console with no CI guarantee.
- Several callables (notably `updateOrderPayment`, `getMerchantSales`, most of `ecommerce/*` and `customer_hub/*`) **read `merchantId` from the client request body** and do not verify `context.auth.uid` owns it.
- FCM tokens are stored in a single slot per user (`users/{uid}.fcmToken`), overwritten on every device login — so multi-device is already broken even before staff exist.

**Recommendation:** do **not** attempt to ship a staff/roles feature in the tomorrow release. Staff/roles is not a UI feature on this codebase — it requires a security foundation that the app currently lacks. Use this lane to land a small "Slice 0" foundation that is independently valuable (closes real security holes, unblocks multi-device notifications) and **does not** ship any user-visible staff feature. Then plan a deliberate "Slice 1" two-role V1 (Owner + Operator) on top of it once the foundation is in.

Do NOT invent enterprise RBAC. The recommended V1 is **two roles, phone-invite, owner-only sensitive paths.** Nothing more.

---

## 2. Current-state findings (facts, with citations)

### 2.1 Auth & identity

- Single auth method: Firebase Phone OTP + anonymous "Explore" mode.
  - `lib/main.dart:255` Firebase init; `lib/main.dart:456` initial route hard-coded to `LoginPage`.
  - `lib/pages/auth/login/login.dart:46` — `StreamBuilder<User?>` on `authStateChanges()` — presence of a `User` (even anonymous) is sufficient to enter `Dashboard`.
- `lib/utils/auth_util.dart` exposes only an anonymous-gate and `logout`. **No role/permission/business getters.**
- All sign-in / register flows live in `lib/pages/auth/view_model/auth_view_model.dart` (`handleLogin :41`, `registerUser :96`, `registerAnonymousAccount :187`, `linkPhoneNumberWithAnonymousAccount :623`, `_storeUserDetails :707`).
- Registration collects: `name`, `mobileNumber`, `mobileNumberNormalized`, `shopName` (required at `lib/pages/auth/register/register.dart:108`), optional `referrerUserId`. **No `businessId`, no role, no membership write.**

### 2.2 Data model

- Tenancy is implicit: everything is `users/{uid}/<subcollection>`. There is **no `businesses/{businessId}` collection.** A staff/membership join object has no natural home today.
- Greps for `role|roles|permissions|isAdmin|isOwner|members|staff|employees|team|invited|accessLevel` across `lib/**/*.dart` and `functions/src/**/*.ts` return **zero access-control hits**. Only marketing copy ("invite others", "The Pasella team").
- Two parallel merchant collections exist: `users/{uid}` (primary) and legacy `shopOwners/{id}` used only by `functions/src/notifications/{non_payment,retention}_notifications.ts:191, 52`. Any membership model bolted onto `users/{uid}` only will silently diverge from notifier paths.

### 2.3 Authorization

- **No `firestore.rules` file** (`find . -name firestore.rules` → empty). `firebase.json` has no `firestore` block (`firebase.json:1-30`). The cross-tenant messaging plan in `docs/connect_thread_tenant_isolation_plan.md:192-199` flags rules as still-aspirational.
- Of 51 files in `functions/src/` declaring `onCall`/`onRequest`, only ~20 reference `context.auth`.
- **Properly authorized** (uid-derived, ownership-checked):
  - `functions/src/utils/heartbeatMerchantApp.ts:31, 58` (`assertCallerIsMerchantAdmin`).
  - `functions/src/merchant_hub/runMerchantPromotion.ts:208-235`.
  - `functions/src/services/deleteUserAccount.ts:40-47`.
  - `functions/src/ledger/ledger.ts:24-31`.
  - `functions/src/reports/business_metrics.ts:33-41, 80-88`.
- **Improperly authorized** (trust `merchantId` from request body):
  - `functions/src/ecommerce/updateOrderPayment.ts:149-171` — accept/reject/assign-driver/mark-delivered. **Any signed-in user can mutate any merchant's orders.** `context.auth.uid` is stamped into `acceptedBy/...` but never compared to `merchantId`.
  - `functions/src/ecommerce/getMerchantSales.ts:27-39`.
  - `functions/src/ecommerce/checkoutCart.ts:15` (HTTP, body-driven).
  - `functions/src/customer_hub/addCredit.ts:10`.
  - `functions/src/payments/paystack/createPaystackTransaction.ts:41`.
  - 30+ others per `grep -L` (some are intentional webhooks).
- Client-side gates are limited to the anonymous-gate (`auth_util.dart:10-54`) and the business-name gate (`lib/pages/profile/business_name_gate.dart:27`). **No role-based UI hiding** exists.

### 2.4 Multi-device reality

- `lib/services/fcm_service.dart:67-105` overwrites `users/{uid}.fcmToken` on every login. Backend already half-supports `fcmTokens: string[]` (`functions/src/ecommerce/notifyOrderEvent.ts:113-118`, `onSaleCreatedNotify.ts:289-292`) but the client never writes it. **The second device to log in silently steals notifications from the first.** This is a pre-existing bug that any multi-operator V1 makes immediately visible.

### 2.5 Audit posture

- The only actor-stamp fields anywhere are on orders: `acceptedBy`, `rejectedBy`, `assignedBy`, `driverUnassignedBy`, `outForDeliveryBy`, `deliveredBy` (`functions/src/ecommerce/updateOrderPayment.ts:209, 222, 256, 273, 301, 318`).
- No `createdBy` / `updatedBy` / `performedBy` on transactions, products, customers, payments, wallet, banking, settings. Zero grep hits in `lib/`.

---

## 3. Recommended V1 role model

Constraint: merchant-team, not corporate RBAC. Two roles. Phone-invite. Single-shop scope.

| Role | Can do | Cannot do |
|---|---|---|
| **Owner** | Everything. Invite/remove operators. Banking, payouts, pricing, plan, account deletion, WhatsApp/Twilio templates, Paystack settings. | — |
| **Operator** | Day-to-day shop ops: accept/reject/assign orders, mark delivered, add customer credit, record payment, edit products (incl. price), send WhatsApp templates, view customers, view reports. | Banking, payouts, plan/billing, Paystack settings, Twilio/WhatsApp template approvals, invite/remove staff, delete account. |

Notes:
- **Exactly two roles.** No "manager", no "viewer", no granular permissions matrix. Resist scope creep.
- **Operator can edit price.** This is contentious; the alternative ("read-only price") is harder to use in a retail shop and pushes operators to ask the owner constantly. If a merchant doesn't trust their operator with pricing, they should not invite them. State this explicitly in the invite copy.
- **One business per operator** in V1. No multi-shop access. (Possible later via a `memberships[]` table.)
- **Owner is the merchant who first registered.** No transfer in V1. Add an explicit "Transfer ownership" later if asked for.

### Data model

Introduce, additively (no migration of existing docs needed):

```
users/{uid}                      # unchanged; uid is the personal user
  - role: 'owner' | 'operator'   # convenience cache; SoT is membership doc
  - primaryBusinessId: string    # the business they currently act on

businesses/{businessId}          # NEW. businessId == owner uid for V1 (zero migration)
  - ownerUid: string
  - shopName, businessType, etc. (copied/owned from users/{ownerUid})
  - createdAt

businesses/{businessId}/members/{uid}   # NEW. membership join
  - role: 'owner' | 'operator'
  - addedBy: uid
  - addedAt
  - phone, name (cached for display)

businesses/{businessId}/invites/{inviteId}   # NEW. pending phone invites
  - phoneNormalized
  - role: 'operator'
  - invitedBy: uid
  - createdAt
  - status: 'pending' | 'accepted' | 'revoked'
  - expiresAt (e.g. 7 days)
```

Keep all current `users/{ownerUid}/*` shop subcollections **exactly where they are** for V1. The auth derivation becomes:

```
caller uid → look up users/{uid}.primaryBusinessId
          → look up businesses/{businessId}/members/{uid}.role
          → all reads/writes resolve to users/{businessId}/<subcollection>
```

i.e. for the owner, `businessId == uid` and nothing changes on disk. For an operator, their callable requests are routed to the owner's `users/{ownerUid}/*` tree.

### Invite flow

1. Owner enters operator phone → cloud function writes invite doc + sends WhatsApp message via existing Twilio path (no SMS cost on the OTP, reuse the WhatsApp comms surface that's already built for the customer side).
2. Operator installs app, signs in via phone OTP (existing flow).
3. On first login, a callable `acceptInvite(inviteId)` (or phone-match scan) creates the membership doc, sets `users/{operatorUid}.role = 'operator'` and `primaryBusinessId = ownerUid`.
4. Owner can revoke from a Staff list screen.

No new auth method. No email. No deep links required in V1 (phone-match on first login is sufficient; deep links are a v1.1 polish).

---

## 4. Recommended implementation path

### Slice 0 — Security foundation (PRE-REQUISITE; ship independent of any staff UI)

This is valuable on its own and **must** ship before Slice 1. None of it is user-visible.

1. **Add `firestore.rules` to the repo**, wire it into `firebase.json`, deploy.
   - Rules enforce: `request.auth.uid != null`, owner-only on banking/payouts/templates, and a generic `users/{uid}/**` "uid == path[1]" rule for now (Slice 1 widens this for memberships).
2. **Re-authorize callables** to derive `merchantId` from `context.auth.uid` (not from request body), starting with the highest-risk three:
   - `functions/src/ecommerce/updateOrderPayment.ts:149` — accept/reject/assign.
   - `functions/src/ecommerce/getMerchantSales.ts:27`.
   - `functions/src/payments/paystack/createPaystackTransaction.ts:41`.
   Then sweep the rest of `ecommerce/*` and `customer_hub/*`. Backwards-compat: ignore the body `merchantId` (don't error) for one release to avoid breaking older app builds in the wild.
3. **Convert FCM tokens to an array** `users/{uid}.fcmTokens[]` keyed by install-id. Backend already tolerates this shape.
4. **Stop allowing anonymous users to reach merchant callables** — add a `request.auth.token.firebase.sign_in_provider != 'anonymous'` check in the callable utility wrapper. (Anonymous-mode is fine for Explore, but it must not be able to mutate.)

Verification: existing flows for a single owner-merchant continue to work; the broken `updateOrderPayment` cross-tenant path is now rejected; two devices on one owner account both receive notifications.

**This slice is the only thing safe to consider for the tomorrow release**, and even that should only ship if there is time for a real smoke pass.

### Slice 1 — Two-role V1 (the actual lane deliverable)

After Slice 0 is in production for at least one release cycle:

1. Add `businesses/{businessId}` + `members/{uid}` + `invites/{inviteId}` collections (above schema).
2. **Backfill**: a one-off function creates `businesses/{uid}` + `members/{uid}` (role: owner) for every existing `users/{uid}` doc. No data movement, just additive writes.
3. Replace the per-callable `assertCallerIsMerchantAdmin` with `resolveCallerBusiness(context)` → `{ businessId, role }`, then per-callable role checks (`requireOwner()` vs `requireMember()`).
4. Firestore rules updated to allow operator reads/writes scoped to their `primaryBusinessId`, but reject operator writes to banking/payouts/templates/Paystack subtrees.
5. UI:
   - Settings → Staff list screen (Owner only). Add operator by phone. Revoke. Pending invites.
   - Operator-side: a one-time "Joining {ShopName}" confirm screen on first login after accept.
   - Hide Settings → Banking, Payouts, Templates from operators (use a `RoleScope` widget; do **not** rely on hiding alone — server enforces).
6. Add `performedBy: uid` stamp to writes on orders, transactions (credit/payment), product edits, and customer edits. Display "by {name}" in order/transaction history.
7. Telemetry: tag every analytics event with `role` and `businessId` (separate from `uid`).

### Slice 2 — Polish (post-V1, only if real demand)

- Owner transfer.
- Operator-level "read-only price" toggle per business.
- Multi-business membership.
- Per-permission overrides.
- Deep-link invite acceptance.

Stop here. Anything beyond Slice 2 is enterprise RBAC and is not the Pasella job.

---

## 5. Explicit scope boundaries (what this lane is NOT)

- Not multi-tenant SaaS (one operator → many shops). V1 is one operator → one shop.
- Not granular permissions. Two roles, fixed.
- Not org charts / departments / driver-as-role / supplier-as-role. Drivers stay as a `driverId` field on orders; suppliers are separate.
- Not customer-facing accounts. This lane is merchant-side staff only.
- Not the "Manual driver allocation" open item from `open-items.md:55` — adjacent but separate. (Slice 1 happens to add the actor-stamp that makes driver allocation auditable.)
- Not a fix for the `shopOwners` legacy collection — flagged as risk, not in scope.

---

## 6. Major risks & follow-ups

1. **Tomorrow-release blast radius.** If product wants to advertise "staff support" tomorrow, the answer is no. Slice 0 alone is the most that should be considered, and Slice 0 is invisible. Be explicit with stakeholders.
2. **No `firestore.rules` in repo today** means we cannot confidently reason about what is and isn't enforced. Before Slice 1, the team must reconcile the deployed console rules with the repo file, or accept they may be silently more permissive than expected.
3. **Cross-tenant write hole in `updateOrderPayment`** (§2.3) is a present-tense security bug regardless of this lane. Recommend filing it as its own ticket (e.g. PAS-SEC-01) so it does not get stranded if PAS-OPS-02 slips.
4. **FCM single-slot bug** will become a P0 complaint the moment two staff devices share a shop. Must land in Slice 0.
5. **`shopOwners` divergence** (§2.2) — any membership-aware notifier must read through the membership table, not the legacy collection. Add a small follow-up to migrate the two notifier files.
6. **Anonymous "Explore" users currently have a UID that can call most merchant callables** (§2.3 + Slice 0 step 4). Closing this is part of Slice 0; tagging here because it's easy to forget.
7. **No business doc today** means analytics and any future invoice/billing surface have nothing to attach to. Slice 1's `businesses/{businessId}` doc unlocks that side-benefit; sequence accordingly.
8. **Operator price-edit** is a product call, not a code call. Re-confirm with the merchant cohort during Slice 1 design before locking copy.

---

## 7. Files reviewed (read-only)

- `lib/main.dart`
- `lib/utils/auth_util.dart`
- `lib/pages/auth/login/login.dart`
- `lib/pages/auth/register/register.dart`
- `lib/pages/auth/registerAnonymous/register_anonymous.dart`
- `lib/pages/auth/view_model/auth_view_model.dart`
- `lib/pages/auth/widgets/login_ui.dart`
- `lib/services/fcm_service.dart`
- `lib/services/firestore_service.dart`
- `lib/services/template_service.dart`
- `lib/providers/transactional_view_model.dart`
- `lib/pages/profile/business_name_gate.dart`
- `lib/pages/ecommerce/orders/order_detail_page.dart`
- `lib/pages/ecommerce/orders_management/data/orders_controller.dart`
- `lib/pages/wallet/view_model/wallet_view_model.dart`
- `lib/shared/billing/wallet_balance_provider.dart`
- `lib/utils/banking_util.dart`
- `functions/src/ecommerce/updateOrderPayment.ts`
- `functions/src/ecommerce/getMerchantSales.ts`
- `functions/src/ecommerce/checkoutCart.ts`
- `functions/src/customer_hub/addCredit.ts`
- `functions/src/merchant_hub/runMerchantPromotion.ts`
- `functions/src/merchant_hub/order/types/orderModel.ts`
- `functions/src/payments/paystack/createPaystackTransaction.ts`
- `functions/src/notifications/non_payment_notifications.ts`
- `functions/src/notifications/retention_notifications.ts`
- `functions/src/ledger/ledger.ts`
- `functions/src/reports/business_metrics.ts`
- `functions/src/services/deleteUserAccount.ts`
- `functions/src/utils/heartbeatMerchantApp.ts`
- `functions/src/ecommerce/notifyOrderEvent.ts`
- `functions/src/ecommerce/onSaleCreatedNotify.ts`
- `firebase.json`
- `docs/connect_thread_tenant_isolation_plan.md`
- `/Users/admin/.openclaw/workspace/voxdei-os/04-Entities/Pasella/open-items.md`

## 8. Files changed

None. Discovery lane.

## 9. Verification performed

- Branch confirmed: `audit/pas-ops-02-staff-role-management`.
- Read-only grep / file inspection across `lib/` and `functions/src/` for every term in §2.2.
- No code, no rules, no functions were modified or deployed.
