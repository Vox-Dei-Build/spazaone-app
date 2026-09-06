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
          borderRadius: BorderRadius.circular(SpazaRadius.control),
          onTap: () async {
            await viewModel.loadProducts();
            if (!context.mounted) return;
            await showSearch<Product?>(
              context: context,
              delegate: ProductSearchDelegate(viewModel: viewModel),
            );
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(
              horizontal: SpazaSpace.md,
              vertical: SpazaSpace.sm,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: SpazaColors.border),
              borderRadius: BorderRadius.circular(SpazaRadius.control),
              color: SpazaColors.surface,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: SpazaSpace.sm),
                Expanded(
                  child: Text(
                    totalProducts > 0 ? 'Choose products' : 'Find a product',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                if (selectedCount > 0) ...[
                  Text(
                    '$selectedCount',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: SpazaColors.heading,
                        ),
                  ),
                  const SizedBox(width: SpazaSpace.sm),
                ],
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: SpazaColors.muted,
                ),
              ],
            ),
          ),
        ),
        if (viewModel.selectedProducts.isNotEmpty) ...[
          const SizedBox(height: SpazaSpace.md),
          ...viewModel.paginatedSelectedProducts.map((entry) {
            final product = viewModel.productById(entry.key);
            final productName = formatStringToCamelCase(
              product.name ?? 'Unnamed Product',
            );
            final quantity = entry.value;
            final unitPrice = product.sellingPrice ?? 0;
            final stock = viewModel.availableStockFor(entry.key);

            return Card(
              margin: const EdgeInsets.only(bottom: SpazaSpace.sm),
              child: Padding(
                padding: const EdgeInsets.all(SpazaSpace.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            productName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          const SizedBox(height: SpazaSpace.xs),
                          Text(
                            '${CurrencyUtil.format(unitPrice)} each · $stock in stock',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: SpazaColors.muted,
                                    ),
                          ),
                          Text(
                            CurrencyUtil.format(unitPrice * quantity),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: SpazaColors.heading,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove one $productName',
                      icon: const Icon(Icons.remove_circle_outline, size: 22),
                      onPressed: () => viewModel.updateProductQuantity(
                        context,
                        entry.key,
                        quantity - 1,
                      ),
                    ),
                    Semantics(
                      button: true,
                      label:
                          'Set quantity for $productName, currently $quantity',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(SpazaRadius.small),
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
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 48,
                          ),
                          child: Center(
                            child: Text(
                              '$quantity',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(color: SpazaColors.heading),
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Add one $productName',
                      icon: const Icon(Icons.add_circle_outline, size: 22),
                      onPressed: () => viewModel.updateProductQuantity(
                        context,
                        entry.key,
                        quantity + 1,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (viewModel.selectedProducts.length > viewModel.itemsPerPage)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Previous products',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed:
                      viewModel.currentPage > 0 ? viewModel.previousPage : null,
                ),
                IconButton(
                  tooltip: 'Next products',
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed:
                      (viewModel.currentPage + 1) * viewModel.itemsPerPage <
                              viewModel.selectedProducts.length
                          ? viewModel.nextPage
                          : null,
                ),
              ],
            ),
        ],
      ],
    );
  }
}
