import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/new_product_page/new_product_page.dart';
import 'package:pasella/providers/transactional_view_model.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/string_utils.dart';

class ProductSearchDelegate extends SearchDelegate<Product?> {
  final TransactionViewModel viewModel;

  ProductSearchDelegate({required this.viewModel})
      : super(
          searchFieldLabel: 'Search products by name',
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
        );

  @override
  void showResults(BuildContext context) {
    viewModel.loadProducts();
    super.showResults(context);
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    SizeConfig().init(context);

    return [
      IconButton(
        icon: Icon(Icons.clear, size: SizeConfig.imageSizeMultiplier * 6),
        onPressed: () {
          query = '';
          showSuggestions(context);
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    SizeConfig().init(context);

    return IconButton(
      icon: Icon(Icons.arrow_back, size: SizeConfig.imageSizeMultiplier * 6),
      onPressed: () {
        close(context, null);
      },
    );
  }

  Widget _buildProductList(BuildContext context) {
    SizeConfig().init(context);

    final normalizedQuery = query.trim().toLowerCase();
    final matches = viewModel.filteredProducts.where((product) {
      final name = (product.name ?? '').toLowerCase();
      return normalizedQuery.isEmpty || name.contains(normalizedQuery);
    }).toList()
      ..sort((a, b) {
        final aSelected = viewModel.selectedProducts.containsKey(a.id) ? 1 : 0;
        final bSelected = viewModel.selectedProducts.containsKey(b.id) ? 1 : 0;
        if (aSelected != bSelected) return bSelected.compareTo(aSelected);
        final aStock = a.quantity ?? 0;
        final bStock = b.quantity ?? 0;
        if (aStock != bStock) return bStock.compareTo(aStock);
        return (a.name ?? '').compareTo(b.name ?? '');
      });

    if (matches.isEmpty) {
      return ListTile(
        title: Text(
          'No products found. Add a new product.',
          style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
        ),
        leading: Icon(Icons.add, size: SizeConfig.imageSizeMultiplier * 6),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (newProductContext) => NewProductPage(
                onProductAdded: (newProduct) async {
                  await viewModel.loadProducts();
                  if (!context.mounted) return;
                  final picked = await _promptQuantity(
                    context,
                    title: formatStringToCamelCase(
                      newProduct.name ?? 'New Product',
                    ),
                    initialQuantity: 1,
                    maxQuantity: newProduct.quantity ?? 0,
                  );
                  if (picked == null) return;
                  viewModel.addProduct(context, newProduct.id!, picked);
                  close(context, newProduct);
                },
              ),
            ),
          );
        },
      );
    }

    return ListView.separated(
      itemCount: matches.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final result = matches[index];
        final productName = formatStringToCamelCase(
          result.name ?? 'Unnamed Product',
        );
        final stock = result.quantity ?? 0;
        final selectedQty = result.id == null
            ? 0
            : (viewModel.selectedProducts[result.id!] ?? 0);
        final subtitleParts = <String>[
          'Stock: $stock',
          'Price: ${CurrencyUtil.format(result.sellingPrice ?? 0)}',
          if (selectedQty > 0) 'Selected: $selectedQty',
        ];

        return ListTile(
          leading: CircleAvatar(
            backgroundColor:
                Theme.of(context).colorScheme.primary.withOpacity(0.08),
            child: Icon(
              Icons.inventory_2_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          title: Text(
            productName,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            subtitleParts.join('  •  '),
            style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.45),
          ),
          trailing: TextButton.icon(
            onPressed: stock <= 0
                ? null
                : () async {
                    final picked = await _promptQuantity(
                      context,
                      title: productName,
                      initialQuantity: selectedQty > 0 ? selectedQty : 1,
                      maxQuantity: stock,
                    );
                    if (picked == null) return;
                    viewModel.updateProductQuantity(
                      context,
                      result.id!,
                      picked,
                    );
                    showSuggestions(context);
                  },
            icon: const Icon(Icons.add),
            label: Text(selectedQty > 0 ? 'Update' : 'Add'),
          ),
          onTap: stock <= 0
              ? null
              : () async {
                  final picked = await _promptQuantity(
                    context,
                    title: productName,
                    initialQuantity: selectedQty > 0 ? selectedQty : 1,
                    maxQuantity: stock,
                  );
                  if (picked == null) return;
                  viewModel.updateProductQuantity(context, result.id!, picked);
                  close(context, result);
                },
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildProductList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildProductList(context);

  Future<int?> _promptQuantity(
    BuildContext context, {
    required String title,
    required int initialQuantity,
    required int maxQuantity,
  }) async {
    final controller = TextEditingController(
      text: initialQuantity <= 0 ? '1' : initialQuantity.toString(),
    );
    String? errorText;

    return showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('Add quantity · $title'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Available stock: $maxQuantity'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Quantity',
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final parsed = int.tryParse(controller.text.trim());
                    if (parsed == null || parsed <= 0) {
                      setState(() {
                        errorText = 'Enter a valid quantity.';
                      });
                      return;
                    }
                    if (maxQuantity > 0 && parsed > maxQuantity) {
                      setState(() {
                        errorText = 'Only $maxQuantity item(s) available.';
                      });
                      return;
                    }
                    Navigator.pop(dialogContext, parsed);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
