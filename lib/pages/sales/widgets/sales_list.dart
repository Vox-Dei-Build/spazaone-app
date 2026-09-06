import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/pages/sales/widgets/sale_detail_page.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:shimmer/shimmer.dart';

class SalesList extends StatefulWidget {
  final SalesViewModel viewModel;
  final double bottomPadding;
  final List<Widget> header;
  final VoidCallback? onAddSale;
  final VoidCallback? onSaleChanged;

  const SalesList({
    super.key,
    required this.viewModel,
    this.bottomPadding = 0,
    this.onAddSale,
    this.onSaleChanged,
    this.header = const [],
  });

  @override
  State<SalesList> createState() => _SalesListState();
}

class _SalesListState extends State<SalesList> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final reader = viewModel.recordedSalesReader;

    return AnimatedBuilder(
      animation: reader,
      builder: (context, _) => StreamBuilder<List<Sale>>(
        stream: viewModel.sales,
        initialData: viewModel.cachedSales,
        builder: (context, snapshot) {
          final failed = reader.hasError || snapshot.hasError;
          if (!reader.hasCurrentData) {
            if (failed) {
              return _paddedScroll(
                RecordedSalesReadError(onRetry: reader.retry),
              );
            }
            return _buildShimmerPlaceholder();
          }

          final Widget? notice = failed
              ? RecordedSalesReadError(
                  showingPreviousData: true,
                  onRetry: reader.retry,
                )
              : reader.isLoading
                  ? const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      child: LinearProgressIndicator(
                        semanticsLabel: 'Updating recorded sales',
                      ),
                    )
                  : null;
          // The cache is updated with the totals before the broadcast event
          // arrives. Using it avoids a frame of old rows under new totals.
          final data = viewModel.cachedSales;
          if (data.isEmpty) {
            return _paddedScroll(
              SalesListEmptyState(onAddSale: widget.onAddSale),
              notice: notice,
            );
          }

          final header = [...widget.header, if (notice != null) notice];
          return ListView.builder(
            padding: EdgeInsets.only(bottom: widget.bottomPadding),
            itemCount: header.length + 1 + data.length,
            itemBuilder: (context, index) {
              if (index < header.length) return header[index];
              if (index == header.length) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                  child: Text(
                    'Entries',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                );
              }
              final sale = data[index - header.length - 1];
              return RecordedSaleTile(
                sale: sale,
                onTap: () async {
                  final changed = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => SaleDetailPage(sale: sale),
                    ),
                  );
                  if (changed == true && mounted) {
                    if (widget.onSaleChanged != null) {
                      widget.onSaleChanged!();
                    } else {
                      viewModel.updateSelectedDate(DateTime.now());
                    }
                  }
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _paddedScroll(Widget child, {Widget? notice}) {
    return ListView(
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      children: [
        ...widget.header,
        if (notice != null) notice,
        const SizedBox(height: 16),
        Center(child: child),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildShimmerPlaceholder() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...widget.header,
          ...List<Widget>.filled(
            5,
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Shimmer.fromColors(
                baseColor: SpazaColors.subtle,
                highlightColor: SpazaColors.surface,
                child: Container(
                  width: double.infinity,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: SpazaColors.surface,
                    borderRadius: BorderRadius.all(
                      Radius.circular(SpazaRadius.control),
                    ),
                  ),
                ),
              ),
            ),
            growable: false,
          ),
        ],
      ),
    );
  }
}

/// Recoverable read feedback, distinct from a verified empty sales period.
class RecordedSalesReadError extends StatelessWidget {
  const RecordedSalesReadError({
    super.key,
    required this.onRetry,
    this.showingPreviousData = false,
  });

  final VoidCallback onRetry;
  final bool showingPreviousData;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              showingPreviousData
                  ? 'Could not refresh sales.'
                  : 'Could not load sales for these dates.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              showingPreviousData
                  ? 'Showing the last loaded entries and totals for these dates.'
                  : 'Check your connection and try again.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: kSecondaryAccent,
                  ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('recorded-sales-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Try again'),
              ),
            ),
          ],
        ),
      );
}

/// A readable recorded-sale entry that also works without a view model.
class RecordedSaleTile extends StatelessWidget {
  const RecordedSaleTile({
    super.key,
    required this.sale,
    required this.onTap,
  });

  final Sale sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat(sale.dateAdded.year == DateTime.now().year
            ? 'EEE, d MMM'
            : 'EEE, d MMM yyyy')
        .format(sale.dateAdded);
    final fullDate = DateFormat('EEE, d MMM yyyy').format(sale.dateAdded);
    final time = DateFormat('HH:mm').format(sale.dateAdded);
    final amount = CurrencyUtil.format(sale.amount);
    final stockAmount = CurrencyUtil.format(sale.stockAmount);
    final dateWidget = Text(
      date,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: kTertiaryColor,
        fontWeight: FontWeight.w500,
      ),
    );
    final timeWidget = Text(
      time,
      style: theme.textTheme.bodySmall?.copyWith(color: kSecondaryAccent),
    );
    final amountWidget = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        amount,
        style: theme.textTheme.titleMedium?.copyWith(
          color: kTertiaryColor,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    final stockWidget = Text(
      'Stock bought $stockAmount',
      style: theme.textTheme.bodySmall?.copyWith(color: kSecondaryAccent),
    );

    return Semantics(
      button: true,
      onTap: onTap,
      label: '$fullDate at $time. Sales $amount. Stock bought $stockAmount.',
      hint: 'Open sale details',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(SpazaRadius.control),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(SpazaRadius.control),
            child: Container(
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stack = constraints.maxWidth < 300 ||
                      MediaQuery.textScalerOf(context).scale(14) > 19;
                  if (stack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: dateWidget),
                            const SizedBox(width: 8),
                            const Icon(SpazaIcons.next, size: 20),
                          ],
                        ),
                        const SizedBox(height: 2),
                        timeWidget,
                        const SizedBox(height: 10),
                        amountWidget,
                        const SizedBox(height: 2),
                        stockWidget,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            dateWidget,
                            const SizedBox(height: 5),
                            timeWidget
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            amountWidget,
                            const SizedBox(height: 5),
                            stockWidget
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(SpazaIcons.next, size: 18),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cash-sales empty state, extracted for focused widget testing.
class SalesListEmptyState extends StatelessWidget {
  const SalesListEmptyState({super.key, this.onAddSale});

  final VoidCallback? onAddSale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              SpazaIcons.sales,
              size: 28,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No recorded sales yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          if (onAddSale != null) ...[
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: onAddSale,
              icon: const Icon(SpazaIcons.add),
              label: const Text('Record sale'),
            ),
          ],
        ],
      ),
    );
  }
}
