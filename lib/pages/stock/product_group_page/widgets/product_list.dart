import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/contact/add_contact/add_contact.dart';
import 'package:pasella/pages/stock/product_card/product_card.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/shared/widgets/onboarding/activation_coachmark.dart';
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
          // PAS-UX-04 started by turning the empty catalogue into a
          // recovery surface. PAS-UX-rel keeps the page helpful but
          // makes customer capture the first onboarding action: a new
          // merchant can build a usable credit/sales workflow with
          // one saved customer, then add products when they need stock
          // or WhatsApp ordering detail.
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
                    Icons.person_add_alt_1_outlined,
                    size: SizeConfig.imageSizeMultiplier * 18,
                    color: Colors.grey.withValues(alpha: 0.5),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  Text(
                    showOnboarding
                        ? 'Start with your first customer'
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
                      'Save one customer first so Pay Later, sales history, '
                      'and WhatsApp follow-ups have someone to work with. '
                      'Products can come next.',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.6,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 3),
                    ActivationCoachmark(
                      userId: viewModel.userId,
                      coachmarkKey: 'add_first_customer_from_products',
                      title: 'Add a customer first',
                      message:
                          'Start with the person buying from you, then add products when stock detail matters.',
                      icon: Icons.person_add_alt_1_outlined,
                      child: ElevatedButton.icon(
                        onPressed: () => _openFirstCustomer(context),
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Add your first customer'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: SizeConfig.imageSizeMultiplier * 6,
                            vertical: SizeConfig.heightMultiplier * 1.5,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                    TextButton.icon(
                      onPressed: onAddProduct,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Add a product instead'),
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
        return CustomScrollView(
          slivers: [
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
                    key: ValueKey<String>(products[index].id!),
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

  void _openFirstCustomer(BuildContext context) {
    context.read<AppModel>().updateCurrentIndex(0);
    Navigator.of(context).pushNamed(AddContactPage.id);
  }
}
