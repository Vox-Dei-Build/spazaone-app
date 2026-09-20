import 'package:flutter/material.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/dynamic_pricing_service.dart';
import 'package:pasella/services/messaging_notification_service.dart';
import 'package:pasella/shared/billing/cost_breakdown.dart';
import 'package:pasella/shared/billing/cost_confirmation_sheet.dart';
import 'package:pasella/shared/billing/cost_sheet_outcome.dart';
import 'package:pasella/utils/sms_pricing_util.dart';

enum TransactionSmsPrice { credit, payment }

enum TransactionPricingUnavailableAction {
  retry,
  saveWithoutSending,
  keepEditing,
}

typedef TransactionPricingLoader = Future<MessagingPricingSnapshotV1>
    Function();
typedef TransactionChannelResolver = Future<MessageChannelExpectation> Function(
    String mobileNumber);
typedef TransactionCostSheetPresenter = Future<CostSheetOutcome> Function(
  BuildContext context, {
  required CostBreakdown breakdown,
  required String confirmLabel,
  required String skipLabel,
  required bool confirmDismissal,
});
typedef TransactionPricingUnavailablePresenter
    = Future<TransactionPricingUnavailableAction> Function(
  BuildContext context,
);
typedef TransactionPricingErrorReporter = Future<void> Function(
  Object error,
  StackTrace stackTrace,
);

/// The result of the messaging choice that gates a transaction write.
///
/// A send-capable result always carries the exact server-owned pricing
/// snapshot and quoted total. An unavailable pricing request can only produce
/// [CostSheetOutcome.skip] or [CostSheetOutcome.keepEditing], so a paid send
/// never proceeds with a guessed or cached fallback rate.
class TransactionMessagingDecision {
  const TransactionMessagingDecision._({
    required this.outcome,
    this.pricingSnapshot,
    this.quotedTotal,
  });

  const TransactionMessagingDecision.recordOnly()
      : this._(outcome: CostSheetOutcome.skip);

  const TransactionMessagingDecision.keepEditing()
      : this._(outcome: CostSheetOutcome.keepEditing);

  const TransactionMessagingDecision.quoted({
    required CostSheetOutcome outcome,
    required MessagingPricingSnapshotV1 pricingSnapshot,
    required double quotedTotal,
  }) : this._(
          outcome: outcome,
          pricingSnapshot: pricingSnapshot,
          quotedTotal: quotedTotal,
        );

  final CostSheetOutcome outcome;
  final MessagingPricingSnapshotV1? pricingSnapshot;
  final double? quotedTotal;

  bool get canSend =>
      outcome.shouldSend && pricingSnapshot != null && quotedTotal != null;
}

/// Loads authoritative messaging pricing only when the merchant submits.
///
/// Pricing is intentionally not cached here. If a transient App Check or
/// network failure clears, pressing the submit action again makes a fresh
/// request. A customer without a mobile number does not need pricing because
/// there is no message path.
Future<TransactionMessagingDecision> chooseOptionalTransactionMessage(
  BuildContext context, {
  required String? mobileNumber,
  required String customerName,
  required String smsText,
  required TransactionSmsPrice smsPrice,
  required String title,
  required String confirmLabel,
  TransactionPricingLoader? loadPricing,
  TransactionChannelResolver? resolveChannel,
  TransactionCostSheetPresenter? showCostSheet,
  TransactionPricingUnavailablePresenter? showPricingUnavailable,
  TransactionPricingErrorReporter? reportPricingError,
}) async {
  final number = mobileNumber?.trim() ?? '';
  if (number.isEmpty) {
    return const TransactionMessagingDecision.recordOnly();
  }

  late MessagingPricingSnapshotV1 pricing;
  while (true) {
    try {
      pricing = await (loadPricing ??
          () => DynamicPricingService.loadSnapshot(
                retryReporter: _recordPricingRetry,
              ))();
      break;
    } catch (error, stackTrace) {
      final reporter = reportPricingError ?? _recordPricingError;
      await reporter(error, stackTrace);
      if (!context.mounted) {
        return const TransactionMessagingDecision.keepEditing();
      }

      final unavailableAction = await (showPricingUnavailable ??
          showTransactionPricingUnavailableChoice)(context);
      if (unavailableAction == TransactionPricingUnavailableAction.retry) {
        continue;
      }
      if (unavailableAction ==
          TransactionPricingUnavailableAction.saveWithoutSending) {
        return const TransactionMessagingDecision.recordOnly();
      }
      return const TransactionMessagingDecision.keepEditing();
    }
  }

  if (!context.mounted) {
    return const TransactionMessagingDecision.keepEditing();
  }

  MessageChannelExpectation expected;
  try {
    expected = await (resolveChannel ??
        MessagingNotificationService.resolveExpectedChannel)(number);
  } catch (_) {
    expected = MessageChannelExpectation.unknown;
  }
  if (!context.mounted) {
    return const TransactionMessagingDecision.keepEditing();
  }

  final smsUnitCost = switch (smsPrice) {
    TransactionSmsPrice.credit => pricing.smsCustomerMinor / 100,
    TransactionSmsPrice.payment => pricing.smsPaymentMinor / 100,
  };
  final smsCost = SMSPricingUtil.calculateCost(
    text: smsText,
    unitCost: smsUnitCost,
  );
  final breakdown = CostBreakdown.singleMessageMultiChannel(
    title: title,
    subtitle: 'Message to $customerName',
    whatsappCost: pricing.whatsappUtilityMinor / 100,
    smsCost: smsCost,
    expected: expected,
  );
  final outcome = await (showCostSheet ?? CostConfirmationSheet.showOutcome)(
    context,
    breakdown: breakdown,
    confirmLabel: confirmLabel,
    skipLabel: 'Done without sending',
    confirmDismissal: true,
  );

  return TransactionMessagingDecision.quoted(
    outcome: outcome,
    pricingSnapshot: pricing,
    quotedTotal: breakdown.total,
  );
}

Future<void> _recordPricingError(Object error, StackTrace stackTrace) {
  final safeError = MessagingPricingUnavailable.fromError(error);
  return CrashService.instance.recordNonFatal(
    safeError,
    stackTrace,
    reason: 'transaction messaging pricing unavailable',
    context: {
      'diagnostic_surface': 'transaction_confirmation',
      'diagnostic_stage': 'pricing',
      'diagnostic_code': safeError.code,
      'diagnostic_retry_outcome': 'exhausted_or_not_retryable',
    },
  );
}

Future<void> _recordPricingRetry({
  required String code,
  required String outcome,
}) {
  return CrashService.instance.log(
    'transaction pricing credential retry',
    context: {
      'diagnostic_surface': 'transaction_confirmation',
      'diagnostic_stage': 'credentials',
      'diagnostic_code': code,
      'diagnostic_retry_outcome': outcome,
    },
  );
}

/// Explicit fallback shown when a transaction can be recorded safely but a
/// paid message cannot be quoted. Closing the dialog also keeps the form open.
@visibleForTesting
Future<TransactionPricingUnavailableAction>
    showTransactionPricingUnavailableChoice(
  BuildContext context,
) async {
  final action = await showDialog<TransactionPricingUnavailableAction>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Message price unavailable'),
      content: const Text(
        'Save this transaction without sending a message, or keep editing.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(
            TransactionPricingUnavailableAction.keepEditing,
          ),
          child: const Text('Keep editing'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(
            TransactionPricingUnavailableAction.saveWithoutSending,
          ),
          child: const Text('Save without sending'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(
            TransactionPricingUnavailableAction.retry,
          ),
          child: const Text('Try again'),
        ),
      ],
    ),
  );
  return action ?? TransactionPricingUnavailableAction.keepEditing;
}
