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
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
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

  /// Pre-formatted short time-of-day or relative label (e.g. "14:32"
  /// or "3 days ago"). The bucket date is rendered in the section
  /// header above, so this stays terse.
  final String relativeTime;

  final VoidCallback onTap;

  /// Optional tiny outline badge — "Collected" / "Uncollected" — used
  /// when the merchant needs that signal independent of status.
  final CollectedBadge? collectedBadge;

  /// Show the last 6 characters of the id (or the whole id if it's
  /// already short). Sufficient to disambiguate adjacent rows without
  /// dominating the layout. Prepended with `#` to read as an id.
  String get _shortId {
    if (id.length <= 6) return '#$id';
    return '#${id.substring(id.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = status.color(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 4,
          vertical: SizeConfig.heightMultiplier * 1.4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top line: status pill (anchor). Total lives on the
                  // right column so the two primary facts sit on the
                  // same baseline.
                  _StatusDot(color: statusColor, label: status.label),
                  SizedBox(height: SizeConfig.heightMultiplier * 0.7),
                  // Subtitle: items · time · short id. Muted; the id
                  // is monospaced so it's visually distinct from the
                  // human-readable bits without shouting.
                  DefaultTextStyle(
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.4,
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (itemsCount != null)
                            TextSpan(
                              text:
                                  '${itemsCount!} item${itemsCount == 1 ? '' : 's'}',
                            ),
                          if (itemsCount != null && relativeTime.isNotEmpty)
                            const TextSpan(text: '  ·  '),
                          if (relativeTime.isNotEmpty)
                            TextSpan(text: relativeTime),
                          if ((itemsCount != null ||
                                  relativeTime.isNotEmpty) &&
                              _shortId.isNotEmpty)
                            const TextSpan(text: '  ·  '),
                          TextSpan(
                            text: _shortId,
                            style: TextStyle(
                              color: const Color(0xFF9CA3AF),
                              fontFamily: 'monospace',
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                              fontSize: SizeConfig.textMultiplier * 1.3,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 2.5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      totalText,
                      style: TextStyle(
                        color: kPrimaryColor,
                        fontWeight: FontWeight.w800,
                        fontSize: SizeConfig.textMultiplier * 1.85,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        height: 1.0,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: const Color(0xFFB0B5BD),
                      size: SizeConfig.imageSizeMultiplier * 5,
                    ),
                  ],
                ),
                if (collectedBadge != null) ...[
                  SizedBox(height: SizeConfig.heightMultiplier * 0.7),
                  _OutlineBadge(
                    text: collectedBadge!.text,
                    color: collectedBadge!.color,
                  ),
                ],
              ],
            ),
          ],
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
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 2.4,
        vertical: SizeConfig.heightMultiplier * 0.55,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
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
          SizedBox(width: SizeConfig.imageSizeMultiplier * 1.5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: SizeConfig.textMultiplier * 1.4,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlineBadge extends StatelessWidget {
  const _OutlineBadge({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 1.4,
        vertical: SizeConfig.heightMultiplier * 0.2,
      ),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.6), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: SizeConfig.textMultiplier * 1.05,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          height: 1.0,
        ),
      ),
    );
  }
}

class CollectedBadge {
  final String text;
  final Color color;
  const CollectedBadge({required this.text, required this.color});
}
