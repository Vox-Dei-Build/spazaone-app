import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/pages/sales/widgets/sale_detail_page.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:shimmer/shimmer.dart';

class SalesList extends StatefulWidget {
  final SalesViewModel viewModel;
  final double bottomPadding;
  final List<Widget> header;
  // PAS-AUTH-03: opt-in onboarding affordance. When non-null and the
  // list is empty the placeholder upgrades from a dead-end label into
  // the Stock-style CTA + walkthrough pattern. The Add Sale FAB still
  // lives on the parent page; this just exposes the same action where
  // the user is already looking.
  final VoidCallback? onAddSale;

  const SalesList({
    super.key,
    required this.viewModel,
    this.bottomPadding = 0,
    this.onAddSale,
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
    SizeConfig().init(context);
    final viewModel = widget.viewModel;

    return StreamBuilder<List<Sale>>(
      stream: viewModel.sales,
      initialData: viewModel.cachedSales,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _paddedScroll(
            const Center(
              child: Text(
                'Could not load sales. Check your connection and try again.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmerPlaceholder(); // adds padding inside
        }

        final data = snapshot.data ?? const <Sale>[];
        if (data.isEmpty) {
          return _paddedScroll(
            SalesListEmptyState(onAddSale: widget.onAddSale),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.only(bottom: widget.bottomPadding), // <- KEY
          itemCount: widget.header.length + 1 + data.length,
          itemBuilder: (context, index) {
            if (index < widget.header.length) return widget.header[index];
            if (index == widget.header.length) {
              return const _SalesColumnHeader();
            }
            final sale = data[index - widget.header.length - 1];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Material(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .42),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final changed = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => SaleDetailPage(sale: sale),
                      ),
                    );
                    if (changed == true) {
                      viewModel.updateSelectedDate(DateTime.now());
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: .45),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.receipt_long_outlined,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 7,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('dd MMM').format(sale.dateAdded),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                DateFormat('HH:mm').format(sale.dateAdded),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 6,
                          child: _SaleAmountValue(
                            semanticsLabel: 'Sales amount',
                            value: CurrencyUtil.format(sale.amount),
                            color: kPrimaryColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 6,
                          child: _SaleAmountValue(
                            semanticsLabel: 'Stock amount',
                            value: CurrencyUtil.format(sale.stockAmount),
                            color: Colors.orange.shade800,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _paddedScroll(Widget child) {
    return ListView(
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      children: [
        ...widget.header,
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        Center(child: child),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
      ],
    );
  }

  Widget _buildShimmerPlaceholder() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: widget.bottomPadding), // <- add padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ...widget.header,
          ...List<Widget>.filled(
            5,
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: SizeConfig.heightMultiplier * 0.5,
                horizontal: SizeConfig.imageSizeMultiplier * 2,
              ),
              child: Shimmer.fromColors(
                baseColor: Colors.black12,
                highlightColor: Colors.black26,
                child: Container(
                  width: SizeConfig.screenWidth,
                  height: SizeConfig.heightMultiplier * 2,
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: BorderRadius.all(
                      Radius.circular(SizeConfig.imageSizeMultiplier * 2),
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

class _SalesColumnHeader extends StatelessWidget {
  const _SalesColumnHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(68, 10, 34, 2),
      child: Row(
        children: [
          Expanded(flex: 7, child: Text('DATE', style: style)),
          const SizedBox(width: 6),
          Expanded(flex: 6, child: Text('SALES', style: style)),
          const SizedBox(width: 6),
          Expanded(
            flex: 6,
            child: Text(
              'STOCK BOUGHT',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleAmountValue extends StatelessWidget {
  const _SaleAmountValue({
    required this.semanticsLabel,
    required this.value,
    required this.color,
  });

  final String semanticsLabel;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$semanticsLabel $value',
      excludeSemantics: true,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.left,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

/// Compact cash-sales empty state, extracted for focused widget testing.
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
              Icons.point_of_sale_outlined,
              size: 28,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No recorded sales yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onAddSale != null) ...[
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: onAddSale,
              icon: const Icon(Icons.add),
              label: const Text('Record sale'),
            ),
          ],
        ],
      ),
    );
  }
}
