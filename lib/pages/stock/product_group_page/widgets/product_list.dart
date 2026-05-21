import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/promote/promotions_page.dart';
import 'package:pasella/pages/stock/product_card/product_card.dart';
import 'package:pasella/pages/stock/product_details/product_details.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/pages/wallet/tabs/info_center_tab.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/shared/widgets/onboarding/whatsapp_store_readiness_card.dart';
import 'package:provider/provider.dart';

class ProductList extends StatelessWidget {
  final StockViewModel viewModel;
  final String? groupName;

  /// PAS-UX-04: callbacks supplied by the parent so the empty-state can
  /// recover users instead of dead-ending. Optional so existing nested
  /// callers (group drilldown) can keep the original empty placeholder.
  final VoidCallback? onAddProduct;
  final VoidCallback? onWatchTutorial;

  const ProductList({
    Key? key,
    required this.viewModel,
    this.groupName,
    this.onAddProduct,
    this.onWatchTutorial,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return StreamBuilder<List<Product>>(
      stream: viewModel.streamProductsByGroup(groupName),
      builder: (BuildContext context, AsyncSnapshot<List<Product>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final products = snapshot.data ?? [];
        if (products.isEmpty) {
          // PAS-UX-04: the original empty state was an inert "No
          // products available" message — a dead screen on the very
          // tab a new merchant lands on. The Add Product affordance
          // existed only as a FAB and the tutorial was buried in a
          // kebab. Surface both as primary recovery actions inline so
          // the empty state itself becomes the onboarding moment.
          //
          // The widget is opt-in: nested callers (group drilldown)
          // don't pass handlers and keep the bare placeholder, since
          // an empty group is a different signal than an empty
          // catalogue.
          final showOnboarding = groupName == null && onAddProduct != null;
          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: SizeConfig.imageSizeMultiplier * 6,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: SizeConfig.imageSizeMultiplier * 18,
                    color: Colors.grey.withOpacity(0.5),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  Text(
                    showOnboarding
                        ? 'Your stock list is empty'
                        : 'No products in this group',
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 2.2,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (showOnboarding) ...[
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                    Text(
                      'Add products so you can record sales, choose what '
                      'appears in WhatsApp ordering, and keep internal-only '
                      'items off the store.',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.6,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 3),
                    ElevatedButton.icon(
                      onPressed: onAddProduct,
                      icon: const Icon(Icons.add),
                      label: const Text('Add your first product'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: SizeConfig.imageSizeMultiplier * 6,
                          vertical: SizeConfig.heightMultiplier * 1.5,
                        ),
                      ),
                    ),
                    if (onWatchTutorial != null) ...[
                      SizedBox(height: SizeConfig.heightMultiplier * 1),
                      TextButton.icon(
                        onPressed: onWatchTutorial,
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Watch a 2-min walkthrough'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        }
        final showStoreReadiness = groupName == null && onAddProduct != null;

        return CustomScrollView(
          slivers: [
            if (showStoreReadiness)
              SliverToBoxAdapter(
                child: WhatsAppStoreReadinessCard(
                  userId: viewModel.userId,
                  products: products,
                  onAddProduct: onAddProduct!,
                  onChooseWhatsAppProduct: () {
                    final firstProduct = products.first;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (_) => ProductDetailsPage(
                              docID: firstProduct.id!,
                              product: firstProduct,
                            ),
                      ),
                    );
                  },
                  onOpenCustomers: () {
                    context.read<AppModel>().updateCurrentIndex(0);
                  },
                  onOpenPromotions: () {
                    Navigator.of(context).pushNamed(PromotionsPage.id);
                  },
                  onOpenBanking: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder:
                            (_) => const WalletPage(
                              initialTab: WalletInitialTab.account,
                              initialAccountView: InfoView.banking,
                            ),
                      ),
                    );
                  },
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 2),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.7,
                  mainAxisSpacing: SizeConfig.heightMultiplier * 1.5,
                  crossAxisSpacing: SizeConfig.imageSizeMultiplier * 2,
                ),
                delegate: SliverChildBuilderDelegate((
                  BuildContext context,
                  int index,
                ) {
                  return ProductCard(
                    product: products[index],
                    docID: products[index].id!,
                  );
                }, childCount: products.length),
              ),
            ),
          ],
        );
      },
    );
  }
}
