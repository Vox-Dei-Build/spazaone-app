import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/pages/sales/widgets/sale_detail_page.dart';
import 'package:pasella/shared/widgets/empty_state_onboarding.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:shimmer/shimmer.dart';

class SalesList extends StatefulWidget {
  final SalesViewModel viewModel;
  final double bottomPadding;
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
          return _paddedScroll(Center(child: Text('Error: ${snapshot.error}')));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmerPlaceholder(); // adds padding inside
        }

        final data = snapshot.data ?? const <Sale>[];
        if (data.isEmpty) {
          return _paddedScroll(
            EmptyStateOnboarding(
              icon: Icons.point_of_sale_outlined,
              headline: 'No sales recorded yet',
              subtitle:
                  'Use Sales for a day-end revenue total or individual cash sale. Add products only when you need stock and profit detail.',
              ctaLabel:
                  widget.onAddSale != null ? 'Record your first sale' : null,
              onCtaTap: widget.onAddSale,
              tutorialKey: TutorialConfig.TUTORIAL_CAPTURE_SALES,
              tutorialTitle: 'How to record a sale',
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.only(bottom: widget.bottomPadding), // <- KEY
          itemCount: data.length,
          itemBuilder: (context, index) {
            final sale = data[index];
            return Card(
              margin: EdgeInsets.symmetric(
                vertical: SizeConfig.heightMultiplier * 0.5,
                horizontal: SizeConfig.imageSizeMultiplier * 2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  SizeConfig.imageSizeMultiplier * 2,
                ),
              ),
              elevation: 3.0,
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(
                  vertical: SizeConfig.heightMultiplier * 0.5,
                  horizontal: SizeConfig.imageSizeMultiplier * 2,
                ),
                title: Text(
                  "Date: ${DateFormat("dd-MM-yyyy HH:mm").format(sale.dateAdded)}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: SizeConfig.textMultiplier * 2,
                  ),
                ),
                subtitle: Text(
                  "Amount: ${CurrencyUtil.format(sale.amount)}",
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: SizeConfig.textMultiplier * 1.5,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios,
                  size: SizeConfig.imageSizeMultiplier * 4,
                  color: Colors.grey,
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
        children: List<Widget>.filled(
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
      ),
    );
  }
}
