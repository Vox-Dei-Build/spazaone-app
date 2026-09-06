import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
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
    final totalProducts = viewModel.products.length;
    final selectedCount = viewModel.selectedProducts.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (viewModel.suggestedProducts.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Recently bought',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: viewModel.suggestedProducts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (chipCtx, index) {
                final product = viewModel.suggestedProducts[index];
                final label =
                    formatStringToCamelCase(product.name ?? 'Product');
                final alreadyInCart =
                    viewModel.selectedProducts.containsKey(product.id);
                return ActionChip(
                  avatar: Icon(
                    alreadyInCart ? Icons.check : Icons.add,
                    size: 16,
                  ),
                  label: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                    ),
                  ),
                  onPressed: () {
                    viewModel.addProduct(context, product.id!, 1);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await viewModel.loadProducts();
            if (!context.mounted) return;
            await showSearch<Product?>(
              context: context,
              delegate: ProductSearchDelegate(viewModel: viewModel),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: SpazaColors.border),
              borderRadius: BorderRadius.circular(16),
              color: SpazaColors.canvas,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(
                      12,
                    ),
                  ),
                  child: Icon(
                    Icons.search,
                    size: 24,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Find products to add',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        totalProducts > 0
                            ? 'Search by product name, then set the exact quantity you want.'
                            : 'Search products or create a new one if it is not listed yet.',
                        style: const TextStyle(
                          fontSize: 14,
                          color: SpazaColors.muted,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$selectedCount selected',
                      style: const TextStyle(
                        fontSize: 13,
                        color: SpazaColors.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
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
                  margin: const EdgeInsets.only(
                    bottom: 12,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
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
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(
                                    height: 4,
                                  ),
                                  Text(
                                    'Unit price: ${CurrencyUtil.format(unitPrice)}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: SpazaColors.muted,
                                    ),
                                  ),
                                  Text(
                                    'Available stock: $stock',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: SpazaColors.muted,
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(
                                    12,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const Text(
                                      'Qty',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: SpazaColors.muted,
                                      ),
                                    ),
                                    Text(
                                      quantity.toString(),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 24,
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
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 24,
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
                height: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: viewModel.currentPage > 0
                            ? Colors.green
                            : Colors.grey,
                        size: 24,
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
                        size: 24,
                      ),
                      onPressed: viewModel.nextPage,
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          const Column(
            children: [
              SizedBox(height: 16),
              Center(
                child: Text(
                  'No products added yet',
                  style: TextStyle(
                    fontSize: 18,
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
