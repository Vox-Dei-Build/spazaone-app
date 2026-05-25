// WhatsApp-style transaction bubble for the Pay Later ledger.
//
// Visual contract (post-review):
//   - No outer Material Card / elevation. The bubble is a single rounded
//     container.
//   - Credits align left, with the bubble's sharp corner on the top-left
//     (chat-tail metaphor). Payments mirror to the right.
//   - First pass painted the whole bubble in a red/green wash. Stacked,
//     that turned the whole ledger into a Christmas-light effect — every
//     row competing for attention. A second pass swapped the wash for a
//     hairline coloured border, but borders read as "tagged thing"
//     rather than a clean message. The bubble is now a plain white card
//     with a soft drop shadow. Direction is still communicated by three
//     redundant signals: side of screen, colored arrow icon, colored
//     amount text.
//   - Three pieces of information per row: arrow icon, amount, time.
//     The product line sits below.
//
// Product names are resolved by the parent [ProductNameCache] rather than
// per-bubble Firestore reads (kills the previous N+1 pattern).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/transactions/widgets/product_name_cache.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

class TransactionCard extends StatelessWidget {
  final Map<String, dynamic> transaction;

  const TransactionCard(this.transaction, {super.key});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final isCredit = transaction['type'] == 'Credit';
    final amount = (transaction['amount'] as num?)?.toDouble() ?? 0.0;
    final time = _formatTime(transaction['date']);

    // Accent colours match the CustomerBalanceHero. Tint is no longer
    // used as a fill — only as a barely-there border so the bubble
    // reads as a clean card.
    final accent = isCredit ? const Color(0xFFC62828) : const Color(0xFF1B5E20);

    // Bubble corner radii: sharp on the tail side, rounded everywhere else.
    final radius = SizeConfig.heightMultiplier * 1.4;
    final bubbleShape = BorderRadius.only(
      topLeft: Radius.circular(isCredit ? 4 : radius),
      topRight: Radius.circular(isCredit ? radius : 4),
      bottomLeft: Radius.circular(radius),
      bottomRight: Radius.circular(radius),
    );

    final bubbleWidth =
        SizeConfig.screenWidth * (SizeConfig.screenWidth > 360 ? 0.78 : 0.92);

    final productLine = _ProductLine(
      products: transaction['products'],
    );

    return Align(
      alignment: isCredit ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: SizeConfig.heightMultiplier * 0.6,
        ),
        child: SizedBox(
          width: bubbleWidth,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: bubbleShape,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 3.5,
              vertical: SizeConfig.heightMultiplier * 1.1,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      isCredit
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      color: accent,
                      size: SizeConfig.imageSizeMultiplier * 4.5,
                    ),
                    SizedBox(width: SizeConfig.imageSizeMultiplier * 1.5),
                    Expanded(
                      child: Text(
                        CurrencyUtil.format(amount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: accent,
                          fontSize: SizeConfig.textMultiplier * 2.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (time != null)
                      Text(
                        time,
                        style: TextStyle(
                          color: const Color(0xFF6B7280),
                          fontSize: SizeConfig.textMultiplier * 1.3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                productLine,
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Robust parser — `date` can be ISO string (from the stream mapping)
  /// or a raw Firestore Timestamp on legacy paths. Returns null when we
  /// can't decode, so the row simply omits the time rather than crashing.
  String? _formatTime(dynamic raw) {
    DateTime? when;
    if (raw is String && raw.isNotEmpty) {
      when = DateTime.tryParse(raw);
    } else if (raw is DateTime) {
      when = raw;
    }
    if (when == null) return null;
    return DateFormat('HH:mm').format(when.toLocal());
  }
}

class _ProductLine extends StatelessWidget {
  final Map<String, dynamic>? products;

  const _ProductLine({this.products});

  @override
  Widget build(BuildContext context) {
    final ps = products;
    if (ps == null || ps.isEmpty) return const SizedBox.shrink();

    final firstId = ps.keys.first;
    final count = ps.length;

    // Resolved by the list-level ProductNameCache. Null = still loading
    // or out of scope; show a neutral placeholder rather than a spinner
    // per bubble (which previously caused visible flicker).
    final cache = context.watch<ProductNameCache?>();
    final resolved = cache?.nameFor(firstId);
    final name = resolved ?? '…';
    final text = count > 1 ? '$name + ${count - 1} more' : name;

    return Padding(
      padding: EdgeInsets.only(top: SizeConfig.heightMultiplier * 0.4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: SizeConfig.textMultiplier * 1.5,
          color: Colors.black87,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
