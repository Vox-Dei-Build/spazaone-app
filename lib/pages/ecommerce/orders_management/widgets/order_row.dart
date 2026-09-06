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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SpazaRadius.surface),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    _badge(context, status.label, statusColor),
                    Text(totalText, style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 10),
                Text(metadata, style: theme.textTheme.bodySmall),
                if (collectedBadge != null) ...[
                  const SizedBox(height: 10),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: _badge(
                          context, collectedBadge!.text, collectedBadge!.color,
                          outlined: true)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, String label, Color color,
          {bool outlined = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(16),
          border:
              outlined ? Border.all(color: color.withValues(alpha: .6)) : null,
        ),
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: color)),
      );
}

class CollectedBadge {
  final String text;
  final Color color;
  const CollectedBadge({required this.text, required this.color});
}
