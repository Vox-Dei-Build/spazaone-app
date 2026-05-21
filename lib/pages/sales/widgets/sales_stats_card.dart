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

    final hPad = SizeConfig.imageSizeMultiplier * 3; // ~12–14px
    final vPad = SizeConfig.heightMultiplier * 1.2; // ~8–10px
    final pillGap = SizeConfig.imageSizeMultiplier * 2; // ~8px

    return Card(
      margin: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.8,
        horizontal: SizeConfig.imageSizeMultiplier * 2,
      ),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SizeConfig.imageSizeMultiplier * 3),
      ),
      child: InkWell(
        onTap: () =>
            _showFullStats(context, sales, cost, profit, count, marginPct),
        child: Padding(
          padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
          child: Row(
            children: [
              // micro pills (scroll if tight)
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _MiniStatPill(
                          label: 'Revenue',
                          value: CurrencyUtil.format(sales),
                          fg: const Color(0xFF0B5FFF),
                          bg: const Color(0x140B5FFF),
                          icon: Icons.point_of_sale,
                        ),
                        SizedBox(width: pillGap / 2),
                        _MiniStatPill(
                          label: 'Profit',
                          value: CurrencyUtil.format(profit),
                          fg: const Color(0xFF2E7D32),
                          bg: const Color(0x142E7D32),
                          icon: Icons.trending_up_rounded,
                        ),
                        SizedBox(width: pillGap / 2),
                        _MiniStatPill(
                          label: 'Entries',
                          value: count.toString(),
                          fg: const Color(0xFF6A1B9A),
                          bg: const Color(0x146A1B9A),
                          icon: Icons.receipt_long_outlined,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: pillGap / 2),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
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
                    title: 'Revenue Recorded',
                    value: CurrencyUtil.format(toDouble(sales)),
                    icon: Icons.point_of_sale,
                    fg: const Color(0xFF0B5FFF),
                    bg: const Color(0x160B5FFF),
                  ),
                  _StatChip(
                    title: 'Total Cost',
                    value: CurrencyUtil.format(toDouble(cost)),
                    icon: Icons.inventory_2_outlined,
                    fg: const Color(0xFFD14343),
                    bg: const Color(0x16D14343),
                  ),
                  _StatChip(
                    title: 'Total Profit',
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

class _MiniStatPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color fg;
  final Color bg;

  const _MiniStatPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.fg,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 2.2, // ~9px
        vertical: SizeConfig.heightMultiplier * 0.7, // ~5px
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 1.6),
          Text(
            label,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.3, // ~10–11px
              color: Colors.black.withOpacity(0.6),
            ),
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 1.6),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: fg,
              fontSize: SizeConfig.textMultiplier * 1.4, // ~11–12px
            ),
          ),
        ],
      ),
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
                style: TextStyle(color: Colors.black.withOpacity(0.86)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.3, // ~10–11px
                        color: Colors.black.withOpacity(0.55),
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
