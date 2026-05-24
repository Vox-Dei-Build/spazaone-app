import 'package:flutter/material.dart';

/// Visual stepper that shows the merchant where the order sits in its
/// lifecycle and what comes next. Designed to live at the top of the
/// order detail page so it sets context before the user scrolls.
///
/// The widget is purely presentational — the parent computes the
/// current [OrderStage] from the same state booleans that drive
/// `ActionsBlock`, so the two views can never disagree.
class OrderProgressTracker extends StatelessWidget {
  const OrderProgressTracker({
    super.key,
    required this.stage,
    required this.isDelivery,
    this.isTerminal = false,
    this.terminalLabel,
  });

  final OrderStage stage;
  final bool isDelivery;

  /// True when the order was cancelled or rejected — we still render
  /// the tracker so the merchant can see how far it got, but flag the
  /// terminal state in muted/error color.
  final bool isTerminal;
  final String? terminalLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final steps = _stepsFor(isDelivery);
    final currentIndex = steps.indexWhere((s) => s.stage == stage);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isTerminal ? Icons.error_outline : Icons.timeline,
                  size: 16,
                  color: isTerminal
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  isTerminal
                      ? (terminalLabel ?? 'Order closed')
                      : 'Order progress',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isTerminal
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StepperRow(
              steps: steps,
              currentIndex: currentIndex,
              isTerminal: isTerminal,
            ),
            const SizedBox(height: 10),
            Text(
              isTerminal
                  ? (terminalLabel ??
                      'This order didn’t complete. No further action needed.')
                  : _captionFor(steps, currentIndex),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<_Step> _stepsFor(bool isDelivery) {
    if (isDelivery) {
      return const [
        _Step(OrderStage.newOrder, 'New', Icons.fiber_new_outlined),
        _Step(OrderStage.accepted, 'Accepted', Icons.check_circle_outline),
        _Step(OrderStage.driverAssigned, 'Driver',
            Icons.local_shipping_outlined),
        _Step(OrderStage.outForDelivery, 'On the way',
            Icons.directions_car_outlined),
        _Step(OrderStage.completed, 'Delivered', Icons.flag_outlined),
      ];
    }
    return const [
      _Step(OrderStage.newOrder, 'New', Icons.fiber_new_outlined),
      _Step(OrderStage.accepted, 'Accepted', Icons.check_circle_outline),
      _Step(OrderStage.readyForCollection, 'Ready',
          Icons.inventory_2_outlined),
      _Step(OrderStage.completed, 'Collected', Icons.flag_outlined),
    ];
  }

  static String _captionFor(List<_Step> steps, int currentIndex) {
    if (currentIndex < 0) return '';
    final current = steps[currentIndex];
    final next =
        currentIndex + 1 < steps.length ? steps[currentIndex + 1] : null;
    final currentLabel = current.label.toLowerCase();
    if (next == null) {
      return 'This order is $currentLabel. Nothing else needed.';
    }
    final nextLabel = next.label.toLowerCase();
    return 'Currently: $currentLabel. Next: $nextLabel.';
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.steps,
    required this.currentIndex,
    required this.isTerminal,
  });

  final List<_Step> steps;
  final int currentIndex;
  final bool isTerminal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final isDone = !isTerminal && i < currentIndex;
      final isCurrent = !isTerminal && i == currentIndex;

      Color circleColor;
      Color iconColor;
      Color labelColor;

      if (isTerminal) {
        circleColor = scheme.surfaceContainerHighest;
        iconColor = scheme.onSurfaceVariant.withValues(alpha: 0.5);
        labelColor = scheme.onSurfaceVariant.withValues(alpha: 0.6);
      } else if (isDone) {
        circleColor = scheme.primary;
        iconColor = scheme.onPrimary;
        labelColor = scheme.onSurface;
      } else if (isCurrent) {
        circleColor = scheme.primaryContainer;
        iconColor = scheme.onPrimaryContainer;
        labelColor = scheme.onSurface;
      } else {
        circleColor = scheme.surfaceContainerHighest;
        iconColor = scheme.onSurfaceVariant;
        labelColor = scheme.onSurfaceVariant;
      }

      children.add(
        Expanded(
          child: Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: circleColor,
                  shape: BoxShape.circle,
                  border: isCurrent
                      ? Border.all(color: scheme.primary, width: 2)
                      : null,
                ),
                child: Icon(
                  isDone ? Icons.check : step.icon,
                  size: 16,
                  color: iconColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                step.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: labelColor,
                      fontWeight:
                          isCurrent ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      );

      if (i < steps.length - 1) {
        final connectorDone = !isTerminal && i < currentIndex;
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: SizedBox(
              width: 18,
              child: Container(
                height: 2,
                color: connectorDone
                    ? scheme.primary
                    : scheme.outlineVariant,
              ),
            ),
          ),
        );
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// Logical stages used by [OrderProgressTracker]. The parent maps
/// raw order/payment state into one of these so the widget stays
/// dumb. `readyForCollection` is only used for pickup orders;
/// `driverAssigned` / `outForDelivery` are delivery-only.
enum OrderStage {
  newOrder,
  accepted,
  driverAssigned,
  outForDelivery,
  readyForCollection,
  completed,
}

class _Step {
  const _Step(this.stage, this.label, this.icon);
  final OrderStage stage;
  final String label;
  final IconData icon;
}

/// Helper that converts the existing order state booleans (computed in
/// `order_detail_page.dart`) into an [OrderStage]. Keeping this here
/// means the page doesn't need to know the stage enum at all — it just
/// hands over the same booleans it already calculates.
OrderStage resolveOrderStage({
  required bool isPendingMerchantReview,
  required bool isAcceptedOrder,
  required bool isOutForDelivery,
  required bool isDelivered,
  required bool isCollected,
  required bool isDelivery,
  required bool hasDriver,
}) {
  if (isDelivered || isCollected) return OrderStage.completed;
  if (isOutForDelivery) return OrderStage.outForDelivery;
  if (isAcceptedOrder) {
    if (isDelivery) {
      return hasDriver ? OrderStage.driverAssigned : OrderStage.accepted;
    }
    return OrderStage.readyForCollection;
  }
  if (isPendingMerchantReview) return OrderStage.newOrder;
  return OrderStage.newOrder;
}
