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

  const SaleCompleted({
    required this.amountBucket,
    required this.isCredit,
    required this.customerIsExisting,
  });

  @override
  String get name => 'sale_completed';

  @override
  Map<String, Object?> get properties => {
        'amount_bucket': amountBucket,
        'is_credit': isCredit,
        'customer_is_existing': customerIsExisting,
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

  const BnplOfferAccepted({
    required this.amountBucket,
    required this.termDays,
  });

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

  const PayoutFailed({
    required this.amountBucket,
    required this.failureCode,
  });

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

  const WalletTopupStarted({
    required this.amountBucket,
    required this.method,
  });

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

// ---------------------------------------------------------------------------
// Consent (meta-events about telemetry itself)
// ---------------------------------------------------------------------------

class ConsentDecided extends AnalyticsEvent {
  final bool analytics;
  final bool replay;
  final bool crash;
  final String surface; // 'first_run_modal' | 'settings_privacy'

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
  Map<String, Object?> get properties => {
        'group': group,
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

  const CustomerCreated({required this.hasImage});

  @override
  String get name => 'customer_created';

  @override
  Map<String, Object?> get properties => {
        'has_image': hasImage,
      };
}

class CustomerCreateBlocked extends AnalyticsEvent {
  final String reason; // 'duplicate_number' | 'validation_failed'

  const CustomerCreateBlocked({required this.reason});

  @override
  String get name => 'customer_create_blocked';

  @override
  Map<String, Object?> get properties => {
        'reason': reason,
      };
}

class CustomerUpdated extends AnalyticsEvent {
  final bool hasImage;

  const CustomerUpdated({required this.hasImage});

  @override
  String get name => 'customer_updated';

  @override
  Map<String, Object?> get properties => {
        'has_image': hasImage,
      };
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
  Map<String, Object?> get properties => {
        'trigger': triggerName,
      };
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
