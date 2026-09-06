// PAS-UX-14: slim order row used by the redesigned Customer Orders
// list.
//
// The legacy `OrderTile` packed an avatar, an order id, a primary
// pill, a secondary collection pill, a total in the title, and then
// repeated the total again in the subtitle alongside "N items · long
// date" — five attention sinks per row. On a phone with 8–10 visible
// orders that's 40–50 elements competing for the eye.
//
// First-pass redesign promoted the order id (`#abcdef…`) to the top
// line. That turned out to be the wrong anchor: merchants scan the
// list for "what state is this in and how much is it for", not "what
// is its random id". The id reads as visual noise — every row leads
// with seven-ish near-identical hex characters.
//
// Current row:
//   * Top line  : colored status pill (left) + total (right). These
//                 are the two facts that drive every "what do I do
//                 with this row" decision.
//   * Subtitle  : `N items · 14:32 · #a3f92b` in muted grey, with the
//                 id truncated to the last 6 chars and rendered in
//                 monospaced tabular figures so two rows are still
//                 quickly distinguishable when needed (e.g. for a
//                 support call).
//   * Trailing  : optional outline "Collected / Uncollected" badge +
//                 chevron.
//
// Full id remains visible on the detail page for copy/share.

import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';

class OrderRow extends StatelessWidget {
  const OrderRow({
    super.key,
    required this.id,
    required this.status,
    required this.totalText,
    required this.itemsCount,
    required this.relativeTime,
    required this.onTap,
    this.collectedBadge,
  });

  final String id;
  final OrderStatus status;
  final String totalText;
  final int? itemsCount;
  final String relativeTime;
  final VoidCallback onTap;
  final CollectedBadge? collectedBadge;

  String get _shortId =>
      '#${id.length <= 6 ? id : id.substring(id.length - 6)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = status.color(context);
    final metadata = [
      if (itemsCount != null)
        '${itemsCount!} item${itemsCount == 1 ? '' : 's'}',
      if (relativeTime.isNotEmpty) relativeTime,
      _shortId,
    ].join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          key: ValueKey('customer-order-row-$id'),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: LayoutBuilder(builder: (context, constraints) {
            final stack = constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 20;
            final statusDetails = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusDot(color: statusColor, label: status.label),
                const SizedBox(height: 5),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: metadata.substring(
                          0,
                          metadata.length - _shortId.length,
                        ),
                      ),
                      TextSpan(
                        text: _shortId,
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontFamily: 'monospace',
                          fontFeatures: [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  maxLines: stack ? null : 1,
                  overflow:
                      stack ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
            final amount = FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                totalText,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: SpazaColors.action,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            );
            final totals = Column(
              crossAxisAlignment:
                  stack ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                amount,
                if (collectedBadge != null) ...[
                  const SizedBox(height: 5),
                  _OutlineBadge(
                    text: collectedBadge!.text,
                    color: collectedBadge!.color,
                  ),
                ],
              ],
            );
            if (stack) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [statusDetails, const SizedBox(height: 6), totals]);
            }
            return Row(children: [
              Expanded(child: statusDetails),
              const SizedBox(width: 12),
              Flexible(child: totals),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: SpazaColors.muted, size: 20),
            ]);
          }),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      );
}

class _OutlineBadge extends StatelessWidget {
  const _OutlineBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .6)),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      );
}

class CollectedBadge {
  final String text;
  final Color color;
  const CollectedBadge({required this.text, required this.color});
}
