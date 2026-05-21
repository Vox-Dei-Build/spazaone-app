import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/view_model/product_view_model.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:provider/provider.dart';

class ProductForm extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final Product product;
  final String? initialGroup;

  const ProductForm({
    Key? key,
    required this.formKey,
    required this.product,
    this.initialGroup,
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

  @override
  void initState() {
    super.initState();
    final viewModel = context.read<ProductViewModel>();
    _cost = double.tryParse(viewModel.costController.text);
    _sellingPrice = double.tryParse(viewModel.sellingPriceController.text);
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return Consumer<ProductViewModel>(
      builder: (context, viewModel, child) {
        String? selectedGroup = widget.product.group ?? widget.initialGroup;
        if (selectedGroup != null &&
            !viewModel.productGroups.contains(selectedGroup)) {
          selectedGroup = null;
        }

        return Form(
          key: widget.formKey,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: double.infinity,
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: SizeConfig.imageSizeMultiplier * 5,
                        vertical: SizeConfig.heightMultiplier * 6,
                      ),
                      margin: EdgeInsets.only(
                        top: SizeConfig.heightMultiplier * 10,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CustomTextField(
                              label: "Product Name*",
                              hintText: "Enter Product Name",
                              prefixIcon: Icons.edit,
                              controller: viewModel.nameController,
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
                            SizedBox(height: SizeConfig.heightMultiplier * 2),
                            Row(
                              children: [
                                Expanded(
                                  child: CustomTextField(
                                    label: "Cost*",
                                    hintText: "Cost",
                                    prefixIcon: Icons.money,
                                    controller: viewModel.costController,
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
                                      widget.product.cost = double.tryParse(
                                        value,
                                      );
                                      setState(() {
                                        _cost = double.tryParse(value);
                                      });
                                    },
                                    textInputType: TextInputType.number,
                                  ),
                                ),
                                SizedBox(
                                  width: SizeConfig.imageSizeMultiplier * 5,
                                ),
                                Expanded(
                                  child: CustomTextField(
                                    label: "Selling Price*",
                                    hintText: "Selling Price",
                                    prefixIcon: Icons.money,
                                    controller:
                                        viewModel.sellingPriceController,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter the selling price';
                                      }
                                      if (double.tryParse(value) == null) {
                                        return 'Please enter a valid number';
                                      }
                                      return null;
                                    },
                                    onChanged: (value) {
                                      viewModel.markUnsavedChanges();
                                      widget.product.sellingPrice =
                                          double.tryParse(value);
                                      setState(() {
                                        _sellingPrice = double.tryParse(value);
                                      });
                                    },
                                    textInputType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            // PAS-UX-05: non-blocking margin warning.
                            // Sub-cost pricing is sometimes intentional
                            // (loss leaders, clearance), so this is a
                            // callout rather than a validator error —
                            // the merchant can still save.
                            if (_cost != null &&
                                _sellingPrice != null &&
                                _sellingPrice! < _cost!) ...[
                              SizedBox(height: SizeConfig.heightMultiplier * 1),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: SizeConfig.imageSizeMultiplier * 4,
                                    color: Colors.orange[700],
                                  ),
                                  SizedBox(
                                    width: SizeConfig.imageSizeMultiplier * 1.5,
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Heads up: selling price is below '
                                      'cost. You will record a loss on '
                                      'each sale.',
                                      style: TextStyle(
                                        fontSize:
                                            SizeConfig.textMultiplier * 1.5,
                                        color: Colors.orange[800],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            SizedBox(height: SizeConfig.heightMultiplier * 2),
                            CustomTextField(
                              label: "Quantity*",
                              hintText: "Enter 0 if unsure",
                              prefixIcon: Icons.inventory,
                              controller: viewModel.quantityController,
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
                            SizedBox(height: SizeConfig.heightMultiplier * 2),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              secondary: const Icon(Icons.storefront_outlined),
                              title: const Text('List in WhatsApp Store'),
                              subtitle: const Text(
                                'On: customers can see and order it. Off: internal-only, still usable for stock and sales.',
                              ),
                              value: widget.product.whatsappListed,
                              onChanged: (value) {
                                viewModel.markUnsavedChanges();
                                setState(() {
                                  widget.product.whatsappListed = value;
                                });
                              },
                            ),
                            SizedBox(height: SizeConfig.heightMultiplier * 2),
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
                                initiallyExpanded: (viewModel
                                        .companyController.text.isNotEmpty) ||
                                    (viewModel
                                        .descriptionController.text.isNotEmpty),
                                title: const Text(
                                  'More details (optional)',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                                children: [
                                  CustomTextField(
                                    label: "Company",
                                    hintText: "Company",
                                    prefixIcon: Icons.business,
                                    controller: viewModel.companyController,
                                    onChanged: (value) {
                                      viewModel.markUnsavedChanges();
                                      widget.product.company = value;
                                    },
                                  ),
                                  SizedBox(
                                    height: SizeConfig.heightMultiplier * 2,
                                  ),
                                  CustomTextField(
                                    label: "Description",
                                    hintText: "Description",
                                    prefixIcon: Icons.description,
                                    controller: viewModel.descriptionController,
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
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: SizeConfig.heightMultiplier * 1.5,
                        ),
                        child: GestureDetector(
                          onTap: () => viewModel.handleImagePick(
                            context,
                            widget.product,
                          ),
                          child: SizedBox(
                            height: SizeConfig.heightMultiplier * 12,
                            width: SizeConfig.heightMultiplier * 12,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Container(
                                color: Colors.white,
                                child: Container(
                                  color: Colors.green.withOpacity(0.1),
                                  child: (viewModel.isLoading)
                                      ? const Center(
                                          child: CircularProgressIndicator(),
                                        )
                                      : (viewModel.imageUrl == null)
                                          ? Center(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    Icons.image,
                                                    size: SizeConfig
                                                            .imageSizeMultiplier *
                                                        6,
                                                    color: Colors.green
                                                        .withOpacity(0.5),
                                                  ),
                                                  Text(
                                                    'Tap to upload',
                                                    style: TextStyle(
                                                      fontSize: SizeConfig
                                                              .textMultiplier *
                                                          1.5,
                                                      color: Colors.green
                                                          .withOpacity(0.5),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )
                                          : CachedNetworkImage(
                                              fit: BoxFit.cover,
                                              imageUrl: viewModel.imageUrl!,
                                              errorWidget:
                                                  (context, url, error) => Icon(
                                                Icons.image,
                                                size: SizeConfig
                                                        .imageSizeMultiplier *
                                                    6,
                                                color: Colors.green
                                                    .withOpacity(0.5),
                                              ),
                                            ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
