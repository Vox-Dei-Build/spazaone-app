import 'package:flutter/foundation.dart';

/// Sealed event taxonomy for PostHog analytics.
///
/// Why a sealed hierarchy:
///   * Names are typed -- you cannot fire `sale_competed` instead of
///     `sale_completed`. Compiler stops the typo at the source.
///   * Properties are typed per event -- each event class lists exactly the
///     fields PostHog should receive. No untyped `Map<String, dynamic>`
///     leaking through the codebase.
///   * Adding a new event is a single edit in this file plus a callsite, so
///     the analytics taxonomy lives in one place and is searchable.
///
/// PII rules baked in here:
///   * No event carries `email`, `phone`, `idNumber`, `firstName`, `lastName`,
///     `bankAccount`, or `address`. If a future event needs to reference a
///     person, use the merchant or customer document id and resolve names in
///     the dashboard via a backend join.
///   * Free-form text (sale notes, comms message bodies) is NEVER captured.
///
/// PostHog auto-captures the following so we do not redefine them here:
///   * `Application Opened`, `Application Backgrounded`, `Application Installed`
///   * `Application Updated`
///   * `$screen` (route changes via `PosthogObserver`)
///   * `$exception` -- emitted manually by `TelemetryService.captureException`
///     because PostHog 4.11 has no native autocapture.
@immutable
sealed class AnalyticsEvent {
  const AnalyticsEvent();

  /// Snake-cased event name as seen in the PostHog UI.
  String get name;

  /// Event-specific properties. Implementations MUST NOT include PII.
  Map<String, Object?> get properties;
}

// ---------------------------------------------------------------------------
// Auth lifecycle
// ---------------------------------------------------------------------------

/// User completed the sign-up flow (anonymous or registered).
class SignupCompleted extends AnalyticsEvent {
  final String method; // 'anonymous' | 'phone' | 'email'
  final String? businessType;
  final String? businessCategory;

  const SignupCompleted({
    required this.method,
    this.businessType,
    this.businessCategory,
  });

  @override
  String get name => 'signup_completed';

  @override
  Map<String, Object?> get properties => {
        'method': method,
        if (businessType != null) 'business_type': businessType,
        if (businessCategory != null) 'business_category': businessCategory,
      };
}

/// User successfully signed in.
class SigninCompleted extends AnalyticsEvent {
  final String method; // 'phone' | 'email' | 'session_restore'

  const SigninCompleted({required this.method});

  @override
  String get name => 'signin_completed';

  @override
  Map<String, Object?> get properties => {'method': method};
}

/// User signed out (manual sign-out, not session expiry).
class SignoutCompleted extends AnalyticsEvent {
  const SignoutCompleted();

  @override
  String get name => 'signout_completed';

  @override
  Map<String, Object?> get properties => const {};
}

// ---------------------------------------------------------------------------
// PAS-UX-22: number-first onboarding lookup
// ---------------------------------------------------------------------------
//
// Pre-auth events emitted by the single number-first entry screen
// (`PhoneEntryPage`). They size the new vs returning split and surface
// failures of the duplicate-account-prevention guard.
//
// PII rules: never carry the phone number itself. `isRegistered` is a
// single bit; `reason` is a backend/error-code-style enum, not free text.

/// Fired once per Continue tap on PhoneEntryPage where the
/// `_isUserRegistered` lookup returned a definitive answer.
///
/// `isRegistered` records which branch the user was routed to:
///   * true  -> existing account, OTP-as-login path
///   * false -> new account, OTP-as-registration path
class PhoneLookupSucceeded extends AnalyticsEvent {
  final bool isRegistered;

  const PhoneLookupSucceeded({required this.isRegistered});

  @override
  String get name => 'phone_lookup_succeeded';

  @override
  Map<String, Object?> get properties => {'is_registered': isRegistered};
}

/// Fired when the registered-user lookup itself failed (offline mid-read,
/// Firestore unavailable, permission denied, etc.) and the user was NOT
/// advanced into either branch.
///
/// `reason` is one of:
///   * 'offline'        -> connectivity guard short-circuited
///   * 'unavailable'    -> Firestore returned `[cloud_firestore/unavailable]`
///   * 'permission'     -> rules denied the read
///   * 'unknown'        -> everything else
class PhoneLookupFailed extends AnalyticsEvent {
  final String reason;

  const PhoneLookupFailed({required this.reason});

  @override
  String get name => 'phone_lookup_failed';

  @override
  Map<String, Object?> get properties => {'reason': reason};
}

// ---------------------------------------------------------------------------
// OTP funnel
// ---------------------------------------------------------------------------
//
// PII rules: OTP events never include the phone number, SMS code,
// verification id, resend token, or raw Firebase exception text.

class OtpCodeSent extends AnalyticsEvent {
  final String purpose; // 'login' | 'registration' | 'link_anonymous'

  const OtpCodeSent({required this.purpose});

  @override
  String get name => 'otp_code_sent';

  @override
  Map<String, Object?> get properties => {'purpose': purpose};
}

class OtpAutoVerified extends AnalyticsEvent {
  final String purpose;
  final String elapsedBucket;

  const OtpAutoVerified({required this.purpose, required this.elapsedBucket});

  @override
  String get name => 'otp_auto_verified';

  @override
  Map<String, Object?> get properties => {
        'purpose': purpose,
        'elapsed_bucket': elapsedBucket,
      };
}

class OtpManualVerified extends AnalyticsEvent {
  final String purpose;
  final String elapsedBucket;

  const OtpManualVerified({required this.purpose, required this.elapsedBucket});

  @override
  String get name => 'otp_manual_verified';

  @override
  Map<String, Object?> get properties => {
        'purpose': purpose,
        'elapsed_bucket': elapsedBucket,
      };
}

class OtpVerificationFailed extends AnalyticsEvent {
  final String purpose;
  final String failureCode;
  final String elapsedBucket;

  const OtpVerificationFailed({
    required this.purpose,
    required this.failureCode,
    required this.elapsedBucket,
  });

  @override
  String get name => 'otp_verification_failed';

  @override
  Map<String, Object?> get properties => {
        'purpose': purpose,
        'failure_code': failureCode,
        'elapsed_bucket': elapsedBucket,
      };
}

class OtpResendRequested extends AnalyticsEvent {
  final String purpose;
  final String elapsedBucket;

  const OtpResendRequested({
    required this.purpose,
    required this.elapsedBucket,
  });

  @override
  String get name => 'otp_resend_requested';

  @override
  Map<String, Object?> get properties => {
        'purpose': purpose,
        'elapsed_bucket': elapsedBucket,
      };
}

class OtpCancelled extends AnalyticsEvent {
  final String purpose;
  final String elapsedBucket;

  const OtpCancelled({required this.purpose, required this.elapsedBucket});

  @override
  String get name => 'otp_cancelled';

  @override
  Map<String, Object?> get properties => {
        'purpose': purpose,
        'elapsed_bucket': elapsedBucket,
      };
}

// ---------------------------------------------------------------------------
// Sales / ledger funnel
// ---------------------------------------------------------------------------

/// Merchant opened the "new sale" form.
class SaleStarted extends AnalyticsEvent {
  final String entryPoint; // 'dashboard' | 'customer_profile' | 'fab'

  const SaleStarted({required this.entryPoint});

  @override
  String get name => 'sale_started';

  @override
  Map<String, Object?> get properties => {'entry_point': entryPoint};
}

/// Sale committed to the ledger.
///
/// `amountBucket` is a coarse band ("0-50", "50-200", ...) rather than the
/// raw amount, so dashboards can segment without storing transaction sizes
/// in PostHog. Compute the bucket at the call site so the rounding rule is
/// auditable.
class SaleCompleted extends AnalyticsEvent {
  final String amountBucket;
  final bool isCredit; // true => BNPL, false => cash/instant
  final bool customerIsExisting;
  final bool hasProducts;
  final String productCountBucket;

  const SaleCompleted({
    required this.amountBucket,
    required this.isCredit,
    required this.customerIsExisting,
    required this.hasProducts,
    required this.productCountBucket,
  });

  @override
  String get name => 'sale_completed';

  @override
  Map<String, Object?> get properties => {
        'amount_bucket': amountBucket,
        'is_credit': isCredit,
        'customer_is_existing': customerIsExisting,
        'has_products': hasProducts,
        'product_count_bucket': productCountBucket,
      };
}

/// Money was actually received for a sale or customer repayment.
///
/// This is deliberately separate from [SaleCompleted]: a credit sale is a
/// valuable merchant action, but it is not a payment until the customer
/// settles it. [transactionId] is a Firestore/order identifier, never a
/// payment-card reference or other sensitive payment credential. It gives
/// analytics a stable reconciliation key; app-side retry protection is handled
/// by `PaymentReceiptTracker` because GA4 app streams do not deduplicate it.
class PaymentReceived extends AnalyticsEvent {
  final String transactionId;
  final String amountBucket;
  final String source;
  final String method;

  const PaymentReceived({
    required this.transactionId,
    required this.amountBucket,
    required this.source,
    required this.method,
  });

  @override
  String get name => 'payment_received';

  @override
  Map<String, Object?> get properties => {
        'transaction_id': transactionId,
        'amount_bucket': amountBucket,
        'source': source,
        'method': method,
      };
}

/// Merchant abandoned the sale form before submitting.
class SaleAbandoned extends AnalyticsEvent {
  final String? lastFieldFocused;

  const SaleAbandoned({this.lastFieldFocused});

  @override
  String get name => 'sale_abandoned';

  @override
  Map<String, Object?> get properties => {
        if (lastFieldFocused != null) 'last_field': lastFieldFocused,
      };
}

// ---------------------------------------------------------------------------
// BNPL funnel
// ---------------------------------------------------------------------------

class BnplOfferShown extends AnalyticsEvent {
  final String amountBucket;

  const BnplOfferShown({required this.amountBucket});

  @override
  String get name => 'bnpl_offer_shown';

  @override
  Map<String, Object?> get properties => {'amount_bucket': amountBucket};
}

class BnplOfferAccepted extends AnalyticsEvent {
  final String amountBucket;
  final int termDays;

  const BnplOfferAccepted({required this.amountBucket, required this.termDays});

  @override
  String get name => 'bnpl_offer_accepted';

  @override
  Map<String, Object?> get properties => {
        'amount_bucket': amountBucket,
        'term_days': termDays,
      };
}

class BnplOfferRejected extends AnalyticsEvent {
  final String amountBucket;
  final String? reason; // user-selected reason from dropdown, never free text

  const BnplOfferRejected({required this.amountBucket, this.reason});

  @override
  String get name => 'bnpl_offer_rejected';

  @override
  Map<String, Object?> get properties => {
        'amount_bucket': amountBucket,
        if (reason != null) 'reason': reason,
      };
}

// ---------------------------------------------------------------------------
// Payouts
// ---------------------------------------------------------------------------

class PayoutRequested extends AnalyticsEvent {
  final String amountBucket;

  const PayoutRequested({required this.amountBucket});

  @override
  String get name => 'payout_requested';

  @override
  Map<String, Object?> get properties => {'amount_bucket': amountBucket};
}

class PayoutCompleted extends AnalyticsEvent {
  final String amountBucket;
  final int latencySeconds;

  const PayoutCompleted({
    required this.amountBucket,
    required this.latencySeconds,
  });

  @override
  String get name => 'payout_completed';

  @override
  Map<String, Object?> get properties => {
        'amount_bucket': amountBucket,
        'latency_seconds': latencySeconds,
      };
}

class PayoutFailed extends AnalyticsEvent {
  final String amountBucket;
  final String failureCode; // backend-defined enum, never raw exception text

  const PayoutFailed({required this.amountBucket, required this.failureCode});

  @override
  String get name => 'payout_failed';

  @override
  Map<String, Object?> get properties => {
        'amount_bucket': amountBucket,
        'failure_code': failureCode,
      };
}

// ---------------------------------------------------------------------------
// Wallet
// ---------------------------------------------------------------------------

class WalletTopupStarted extends AnalyticsEvent {
  final String amountBucket;
  final String method; // 'paystack_card' | 'eft' | ...

  const WalletTopupStarted({required this.amountBucket, required this.method});

  @override
  String get name => 'wallet_topup_started';

  @override
  Map<String, Object?> get properties => {
        'amount_bucket': amountBucket,
        'method': method,
      };
}

class WalletTopupCompleted extends AnalyticsEvent {
  final String amountBucket;
  final String method;

  const WalletTopupCompleted({
    required this.amountBucket,
    required this.method,
  });

  @override
  String get name => 'wallet_topup_completed';

  @override
  Map<String, Object?> get properties => {
        'amount_bucket': amountBucket,
        'method': method,
      };
}

class WalletTopupFailed extends AnalyticsEvent {
  final String amountBucket;
  final String method;
  final String failureCode;

  const WalletTopupFailed({
    required this.amountBucket,
    required this.method,
    required this.failureCode,
  });

  @override
  String get name => 'wallet_topup_failed';

  @override
  Map<String, Object?> get properties => {
        'amount_bucket': amountBucket,
        'method': method,
        'failure_code': failureCode,
      };
}

// ---------------------------------------------------------------------------
// Communications (SMS / WhatsApp / push)
// ---------------------------------------------------------------------------

class CommsSent extends AnalyticsEvent {
  final String channel; // 'sms' | 'whatsapp' | 'push'
  final String templateId; // never the rendered body
  final int recipientCount;

  const CommsSent({
    required this.channel,
    required this.templateId,
    required this.recipientCount,
  });

  @override
  String get name => 'comms_sent';

  @override
  Map<String, Object?> get properties => {
        'channel': channel,
        'template_id': templateId,
        'recipient_count': recipientCount,
      };
}

class ActivationNudgeOpened extends AnalyticsEvent {
  final String nudgeType;
  final String action;
  final String channel;

  const ActivationNudgeOpened({
    required this.nudgeType,
    required this.action,
    required this.channel,
  });

  @override
  String get name => 'activation_nudge_opened';

  @override
  Map<String, Object?> get properties => {
        'nudge_type': nudgeType,
        'action': action,
        'channel': channel,
      };
}

class OrderingLinkCreated extends AnalyticsEvent {
  final String source; // 'settings' | 'stock_readiness' | 'activation_nudge'
  final bool regenerated;

  const OrderingLinkCreated({
    required this.source,
    required this.regenerated,
  });

  @override
  String get name => 'ordering_link_created';

  @override
  Map<String, Object?> get properties => {
        'source': source,
        'regenerated': regenerated,
      };
}

class OrderingLinkShared extends AnalyticsEvent {
  final String
      channel; // 'native_share' | 'whatsapp' | 'copy_link' | 'copy_code'

  const OrderingLinkShared({required this.channel});

  @override
  String get name => 'ordering_link_shared';

  @override
  Map<String, Object?> get properties => {'channel': channel};
}

// ---------------------------------------------------------------------------
// Consent (meta-events about telemetry itself)
// ---------------------------------------------------------------------------

class ConsentDecided extends AnalyticsEvent {
  final bool analytics;
  final bool replay;
  final bool crash;
  final String surface; // 'first_run_modal' | 'post_auth_sheet' | settings

  const ConsentDecided({
    required this.analytics,
    required this.replay,
    required this.crash,
    required this.surface,
  });

  @override
  String get name => 'consent_decided';

  @override
  Map<String, Object?> get properties => {
        'analytics': analytics,
        'replay': replay,
        'crash': crash,
        'surface': surface,
      };
}

// ---------------------------------------------------------------------------
// Stock CRUD
// ---------------------------------------------------------------------------
//
// PAS-UX-16: the onboarding funnel ('signup -> first product -> first
// customer -> first sale -> first message') was missing two of its
// most important hops because product and customer CRUD weren't
// instrumented. The Sale and Comms events were fine, but you couldn't
// tell from the dashboard whether merchants were dropping off at
// stock seeding, customer entry, or actually transacting. These
// events close that gap.
//
// Properties intentionally exclude product / customer NAMES and any
// free-form notes. Group, price-bucket and quantity-bucket are coarse
// signals that help the funnel without leaking merchant data.

class ProductCreated extends AnalyticsEvent {
  final String? group;
  final String sellingPriceBucket;
  final String costPriceBucket;
  final bool hasImage;

  const ProductCreated({
    this.group,
    required this.sellingPriceBucket,
    required this.costPriceBucket,
    required this.hasImage,
  });

  @override
  String get name => 'product_created';

  @override
  Map<String, Object?> get properties => {
        'group': group,
        'selling_price_bucket': sellingPriceBucket,
        'cost_price_bucket': costPriceBucket,
        'has_image': hasImage,
      };
}

class ProductUpdated extends AnalyticsEvent {
  final String? group;
  final String sellingPriceBucket;
  final String costPriceBucket;
  final bool hasImage;

  const ProductUpdated({
    this.group,
    required this.sellingPriceBucket,
    required this.costPriceBucket,
    required this.hasImage,
  });

  @override
  String get name => 'product_updated';

  @override
  Map<String, Object?> get properties => {
        'group': group,
        'selling_price_bucket': sellingPriceBucket,
        'cost_price_bucket': costPriceBucket,
        'has_image': hasImage,
      };
}

class ProductDeleted extends AnalyticsEvent {
  final String? group;

  const ProductDeleted({this.group});

  @override
  String get name => 'product_deleted';

  @override
  Map<String, Object?> get properties => {'group': group};
}

class WhatsAppCatalogStatusLoaded extends AnalyticsEvent {
  const WhatsAppCatalogStatusLoaded({
    required this.rollout,
    required this.liveBucket,
    required this.needsAttentionBucket,
    required this.source,
    required this.latencyBucket,
    required this.cacheAgeBucket,
  });

  final String rollout;
  final String liveBucket;
  final String needsAttentionBucket;
  final String source;
  final String latencyBucket;
  final String cacheAgeBucket;

  @override
  String get name => 'whatsapp_catalog_status_loaded';

  @override
  Map<String, Object?> get properties => {
        'rollout': rollout,
        'live_bucket': liveBucket,
        'needs_attention_bucket': needsAttentionBucket,
        'source': source,
        'latency_bucket': latencyBucket,
        'cache_age_bucket': cacheAgeBucket,
      };
}

class WhatsAppCatalogStatusActionOpened extends AnalyticsEvent {
  const WhatsAppCatalogStatusActionOpened({
    required this.status,
    required this.action,
  });

  final String status;
  final String action;

  @override
  String get name => 'whatsapp_catalog_status_action_opened';

  @override
  Map<String, Object?> get properties => {
        'status': status,
        'action': action,
      };
}

class WhatsAppCatalogStatusLoadFailed extends AnalyticsEvent {
  const WhatsAppCatalogStatusLoadFailed({
    required this.failure,
    required this.latencyBucket,
    required this.cacheAvailable,
  });

  final String failure;
  final String latencyBucket;
  final bool cacheAvailable;

  @override
  String get name => 'whatsapp_catalog_status_load_failed';

  @override
  Map<String, Object?> get properties => {
        'failure': failure,
        'latency_bucket': latencyBucket,
        'cache_available': cacheAvailable,
      };
}

class StockInvoiceViewerFailed extends AnalyticsEvent {
  const StockInvoiceViewerFailed({
    required this.fileType,
    required this.failure,
  });

  final String fileType;
  final String failure;

  @override
  String get name => 'stock_invoice_viewer_failed';

  @override
  Map<String, Object?> get properties => {
        'file_type': fileType,
        'failure': failure,
      };
}

// ---------------------------------------------------------------------------
// Contact CRUD
// ---------------------------------------------------------------------------
//
// CustomerCreateBlocked is a deliberate sub-event for duplicate-number
// rejections; it tells us how often the merchant tries to add a
// contact that already exists, which has been a recurring confusion
// point in support.

class CustomerCreated extends AnalyticsEvent {
  final bool hasImage;
  final String customerCountBucket;

  const CustomerCreated({
    required this.hasImage,
    required this.customerCountBucket,
  });

  @override
  String get name => 'customer_created';

  @override
  Map<String, Object?> get properties => {
        'has_image': hasImage,
        'customer_count_bucket': customerCountBucket,
      };
}

class CustomerCreateBlocked extends AnalyticsEvent {
  final String reason; // 'duplicate_number' | 'validation_failed'

  const CustomerCreateBlocked({required this.reason});

  @override
  String get name => 'customer_create_blocked';

  @override
  Map<String, Object?> get properties => {'reason': reason};
}

class CustomerUpdated extends AnalyticsEvent {
  final bool hasImage;

  const CustomerUpdated({required this.hasImage});

  @override
  String get name => 'customer_updated';

  @override
  Map<String, Object?> get properties => {'has_image': hasImage};
}

class CustomerDeleted extends AnalyticsEvent {
  const CustomerDeleted();

  @override
  String get name => 'customer_deleted';

  @override
  Map<String, Object?> get properties => const {};
}

// ---------------------------------------------------------------------------
// Review nudge
// ---------------------------------------------------------------------------

/// Fired when ReviewPromptService actually asked the OS to show the native
/// in-app review sheet. Note: the OS may suppress the prompt silently
/// (Apple/Google quotas), so this is an "asked" signal, not a "displayed"
/// one. We carry only the trigger name -- never sale amounts or customer
/// ids -- to keep the event PII-free.
class ReviewNudgeShown extends AnalyticsEvent {
  final String triggerName;

  const ReviewNudgeShown({required this.triggerName});

  @override
  String get name => 'review_nudge_shown';

  @override
  Map<String, Object?> get properties => {'trigger': triggerName};
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Coarse rand bucket helper. Centralised so every callsite uses the same
/// boundaries -- changing the buckets must remain a single edit.
String amountBucketZAR(num amount) {
  if (amount < 50) return '0-50';
  if (amount < 200) return '50-200';
  if (amount < 500) return '200-500';
  if (amount < 1000) return '500-1000';
  if (amount < 5000) return '1000-5000';
  if (amount < 20000) return '5000-20000';
  return '20000+';
}

String productCountBucket(int count) {
  if (count <= 0) return '0';
  if (count == 1) return '1';
  if (count <= 3) return '2-3';
  if (count <= 5) return '4-5';
  return '6+';
}

String customerCountBucket(int count) {
  if (count <= 0) return '0';
  if (count == 1) return '1';
  if (count <= 4) return '2-4';
  if (count <= 9) return '5-9';
  return '10+';
}
