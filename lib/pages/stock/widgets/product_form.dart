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
  _ProductFormState createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
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
                          top: SizeConfig.heightMultiplier * 10),
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
                                      widget.product.cost =
                                          double.tryParse(value);
                                    },
                                    textInputType: TextInputType.number,
                                  ),
                                ),
                                SizedBox(
                                    width: SizeConfig.imageSizeMultiplier * 5),
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
                                    },
                                    textInputType: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: SizeConfig.heightMultiplier * 2),
                            CustomTextField(
                              label: "Quantity*",
                              hintText: "Quantity",
                              prefixIcon: Icons.inventory,
                              controller: viewModel.quantityController,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter the quantity';
                                }
                                if (int.tryParse(value) == null) {
                                  return 'Please enter a valid number';
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
                            SizedBox(height: SizeConfig.heightMultiplier * 2),
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
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: EdgeInsets.only(
                            top: SizeConfig.heightMultiplier * 1.5),
                        child: GestureDetector(
                          onTap: () => viewModel.handleImagePick(
                              context, widget.product),
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
