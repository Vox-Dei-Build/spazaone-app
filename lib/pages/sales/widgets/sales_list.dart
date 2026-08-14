import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
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
          itemCount: widget.header.length + data.length,
          itemBuilder: (context, index) {
            if (index < widget.header.length) return widget.header[index];
            final sale = data[index - widget.header.length];
            return ListTile(
              minVerticalPadding: 12,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_outlined, size: 20),
              ),
              title: Text(
                DateFormat('dd MMM yyyy').format(sale.dateAdded),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(DateFormat('HH:mm').format(sale.dateAdded)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    CurrencyUtil.format(sale.amount),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
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
              shape: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
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
