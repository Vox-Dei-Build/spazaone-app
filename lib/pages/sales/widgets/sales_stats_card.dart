import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
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
    final cost = widget.viewModel.totalCost;
    final profit = widget.viewModel.totalProfit;
    final count = widget.viewModel.totalNumberOfSales;
    final marginPct = (sales > 0) ? (profit / sales * 100.0) : double.nan;

    final colors = Theme.of(context).colorScheme;
    final stack = MediaQuery.textScalerOf(context).scale(14) >= 20;
    final metrics = <Widget>[
      _SalesSummaryMetric(label: 'Sales', value: CurrencyUtil.format(sales)),
      _SalesSummaryMetric(label: 'Profit', value: CurrencyUtil.format(profit)),
      _SalesSummaryMetric(label: 'Recorded', value: count.toString()),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Material(
        color: colors.primaryContainer.withValues(alpha: .26),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.primary.withValues(alpha: .15)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('sales-summary'),
          onTap: () =>
              _showFullStats(context, sales, cost, profit, count, marginPct),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stack) ...[
                  Text(
                    _buildPeriodText(
                      widget.selectedDay,
                      widget.startDate,
                      widget.endDate,
                    ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _SalesDetailsLabel(color: colors.primary),
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _buildPeriodText(
                            widget.selectedDay,
                            widget.startDate,
                            widget.endDate,
                          ),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      _SalesDetailsLabel(color: colors.primary),
                    ],
                  ),
                const SizedBox(height: 16),
                if (stack)
                  for (var index = 0; index < metrics.length; index++) ...[
                    if (index > 0) Divider(color: colors.outlineVariant),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: metrics[index],
                    ),
                  ]
                else
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        for (var index = 0;
                            index < metrics.length;
                            index++) ...[
                          if (index > 0)
                            VerticalDivider(color: colors.outlineVariant),
                          Expanded(child: metrics[index]),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFullStats(
    BuildContext context,
    num sales,
    num cost,
    num profit,
    int count,
    double marginPct,
  ) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
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
              Row(
                children: [
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
                    title: 'Cost of products',
                    value: CurrencyUtil.format(toDouble(cost)),
                    icon: Icons.inventory_2_outlined,
                    fg: const Color(0xFFD14343),
                    bg: const Color(0x16D14343),
                  ),
                  _StatChip(
                    title: 'Profit',
                    value: CurrencyUtil.format(toDouble(profit)),
                    icon: Icons.trending_up_rounded,
                    fg: const Color(0xFF2E7D32),
                    bg: const Color(0x162E7D32),
                  ),
                  _StatChip(
                    title: 'Recorded sales',
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
      return 'Sales: ${fmt(startDate)} — ${fmt(endDate)}';
    }
    if (selectedDay != null) {
      final now = DateTime.now();
      final same = now.year == selectedDay.year &&
          now.month == selectedDay.month &&
          now.day == selectedDay.day;
      return same ? "Today's Sales" : 'Sales: ${fmt(selectedDay)}';
    }
    return 'Sales Overview';
  }
}

class _SalesSummaryMetric extends StatelessWidget {
  const _SalesSummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _SalesDetailsLabel extends StatelessWidget {
  const _SalesDetailsLabel({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Details',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(width: 2),
        Icon(Icons.chevron_right_rounded, size: 20, color: color),
      ],
    );
  }
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.3, // ~10–11px
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
