import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/shared/widgets/spaza_shimmer.dart';
import 'package:pasella/utils/currency_util.dart';

class SalesStatsCard extends StatelessWidget {
  const SalesStatsCard({
    super.key,
    required this.viewModel,
    this.selectedDay,
    this.startDate,
    this.endDate,
    this.onRecordSale,
  });

  final SalesViewModel viewModel;
  final DateTime? selectedDay;
  final DateTime? startDate;
  final DateTime? endDate;
  final VoidCallback? onRecordSale;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: viewModel.recordedSalesReader,
        builder: (context, _) => SalesSummaryCard(
          sales: viewModel.totalSales,
          stockAmount: viewModel.totalStockAmount,
          cost: viewModel.totalCost,
          profit: viewModel.totalProfit,
          entryCount: viewModel.totalNumberOfSales,
          selectedDay: selectedDay,
          startDate: startDate,
          endDate: endDate,
          onRecordSale: onRecordSale,
          hasCurrentData: viewModel.recordedSalesReader.hasCurrentData,
          isLoading: viewModel.recordedSalesReader.isLoading,
        ),
      );
}

/// The same summary used by the recorded-sales page, without a data dependency.
class SalesSummaryCard extends StatelessWidget {
  const SalesSummaryCard({
    super.key,
    required this.sales,
    required this.stockAmount,
    required this.cost,
    required this.profit,
    required this.entryCount,
    this.selectedDay,
    this.startDate,
    this.endDate,
    this.onRecordSale,
    this.hasCurrentData = true,
    this.isLoading = false,
  });

  final double sales;
  final double stockAmount;
  final double cost;
  final double profit;
  final int entryCount;
  final DateTime? selectedDay;
  final DateTime? startDate;
  final DateTime? endDate;
  final VoidCallback? onRecordSale;
  final bool hasCurrentData;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recordButton = onRecordSale == null
        ? null
        : FilledButton.icon(
            key: const ValueKey('record-sale-action'),
            onPressed: onRecordSale,
            style: FilledButton.styleFrom(
              backgroundColor: kPrimaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SpazaRadius.control),
              ),
            ),
            icon: const Icon(SpazaIcons.add, size: 20),
            label: const Text('Record sale'),
          );

    // A missing or failed read is not a verified zero-sales period. Keep
    // recording available, but show no financial figures until the range loads.
    if (!hasCurrentData) {
      if (isLoading) {
        return SalesSummarySkeleton(onRecordSale: onRecordSale);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: recordButton ?? const SizedBox.shrink(),
        ),
      );
    }

    final total = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Total sales',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: kSecondaryAccent,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          label: 'Total sales ${CurrencyUtil.format(sales)}',
          excludeSemantics: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyUtil.format(sales),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: kTertiaryColor,
                fontSize: 30,
                fontWeight: FontWeight.w500,
                letterSpacing: -.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '$entryCount ${entryCount == 1 ? 'entry' : 'entries'}',
          style: theme.textTheme.bodySmall?.copyWith(color: kSecondaryAccent),
        ),
      ],
    );

    return Container(
      key: const ValueKey('sales-summary'),
      margin: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: SpazaColors.border),
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          total,
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              text: 'Stock bought  ',
              children: [
                TextSpan(
                  text: CurrencyUtil.format(stockAmount),
                  style: const TextStyle(
                    color: kTertiaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            style: theme.textTheme.bodySmall?.copyWith(color: kSecondaryAccent),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final details = TextButton(
                key: const ValueKey('sales-summary-details'),
                onPressed: () => _showDetails(context),
                style: TextButton.styleFrom(
                  foregroundColor: kTertiaryColor,
                  minimumSize: const Size(64, 52),
                ),
                child: const Text('Details'),
              );
              if (recordButton == null) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: details,
                );
              }
              if (constraints.maxWidth < 280 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    recordButton,
                    const SizedBox(height: 8),
                    details,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: recordButton),
                  const SizedBox(width: 12),
                  details,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String get _period {
    String format(DateTime date) => DateFormat.yMMMd().format(date);
    if (startDate != null && endDate != null) {
      return '${format(startDate!)} – ${format(endDate!)}';
    }
    if (selectedDay != null) return format(selectedDay!);
    return 'All dates';
  }

  void _showDetails(BuildContext context) {
    final margin = sales > 0 ? profit / sales * 100 : double.nan;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      // The modal's useSafeArea protects the top and sides only. Keep its
      // scroll viewport above Android navigation and any retained keyboard.
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Sales details',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: kTertiaryColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close sales details',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(SpazaIcons.close),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('sales-details-scroll'),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Long ranges scroll with the figures so the fixed
                        // close control cannot crowd out a short viewport.
                        Text(_period,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        _DetailValue('Total sales', CurrencyUtil.format(sales)),
                        _DetailValue(
                            'Stock bought', CurrencyUtil.format(stockAmount)),
                        _DetailValue('Difference',
                            CurrencyUtil.format(sales - stockAmount)),
                        const SizedBox(height: 8),
                        Text(
                          'Difference compares sales with stock purchases. It is not '
                          'profit because stock bought in this period may be sold later.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: kSecondaryAccent,
                                    height: 1.5,
                                  ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Product breakdown',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: kTertiaryColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        _DetailValue(
                            'Itemized product cost', CurrencyUtil.format(cost)),
                        _DetailValue('Itemized product profit',
                            CurrencyUtil.format(profit)),
                        if (margin.isFinite)
                          _DetailValue(
                              'Profit margin', '${margin.toStringAsFixed(1)}%'),
                        _DetailValue('Number of entries', '$entryCount'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mirrors the recorded-sales summary while its totals are loading.
class SalesSummarySkeleton extends StatelessWidget {
  const SalesSummarySkeleton({super.key, this.onRecordSale});

  final VoidCallback? onRecordSale;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('recorded-sales-summary-loading'),
        margin: const EdgeInsets.fromLTRB(4, 8, 4, 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: SpazaColors.border),
          borderRadius: BorderRadius.circular(SpazaRadius.surface),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SpazaShimmer(
              semanticsLabel: 'Loading sales totals',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SpazaSkeletonBox(height: 12, width: 82),
                  SizedBox(height: 12),
                  SpazaSkeletonBox(height: 30, width: 154),
                  SizedBox(height: 12),
                  SpazaSkeletonBox(height: 11, width: 68),
                  SizedBox(height: 14),
                  SpazaSkeletonBox(height: 11, width: 132),
                ],
              ),
            ),
            if (onRecordSale != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey('record-sale-action'),
                onPressed: onRecordSale,
                style: FilledButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SpazaRadius.control),
                  ),
                ),
                icon: const Icon(SpazaIcons.add, size: 20),
                label: const Text('Record sale'),
              ),
            ],
          ],
        ),
      );
}

class _DetailValue extends StatelessWidget {
  const _DetailValue(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelWidget = Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(color: kSecondaryAccent),
    );
    final valueWidget = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        style: theme.textTheme.titleMedium?.copyWith(
          color: kTertiaryColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: SpazaColors.border),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 340 ||
              MediaQuery.textScalerOf(context).scale(14) > 19) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelWidget, const SizedBox(height: 6), valueWidget],
            );
          }
          return Row(
            children: [
              Expanded(child: labelWidget),
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: valueWidget,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
