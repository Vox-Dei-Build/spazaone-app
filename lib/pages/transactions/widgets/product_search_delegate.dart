import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/new_product_page/new_product_page.dart';
import 'package:pasella/pages/stock/product_details/product_details.dart';
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

    // PAS-UX batch-add: the search sheet now stays open after each add so the
    // merchant can build the whole basket in one session. We expose two
    // always-present actions to avoid SearchDelegate rebuild quirks with
    // conditional/variable-length actions lists:
    //   1. Clear-query icon (disabled when there's nothing to clear).
    //   2. A live "Done · N" icon button that returns to the transaction form
    //      and reflects how many distinct lines are already in the basket.
    //
    // SearchDelegate doesn't rebuild buildActions when an external Listenable
    // (the view model) notifies, so the Done badge is wrapped in a
    // ListenableBuilder bound to the view model. This way every successful
    // add/remove/quantity update from anywhere in this flow refreshes the
    // basket count immediately, including updates that happen *after* the
    // quantity dialog is dismissed (which were previously stale until the
    // next add or until the merchant left and re-opened the picker).
    final hasQuery = query.isNotEmpty;

    return [
      IconButton(
        tooltip: 'Clear search',
        icon: Icon(Icons.clear, size: SizeConfig.imageSizeMultiplier * 6),
        onPressed: hasQuery
            ? () {
                query = '';
                showSuggestions(context);
              }
            : null,
      ),
      ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final basketCount = viewModel.selectedProducts.length;
          return IconButton(
            tooltip: basketCount > 0
                ? 'Done — $basketCount in basket'
                : 'Done',
            icon: Badge(
              isLabelVisible: basketCount > 0,
              label: Text('$basketCount'),
              child: Icon(
                Icons.check_circle_outline,
                size: SizeConfig.imageSizeMultiplier * 6,
              ),
            ),
            onPressed: () => close(context, null),
          );
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
                  final productName = formatStringToCamelCase(
                    newProduct.name ?? 'New Product',
                  );
                  final picked = await _promptQuantity(
                    context,
                    title: productName,
                    initialQuantity: 1,
                    maxQuantity: newProduct.quantity ?? 0,
                    confirmLabel: 'Add to transaction',
                  );
                  if (picked == null || !context.mounted) return;
                  viewModel.addProduct(context, newProduct.id!, picked);
                  _showSelectionFeedback(
                    context,
                    '$productName added to this transaction · Qty $picked',
                  );
                  // PAS-UX batch-add: keep the search sheet open so the
                  // merchant can immediately look for the next product
                  // instead of being kicked back to the form after each add.
                  _continueAdding(context);
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
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
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
          trailing: stock <= 0
              ? OutlinedButton.icon(
                  onPressed: result.id == null
                      ? null
                      : () async {
                          await _recoverOutOfStockProduct(
                            context,
                            product: result,
                            productName: productName,
                          );
                        },
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Add stock'),
                )
              : TextButton.icon(
                  onPressed: () async {
                    final picked = await _promptQuantity(
                      context,
                      title: productName,
                      initialQuantity: selectedQty > 0 ? selectedQty : 1,
                      maxQuantity: stock,
                      confirmLabel: selectedQty > 0
                          ? 'Update transaction'
                          : 'Add to transaction',
                    );
                    if (picked == null || !context.mounted) return;
                    await viewModel.updateProductQuantity(
                      context,
                      result.id!,
                      picked,
                    );
                    if (!context.mounted) return;
                    _showSelectionFeedback(
                      context,
                      selectedQty > 0
                          ? '$productName updated in this transaction · Qty $picked'
                          : '$productName added to this transaction · Qty $picked',
                    );
                    _continueAdding(context);
                  },
                  icon: const Icon(Icons.add),
                  label: Text(selectedQty > 0 ? 'Update' : 'Add'),
                ),
          onTap: () async {
            if (stock <= 0) {
              await _recoverOutOfStockProduct(
                context,
                product: result,
                productName: productName,
              );
              return;
            }
            final picked = await _promptQuantity(
              context,
              title: productName,
              initialQuantity: selectedQty > 0 ? selectedQty : 1,
              maxQuantity: stock,
              confirmLabel:
                  selectedQty > 0 ? 'Update transaction' : 'Add to transaction',
            );
            if (picked == null || !context.mounted) return;
            await viewModel.updateProductQuantity(context, result.id!, picked);
            if (!context.mounted) return;
            _showSelectionFeedback(
              context,
              selectedQty > 0
                  ? '$productName updated in this transaction · Qty $picked'
                  : '$productName added to this transaction · Qty $picked',
            );
            _continueAdding(context);
          },
        );
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildProductList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildProductList(context);

  Future<void> _recoverOutOfStockProduct(
    BuildContext context, {
    required Product product,
    required String productName,
  }) async {
    final productId = product.id;
    if (productId == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailsPage(docID: productId, product: product),
      ),
    );

    await viewModel.loadProducts();
    if (!context.mounted) return;
    showResults(context);

    final refreshed = viewModel.productById(productId);
    final refreshedStock = refreshed.quantity ?? 0;
    if (refreshedStock <= 0) {
      _showSelectionFeedback(
        context,
        '$productName is still out of stock. Add stock, save, then try again.',
        backgroundColor: Colors.orange,
      );
      return;
    }

    final selectedQty = viewModel.selectedProducts[productId] ?? 0;
    final picked = await _promptQuantity(
      context,
      title: productName,
      initialQuantity: selectedQty > 0 ? selectedQty : 1,
      maxQuantity: refreshedStock,
      confirmLabel:
          selectedQty > 0 ? 'Update transaction' : 'Add to transaction',
    );
    if (picked == null || !context.mounted) return;

    await viewModel.updateProductQuantity(context, productId, picked);
    if (!context.mounted) return;
    _showSelectionFeedback(
      context,
      selectedQty > 0
          ? '$productName updated in this transaction · Qty $picked'
          : '$productName added to this transaction · Qty $picked',
    );
    _continueAdding(context);
  }

  Future<int?> _promptQuantity(
    BuildContext context, {
    required String title,
    required int initialQuantity,
    required int maxQuantity,
    String confirmLabel = 'Add to transaction',
  }) {
    // PAS-UX batch-add: own the TextEditingController inside a dedicated
    // StatefulWidget so its lifecycle is tied to the dialog's element tree.
    // Previously the controller was created in this async function and
    // disposed in a `finally` block; when the picker stays open (batch-add)
    // and triggers an ancestor rebuild during dialog pop, Flutter would
    // attempt one more rebuild of the dialog and hit the already-disposed
    // controller — surfaced as "A TextEditingController was used after
    // being disposed" followed by a cascade of GlobalKey/RenderFlex errors.
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => _QuantityPromptDialog(
        title: title,
        initialQuantity: initialQuantity,
        maxQuantity: maxQuantity,
        confirmLabel: confirmLabel,
      ),
    );
  }

  /// PAS-UX batch-add: keep the search sheet open after a successful add so
  /// the merchant can build a multi-line basket in one flow. Clears the
  /// current query and returns to the suggestions list (showing the basket
  /// items first thanks to the existing sort in `_buildProductList`).
  void _continueAdding(BuildContext context) {
    if (!context.mounted) return;
    query = '';
    showSuggestions(context);
  }

  void _showSelectionFeedback(
    BuildContext context,
    String message, {
    Color backgroundColor = Colors.green,
  }) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(
            Navigator.of(context, rootNavigator: true).context,
          ) ??
          ScaffoldMessenger.maybeOf(context);
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
        ),
      );
    });
  }
}

/// Dialog body for `_promptQuantity`. Owns its own [TextEditingController]
/// so the controller's lifecycle is tied to this widget's State rather than
/// the calling async function — preventing "used after dispose" assertions
/// when ancestor rebuilds race the dialog pop in the batch-add flow.
class _QuantityPromptDialog extends StatefulWidget {
  const _QuantityPromptDialog({
    required this.title,
    required this.initialQuantity,
    required this.maxQuantity,
    required this.confirmLabel,
  });

  final String title;
  final int initialQuantity;
  final int maxQuantity;
  final String confirmLabel;

  @override
  State<_QuantityPromptDialog> createState() => _QuantityPromptDialogState();
}

class _QuantityPromptDialogState extends State<_QuantityPromptDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialQuantity <= 0
          ? '1'
          : widget.initialQuantity.toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null || parsed <= 0) {
      setState(() {
        _errorText = 'Enter a valid quantity.';
      });
      return;
    }
    // PAS-UX-XX: removed the hard "Only N available" block here. The
    // merchant is allowed to enter any positive integer; if it exceeds
    // stock, `updateProductQuantity` will prompt to top up inventory
    // before accepting the line.
    Navigator.pop(context, parsed);
  }

  @override
  Widget build(BuildContext context) {
    final parsed = int.tryParse(_controller.text.trim());
    final exceedsStock = parsed != null &&
        parsed > 0 &&
        widget.maxQuantity >= 0 &&
        parsed > widget.maxQuantity;

    return AlertDialog(
      title: Text('Add product to transaction · ${widget.title}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Available stock: ${widget.maxQuantity}'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Quantity',
              errorText: _errorText,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) {
              // Rebuild so the over-stock hint re-evaluates and the prior
              // errorText (if any) is cleared as the merchant edits.
              setState(() {
                _errorText = null;
              });
            },
            onSubmitted: (_) => _submit(),
          ),
          // PAS-UX-XX: surface an *inline non-blocking* heads-up when the
          // typed quantity exceeds on-hand stock. The merchant can still
          // submit — the top-up confirmation is handled centrally in
          // `TransactionViewModel.updateProductQuantity` so the recovery
          // flow stays in one place.
          if (exceedsStock)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Exceeds stock by '
                      '${parsed - widget.maxQuantity}. We\'ll ask to '
                      'top up your inventory before adding.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
