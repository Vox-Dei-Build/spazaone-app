// PAS-UX-14: redesigned filter chip row for Customer Orders.
//
// The legacy version dumped all 13 raw `OrderStatus` values into a
// horizontally scrolling row of equal-weight `ChoiceChip`s. Two
// problems followed:
//
//   1. The chips merchants actually used (All, Pending, BNPL,
//      Delivery) competed for attention with eight long-tail chips
//      ("BNPL Outstanding", "Out for Delivery", …). Cognitive load
//      was high and the row scrolled off-screen.
//   2. There was no signal of how many orders were in each bucket,
//      so merchants tapped through chips just to discover empties.
//
// The redesign:
//   * Four primary chips, never scrolled: All, Pending, BNPL,
//     Delivery. Each shows a small count badge derived from the
//     cached server result (no extra query).
//   * A single "More" chip opens a bottom sheet listing the
//     remaining specific statuses (Accepted, Paid, Cancelled,
//     Rejected, Uncollected, Collected, Out for Delivery,
//     Delivered, BNPL Pending/Outstanding/Rejected) so power users
//     can still drill in.
//   * Selection state survives across primary and sheet: tapping
//     "Paid" in the sheet marks the More chip as "selected"
//     and shows "Paid" inline as its label, mirroring how Gmail
//     handles its labels filter.
//
// Selection model lives in `OrdersController` as an `OrdersFilter`
// union (group OR specific). This widget is purely presentational.

import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/ecommerce/orders_management/data/order_filters.dart';
import 'package:pasella/pages/ecommerce/widgets/order_status.dart';

class OrderFilterChips extends StatelessWidget {
  const OrderFilterChips({
    super.key,
    required this.filter,
    required this.counts,
    required this.onSelect,
  });

  final OrdersFilter filter;
  final Map<OrderFilterGroup, int> counts;
  final ValueChanged<OrdersFilter> onSelect;

  static const _primary = <_PrimaryChipDef>[
    _PrimaryChipDef(OrderFilterGroup.all, 'All'),
    _PrimaryChipDef(OrderFilterGroup.pending, 'Pending'),
    _PrimaryChipDef(OrderFilterGroup.bnpl, 'Pay Later'),
    _PrimaryChipDef(OrderFilterGroup.delivery, 'Delivery'),
  ];

  /// Statuses surfaced inside the More sheet. Ordered by how often a
  /// merchant might want them (purely a judgement call — easy to
  /// re-shuffle later).
  static const _moreStatuses = <OrderStatus>[
    OrderStatus.accepted,
    OrderStatus.paid,
    OrderStatus.uncollected,
    OrderStatus.collected,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
    OrderStatus.bnplPending,
    OrderStatus.bnplOutstanding,
    OrderStatus.bnplRejected,
    OrderStatus.cancelled,
    OrderStatus.rejected,
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 1.2,
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 0.8,
      ),
      child: Row(
        children: [
          for (final def in _primary) ...[
            _Chip(
              label: def.label,
              count: counts[def.group] ?? 0,
              selected: filter.group == def.group,
              onTap: () => onSelect(OrdersFilter.group(def.group)),
            ),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 1.8),
          ],
          _MoreChip(
            specific: filter.specific,
            onPick: (status) => onSelect(OrdersFilter.specific(status)),
            statuses: _moreStatuses,
          ),
        ],
      ),
    );
  }
}

class _PrimaryChipDef {
  final OrderFilterGroup group;
  final String label;
  const _PrimaryChipDef(this.group, this.label);
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? kPrimaryColor : const Color(0xFFF1F3F5);
    final fg = selected ? Colors.white : const Color(0xFF1A1F2B);
    final countBg = selected
        ? Colors.white.withOpacity(0.22)
        : Colors.black.withOpacity(0.06);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 3.2,
            vertical: SizeConfig.heightMultiplier * 0.95,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: SizeConfig.textMultiplier * 1.55,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
              if (count > 0) ...[
                SizedBox(width: SizeConfig.imageSizeMultiplier * 1.5),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: SizeConfig.imageSizeMultiplier * 1.4,
                    vertical: SizeConfig.heightMultiplier * 0.15,
                  ),
                  decoration: BoxDecoration(
                    color: countBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: TextStyle(
                      color: fg,
                      fontSize: SizeConfig.textMultiplier * 1.2,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreChip extends StatelessWidget {
  const _MoreChip({
    required this.specific,
    required this.onPick,
    required this.statuses,
  });

  final OrderStatus? specific;
  final ValueChanged<OrderStatus> onPick;
  final List<OrderStatus> statuses;

  Future<void> _openSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<OrderStatus>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MoreStatusesSheet(
        statuses: statuses,
        selected: specific,
      ),
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final hasSpecific = specific != null;
    final label = hasSpecific ? specific!.label : 'More';
    final selected = hasSpecific;
    final bg = selected ? kPrimaryColor : const Color(0xFFF1F3F5);
    final fg = selected ? Colors.white : const Color(0xFF1A1F2B);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _openSheet(context),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 3.2,
            vertical: SizeConfig.heightMultiplier * 0.95,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: SizeConfig.textMultiplier * 1.55,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 1.2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: fg,
                size: SizeConfig.imageSizeMultiplier * 4.5,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreStatusesSheet extends StatelessWidget {
  const _MoreStatusesSheet({required this.statuses, required this.selected});

  final List<OrderStatus> statuses;
  final OrderStatus? selected;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: EdgeInsets.only(
                  top: SizeConfig.heightMultiplier * 1.2,
                ),
                width: SizeConfig.imageSizeMultiplier * 10,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                SizeConfig.imageSizeMultiplier * 5,
                SizeConfig.heightMultiplier * 2,
                SizeConfig.imageSizeMultiplier * 5,
                SizeConfig.heightMultiplier * 0.8,
              ),
              child: Text(
                'Filter by status',
                style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.9,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: mq.size.height * 0.55),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: statuses.length,
                itemBuilder: (ctx, i) {
                  final s = statuses[i];
                  final isSel = s == selected;
                  return InkWell(
                    onTap: () => Navigator.of(ctx).pop(s),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: SizeConfig.imageSizeMultiplier * 5,
                        vertical: SizeConfig.heightMultiplier * 1.6,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: s.color(ctx),
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: SizeConfig.imageSizeMultiplier * 3),
                          Expanded(
                            child: Text(
                              s.label,
                              style: TextStyle(
                                fontSize: SizeConfig.textMultiplier * 1.7,
                                fontWeight:
                                    isSel ? FontWeight.w700 : FontWeight.w500,
                                color: const Color(0xFF1A1F2B),
                              ),
                            ),
                          ),
                          if (isSel)
                            Icon(
                              Icons.check_circle_rounded,
                              color: kPrimaryColor,
                              size: SizeConfig.imageSizeMultiplier * 5.5,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1.5),
          ],
        ),
      ),
    );
  }
}

/// Shimmer placeholder shown while the very first load is in flight.
/// Mirrors the geometry of `OrderFilterChips` so the swap is invisible.
class OrderFilterChipsSkeleton extends StatelessWidget {
  const OrderFilterChipsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 1.2,
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.heightMultiplier * 0.8,
      ),
      child: Row(
        children: List.generate(5, (i) {
          final w = [70.0, 95.0, 78.0, 100.0, 72.0][i];
          return Padding(
            padding:
                EdgeInsets.only(right: SizeConfig.imageSizeMultiplier * 1.8),
            child: Container(
              width: w,
              height: SizeConfig.heightMultiplier * 4.2,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F5),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          );
        }),
      ),
    );
  }
}
