import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/transactions/widgets/product_search_delegate.dart';
import 'package:pasella/pages/transactions/widgets/quantity_input_sheet.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';

class ProductSelectionWidget<T extends TransactionViewModel>
    extends StatelessWidget {
  final T viewModel;

  const ProductSelectionWidget({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final totalProducts = viewModel.products.length;
    final selectedCount = viewModel.selectedProducts.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (viewModel.productSelectionNotice case final notice?) ...[
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 3,
              vertical: SizeConfig.heightMultiplier,
            ),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(
                SizeConfig.imageSizeMultiplier * 3,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: SizeConfig.imageSizeMultiplier * 4.5,
                  color: Theme.of(context).colorScheme.primary,
                ),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                Expanded(
                  child: Text(
                    notice,
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.45,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 1.5),
        ],
        if (viewModel.suggestedProducts.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Recently bought',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.8,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 1),
          SizedBox(
            height: SizeConfig.heightMultiplier * 5,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: viewModel.suggestedProducts.length,
              separatorBuilder: (_, __) =>
                  SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
              itemBuilder: (chipCtx, index) {
                final product = viewModel.suggestedProducts[index];
                final label =
                    formatStringToCamelCase(product.name ?? 'Product');
                final alreadyInCart =
                    viewModel.selectedProducts.containsKey(product.id);
                return ActionChip(
                  avatar: Icon(
                    alreadyInCart ? Icons.check : Icons.add,
                    size: SizeConfig.imageSizeMultiplier * 4,
                  ),
                  label: Text(
                    label,
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.7,
                    ),
                  ),
                  onPressed: () {
                    viewModel.addProduct(context, product.id!, 1);
                  },
                );
              },
            ),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 2),
        ],
        InkWell(
          borderRadius:
              BorderRadius.circular(SizeConfig.imageSizeMultiplier * 4),
          onTap: () async {
            await viewModel.loadProducts();
            if (!context.mounted) return;
            await showSearch<Product?>(
              context: context,
              delegate: ProductSearchDelegate(viewModel: viewModel),
            );
          },
          child: Container(
            padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius:
                  BorderRadius.circular(SizeConfig.imageSizeMultiplier * 4),
              color: Colors.grey.shade50,
            ),
            child: Row(
              children: [
                Container(
                  width: SizeConfig.imageSizeMultiplier * 11,
                  height: SizeConfig.imageSizeMultiplier * 11,
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(
                      SizeConfig.imageSizeMultiplier * 3,
                    ),
                  ),
                  child: Icon(
                    Icons.search,
                    size: SizeConfig.imageSizeMultiplier * 6,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find products to add',
                        style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: SizeConfig.heightMultiplier * 0.5),
                      Text(
                        totalProducts > 0
                            ? 'Search by product name, then set the exact quantity you want.'
                            : 'Search products or create a new one if it is not listed yet.',
                        style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.55,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Browse',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.55,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 0.4),
                    Text(
                      '$selectedCount selected',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.35,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        if (viewModel.selectedProducts.isNotEmpty)
          Column(
            children: [
              ...viewModel.paginatedSelectedProducts.map((entry) {
                final product = viewModel.productById(entry.key);
                final productName = formatStringToCamelCase(
                  product.name ?? 'Unnamed Product',
                );
                final quantity = entry.value;
                final unitPrice = product.sellingPrice ?? 0;
                final stock = viewModel.availableStockFor(entry.key);

                return Card(
                  margin: EdgeInsets.only(
                    bottom: SizeConfig.heightMultiplier * 1.2,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    productName,
                                    style: TextStyle(
                                      fontSize:
                                          SizeConfig.textMultiplier * 1.95,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(
                                    height: SizeConfig.heightMultiplier * 0.5,
                                  ),
                                  Text(
                                    'Unit price: ${CurrencyUtil.format(unitPrice)}',
                                    style: TextStyle(
                                      fontSize:
                                          SizeConfig.textMultiplier * 1.55,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  Text(
                                    'Available stock: $stock',
                                    style: TextStyle(
                                      fontSize:
                                          SizeConfig.textMultiplier * 1.45,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final picked = await QuantityInputSheet.show(
                                  context,
                                  productName: productName,
                                  currentQuantity: quantity,
                                );
                                if (picked == null || !context.mounted) return;
                                viewModel.updateProductQuantity(
                                  context,
                                  entry.key,
                                  picked,
                                );
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal:
                                      SizeConfig.imageSizeMultiplier * 3,
                                  vertical: SizeConfig.heightMultiplier * 0.9,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(
                                    SizeConfig.imageSizeMultiplier * 3,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      'Qty',
                                      style: TextStyle(
                                        fontSize:
                                            SizeConfig.textMultiplier * 1.25,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    Text(
                                      quantity.toString(),
                                      style: TextStyle(
                                        fontSize:
                                            SizeConfig.textMultiplier * 2.1,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: SizeConfig.heightMultiplier * 1.2),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.remove_circle_outline,
                                size: SizeConfig.imageSizeMultiplier * 6,
                              ),
                              onPressed: () {
                                viewModel.updateProductQuantity(
                                  context,
                                  entry.key,
                                  quantity - 1,
                                );
                              },
                            ),
                            Expanded(
                              child: Text(
                                'Line total: ${CurrencyUtil.format(unitPrice * quantity)}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: SizeConfig.textMultiplier * 1.7,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.add_circle_outline,
                                size: SizeConfig.imageSizeMultiplier * 6,
                              ),
                              onPressed: () {
                                viewModel.updateProductQuantity(
                                  context,
                                  entry.key,
                                  quantity + 1,
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              SizedBox(
                height: SizeConfig.heightMultiplier * 4,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: viewModel.currentPage > 0
                            ? Colors.green
                            : Colors.grey,
                        size: SizeConfig.imageSizeMultiplier * 6,
                      ),
                      onPressed: viewModel.previousPage,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.arrow_forward,
                        color: (viewModel.currentPage + 1) *
                                    viewModel.itemsPerPage <
                                viewModel.selectedProducts.length
                            ? Colors.green
                            : Colors.grey,
                        size: SizeConfig.imageSizeMultiplier * 6,
                      ),
                      onPressed: viewModel.nextPage,
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              SizedBox(height: SizeConfig.heightMultiplier * 3),
              Center(
                child: Text(
                  'No products added yet',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
