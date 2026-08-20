import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/transaction_util.dart';

class SalesStatsCard extends StatefulWidget {
  final SalesViewModel viewModel;
  final DateTime? selectedDay;
  final DateTime? startDate;
  final DateTime? endDate;

  const SalesStatsCard({
    super.key,
    required this.viewModel,
    this.selectedDay,
    this.startDate,
    this.endDate,
  });

  @override
  State<SalesStatsCard> createState() => _SalesStatsCardState();
}

class _SalesStatsCardState extends State<SalesStatsCard> {
  @override
  Widget build(BuildContext context) {
    // Metrics
    final sales = widget.viewModel.totalSales;
    final stockAmount = widget.viewModel.totalStockAmount;
    final difference = sales - stockAmount;
    final cost = widget.viewModel.totalCost;
    final profit = widget.viewModel.totalProfit;
    final count = widget.viewModel.totalNumberOfSales;
    final marginPct = (sales > 0) ? (profit / sales * 100.0) : double.nan;

    final colors = Theme.of(context).colorScheme;

    return Card(
      key: const ValueKey('sales-summary'),
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      color: colors.surface,
      elevation: 2,
      shadowColor: colors.shadow.withValues(alpha: .12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        onTap: () => _showFullStats(
          context,
          sales,
          stockAmount,
          difference,
          cost,
          profit,
          count,
          marginPct,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFF30345F).withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      color: Color(0xFF30345F),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sales & stock',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          _buildPeriodText(
                            widget.selectedDay,
                            widget.startDate,
                            widget.endDate,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _OpenMetric(
                      label: 'Sales',
                      value: CurrencyUtil.format(sales),
                      valueColor: kPrimaryColor,
                      backgroundColor: kPrimaryColor.withValues(alpha: 0.08),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OpenMetric(
                      label: 'Stock bought',
                      value: CurrencyUtil.format(stockAmount),
                      valueColor: Colors.orange.shade800,
                      backgroundColor: Colors.orange.withValues(alpha: 0.09),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Difference',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    CurrencyUtil.format(difference),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF30345F),
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '$count ${count == 1 ? 'entry' : 'entries'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Cash view • difference is not profit',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullStats(
    BuildContext context,
    num sales,
    num stockAmount,
    num difference,
    num cost,
    num profit,
    int count,
    double marginPct,
  ) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final chipGap = SizeConfig.imageSizeMultiplier * 2; // ~8px

        return Padding(
          padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3), // ~12px
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top bar with grabber + title + close
              Row(
                children: [
                  // drag handle
                  Container(
                    width: 32,
                    height: 4,
                    margin: EdgeInsets.only(
                      right: SizeConfig.imageSizeMultiplier * 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _buildPeriodText(
                        widget.selectedDay,
                        widget.startDate,
                        widget.endDate,
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: SizeConfig.textMultiplier * 2, // ~15–16px
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(ctx).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 1.2),

              // 2-column grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: chipGap,
                mainAxisSpacing: chipGap,
                childAspectRatio: 2.4, // denser
                children: [
                  _StatChip(
                    title: 'Sales',
                    value: CurrencyUtil.format(toDouble(sales)),
                    icon: Icons.point_of_sale,
                    fg: const Color(0xFF0B5FFF),
                    bg: const Color(0x160B5FFF),
                  ),
                  _StatChip(
                    title: 'Stock Bought',
                    value: CurrencyUtil.format(toDouble(stockAmount)),
                    icon: Icons.inventory_2_outlined,
                    fg: const Color(0xFFC45D08),
                    bg: const Color(0x16F57C00),
                  ),
                  _StatChip(
                    title: 'Difference',
                    value: CurrencyUtil.format(toDouble(difference)),
                    icon: Icons.compare_arrows_rounded,
                    fg: const Color(0xFF30345F),
                    bg: const Color(0x1630345F),
                  ),
                  _StatChip(
                    title: 'Itemized Product Cost',
                    value: CurrencyUtil.format(toDouble(cost)),
                    icon: Icons.inventory_2_outlined,
                    fg: const Color(0xFFD14343),
                    bg: const Color(0x16D14343),
                  ),
                  _StatChip(
                    title: 'Itemized Product Profit',
                    value: CurrencyUtil.format(toDouble(profit)),
                    icon: Icons.trending_up_rounded,
                    fg: const Color(0xFF2E7D32),
                    bg: const Color(0x162E7D32),
                  ),
                  _StatChip(
                    title: 'No. of Entries',
                    value: count.toString(),
                    icon: Icons.receipt_long_outlined,
                    fg: const Color(0xFF6A1B9A),
                    bg: const Color(0x166A1B9A),
                  ),
                  if (marginPct.isFinite)
                    _StatChip(
                      title: 'Profit Margin',
                      value: '${marginPct.toStringAsFixed(1)}%',
                      icon: Icons.pie_chart_rounded,
                      fg: const Color(0xFF00897B),
                      bg: const Color(0x1600897B),
                    ),
                ],
              ),
              SizedBox(height: SizeConfig.heightMultiplier * 1.2),
              Text(
                'Difference compares sales with stock purchases. It is not profit because stock bought today may be sold later.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _buildPeriodText(
    DateTime? selectedDay,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    String fmt(DateTime d) => DateFormat.yMMMd().format(d);
    if (startDate != null && endDate != null) {
      return 'Sales & stock: ${fmt(startDate)} — ${fmt(endDate)}';
    }
    if (selectedDay != null) {
      final now = DateTime.now();
      final same = now.year == selectedDay.year &&
          now.month == selectedDay.month &&
          now.day == selectedDay.day;
      return same
          ? "Today's sales & stock"
          : 'Sales & stock: ${fmt(selectedDay)}';
    }
    return 'Sales Overview';
  }
}

class _OpenMetric extends StatelessWidget {
  const _OpenMetric({
    required this.label,
    required this.value,
    this.valueColor,
    this.backgroundColor,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: backgroundColor ??
              Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      );
}

class _StatChip extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color fg;
  final Color bg;

  const _StatChip({
    required this.title,
    required this.value,
    required this.icon,
    required this.fg,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 3, // ~12px
          vertical: SizeConfig.heightMultiplier * 1.2, // ~8–10px
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: fg),
            SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
            Expanded(
              child: DefaultTextStyle(
                style: TextStyle(color: Colors.black.withValues(alpha: 0.86)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.3, // ~10–11px
                        color: Colors.black.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 0.3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.7, // ~13px
                        fontWeight: FontWeight.w900,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
