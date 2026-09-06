import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/view_model/product_view_model.dart';
import 'package:pasella/pages/stock/widgets/whatsapp_listing_preview.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:provider/provider.dart';

class ProductForm extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final Product product;
  final String? initialGroup;
  final Future<String?> Function()? loadShopName;

  const ProductForm({
    Key? key,
    required this.formKey,
    required this.product,
    this.initialGroup,
    this.loadShopName,
  }) : super(key: key);

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  /// PAS-UX-05: cached parse results for the cost / selling-price soft
  /// warning. We don't validate this as an error (a merchant may
  /// legitimately run a loss-leader promo) but we surface a margin
  /// callout so accidental sub-cost pricing isn't silent.
  double? _cost;
  double? _sellingPrice;

  /// PAS-UX-XX: shop name is fetched once for the WhatsApp listing preview
  /// "Reply to buy from {shop}" line. Null while loading and falls back to
  /// a generic placeholder inside the preview widget.
  String? _shopName;

  @override
  void initState() {
    super.initState();
    final viewModel = context.read<ProductViewModel>();
    _cost = double.tryParse(viewModel.costController.text);
    _sellingPrice = double.tryParse(viewModel.sellingPriceController.text);
    _loadShopName();
  }

  Future<void> _loadShopName() async {
    try {
      final name = await (widget.loadShopName?.call() ?? fetchShopName());
      if (!mounted) return;
      setState(() {
        _shopName = name;
      });
    } catch (_) {
      // Non-fatal: preview falls back to a generic label.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProductViewModel>(
      builder: (context, viewModel, child) {
        final selectedGroup = widget.product.group ?? widget.initialGroup;
        // Preserve a custom group while the asynchronous group list loads.
        // Clearing an unknown value during build silently removed the group
        // from existing products before the merchant touched the field.
        final availableGroups = <String>{
          ...viewModel.productGroups,
          if (selectedGroup != null) selectedGroup,
        }.toList()
          ..sort();

        return Form(
          key: widget.formKey,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              32 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ProductImagePicker(
                  viewModel: viewModel,
                  product: widget.product,
                ),
                const SizedBox(height: 24),
                CustomTextField(
                  label: "Product name*",
                  hintText: "Enter product name",
                  prefixIcon: Icons.edit,
                  controller: viewModel.nameController,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a product name';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    viewModel.markUnsavedChanges();
                    widget.product.name = value;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  label: "Cost*",
                  hintText: "Cost",
                  prefixIcon: Icons.money,
                  controller: viewModel.costController,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the cost';
                    }
                    if (double.tryParse(value) == null) {
                      return 'Please enter a valid number';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    viewModel.markUnsavedChanges();
                    widget.product.cost = double.tryParse(value);
                    setState(() {
                      _cost = double.tryParse(value);
                    });
                  },
                  textInputType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 12),
                CustomTextField(
                  label: "Selling price*",
                  hintText: "Selling price",
                  prefixIcon: Icons.money,
                  controller: viewModel.sellingPriceController,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the selling price';
                    }
                    if (double.tryParse(value) == null) {
                      return 'Please enter a valid number';
                    }
                    if (widget.product.whatsappListed &&
                        (double.tryParse(value) ?? 0) <= 0) {
                      return 'Enter a price above zero for WhatsApp listings';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    viewModel.markUnsavedChanges();
                    widget.product.sellingPrice = double.tryParse(
                      value,
                    );
                    setState(() {
                      _sellingPrice = double.tryParse(value);
                    });
                  },
                  textInputType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                // PAS-UX-XX: cost field clarity. Merchant
                // feedback (Gugu) flagged confusion over
                // whether "Cost" is visible to customers.
                // Kept as a single muted line under the row
                // so the answer is on-screen without adding
                // visual weight.
                const Padding(
                  padding: EdgeInsets.only(
                    left: 8,
                    top: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: SpazaColors.muted,
                      ),
                      SizedBox(
                        width: 4,
                      ),
                      Expanded(
                        child: Text(
                          'Cost is internal. Customers only see the selling price.',
                          style: TextStyle(
                            fontSize: 13,
                            color: SpazaColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // PAS-UX-05: non-blocking margin warning.
                // Sub-cost pricing is sometimes intentional
                // (loss leaders, clearance), so this is a
                // callout rather than a validator error —
                // the merchant can still save.
                if (_cost != null &&
                    _sellingPrice != null &&
                    _sellingPrice! < _cost!) ...[
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Colors.orange[700],
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      Expanded(
                        child: Text(
                          'Heads up: selling price is below '
                          'cost. You will record a loss on '
                          'each sale.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                CustomTextField(
                  label: "Quantity*",
                  hintText: "Enter 0 if unsure",
                  prefixIcon: Icons.inventory,
                  controller: viewModel.quantityController,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the quantity';
                    }
                    final parsed = int.tryParse(value);
                    if (parsed == null) {
                      return 'Please enter a valid number';
                    }
                    // PAS-UX-05: explicit non-negative
                    // guard. Without it the form happily
                    // accepts -3 and the stock list shows
                    // a negative count, which then breaks
                    // the sale-deduct path.
                    if (parsed < 0) {
                      return 'Quantity cannot be negative';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    viewModel.markUnsavedChanges();
                    widget.product.quantity = int.tryParse(value);
                  },
                  textInputType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.storefront_outlined),
                  title: const Text('List in WhatsApp store'),
                  subtitle: const Text(
                    'On requests a background catalogue sync. A name, positive selling price, product image and shop link are required. Turning this off removes the WhatsApp listing but keeps the product in stock and sales.',
                  ),
                  value: widget.product.whatsappListed,
                  onChanged: (value) {
                    viewModel.markUnsavedChanges();
                    setState(() {
                      widget.product.whatsappListed = value;
                    });
                  },
                ),
                // PAS-UX-XX: live preview of the listing as it
                // appears to customers in the WhatsApp Store.
                // Only rendered when the toggle is ON — the
                // toggle copy already explains the OFF state
                // ("internal-only") so the preview would just
                // add noise there. Bound to the live form
                // values so it updates as the merchant types.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  ),
                  child: widget.product.whatsappListed
                      ? Padding(
                          key: const ValueKey('wa-preview-on'),
                          padding: const EdgeInsets.only(
                            top: 4,
                          ),
                          child: WhatsappListingPreview(
                            name: viewModel.nameController.text,
                            sellingPrice: double.tryParse(
                              viewModel.sellingPriceController.text,
                            ),
                            company: viewModel.companyController.text,
                            description: viewModel.descriptionController.text,
                            imageUrl: viewModel.imageUrl,
                            localImage: viewModel.pendingImage,
                            shopName: _shopName,
                          ),
                        )
                      : const SizedBox(
                          key: ValueKey('wa-preview-off'),
                          width: double.infinity,
                        ),
                ),
                // PAS-WA-03: inline cue for the hard validation
                // gate in ProductViewModel.saveProduct. Surfaces
                // the requirement at the moment the merchant
                // flips the toggle, so the save-time block is
                // never a surprise. Hidden as soon as an image
                // is attached or the toggle is turned back off.
                if (widget.product.whatsappListed && !viewModel.hasImage) ...[
                  const SizedBox(height: 8),
                  Row(
                    key: const ValueKey('wa-image-required-cue'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 20,
                        color: Colors.orange[700],
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      Expanded(
                        child: Text(
                          'Add a product image before listing '
                          'this for WhatsApp orders.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                // Progressive disclosure: keep optional fields out
                // of the merchant's way during initial create. Auto
                // expands when an existing product already has data
                // in either field (edit surface) so values stay
                // visible.
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    initiallyExpanded: selectedGroup != null ||
                        (viewModel.companyController.text.isNotEmpty) ||
                        (viewModel.descriptionController.text.isNotEmpty),
                    title: const Text(
                      'More details (optional)',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    children: [
                      DropdownButtonFormField<String>(
                        value: selectedGroup,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Product group (optional)',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: availableGroups
                            .map(
                              (group) => DropdownMenuItem<String>(
                                value: group,
                                child: Text(group),
                              ),
                            )
                            .toList(),
                        onChanged: (group) {
                          viewModel.markUnsavedChanges();
                          setState(() {
                            widget.product.group = group;
                          });
                        },
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      CustomTextField(
                        label: "Company",
                        hintText: "Company",
                        prefixIcon: Icons.business,
                        controller: viewModel.companyController,
                        textInputAction: TextInputAction.next,
                        onChanged: (value) {
                          viewModel.markUnsavedChanges();
                          widget.product.company = value;
                        },
                      ),
                      const SizedBox(
                        height: 16,
                      ),
                      CustomTextField(
                        label: "Description",
                        hintText: "Description",
                        prefixIcon: Icons.description,
                        controller: viewModel.descriptionController,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) =>
                            FocusScope.of(context).unfocus(),
                        onChanged: (value) {
                          viewModel.markUnsavedChanges();
                          widget.product.description = value;
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProductImagePicker extends StatelessWidget {
  const _ProductImagePicker({required this.viewModel, required this.product});

  final ProductViewModel viewModel;
  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: viewModel.hasImage ? 'Change product photo' : 'Add product photo',
      child: InkWell(
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
        onTap: viewModel.isLoading
            ? null
            : () => viewModel.handleImagePick(context, product),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(SpazaRadius.surface),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(SpazaRadius.control),
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: viewModel.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : viewModel.pendingImage != null
                          ? Image.file(viewModel.pendingImage!,
                              fit: BoxFit.cover)
                          : (viewModel.imageUrl?.isNotEmpty ?? false)
                              ? CachedNetworkImage(
                                  imageUrl: viewModel.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      const _ProductImagePlaceholder(),
                                )
                              : const _ProductImagePlaceholder(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      viewModel.hasImage
                          ? 'Product photo'
                          : 'Add a product photo',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      viewModel.hasImage
                          ? 'Tap to replace it. The WhatsApp preview updates immediately.'
                          : 'Required only when you list this product on WhatsApp.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductImagePlaceholder extends StatelessWidget {
  const _ProductImagePlaceholder();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.add_photo_alternate_outlined)),
      );
}
