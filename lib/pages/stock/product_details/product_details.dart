import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/product_details/widgets/delete_product_confirmation_dialog.dart';
import 'package:pasella/pages/stock/widgets/product_form.dart';
import 'package:pasella/pages/stock/view_model/product_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';

class ProductDetailsPage extends StatefulWidget {
  final Product product;
  final String docID;

  const ProductDetailsPage(
      {Key? key, required this.product, required this.docID})
      : super(key: key);

  @override
  _ProductDetailsPage createState() => _ProductDetailsPage();
}

class _ProductDetailsPage extends State<ProductDetailsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProductViewModel(widget.product),
      child: Consumer<ProductViewModel>(
        builder: (context, viewModel, child) {
          return Scaffold(
            floatingActionButton: Padding(
              padding: const EdgeInsets.only(
                bottom: 35,
                right: 5,
              ),
              child: FloatingActionButton(
                backgroundColor:
                    viewModel.hasUnsavedChanges ? Colors.green : Colors.grey,
                onPressed: viewModel.isLoading || !viewModel.hasUnsavedChanges
                    ? null
                    : () async {
                        if (_formKey.currentState?.validate() ?? false) {
                          await viewModel.saveProduct(
                              context, widget.product, widget.docID);
                        }
                      },
                child: viewModel.isLoading
                    ? const CircularProgressIndicator(
                        color: Colors.white,
                      )
                    : const Icon(
                        Icons.done,
                        color: Colors.white,
                      ),
              ),
            ),
            appBar: CustomAppBar(
              title: "Edit Product",
              trailing: IconButton(
                icon: Icon(
                  Icons.delete,
                  color: Colors.black,
                  size: SizeConfig.imageSizeMultiplier * 7,
                ),
                onPressed: viewModel.isLoading
                    ? null
                    : () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return DeleteConfirmationDialog(
                              onConfirm: () async {
                                await viewModel.deleteProduct(
                                    context, widget.docID);
                              },
                            );
                          },
                        );
                      },
              ),
            ),
            body: SafeArea(
              child: SizedBox(
                height: double.infinity,
                width: double.infinity,
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: LayoutConstants.padding10Horizontal,
                        child: ProductForm(
                          formKey: _formKey,
                          product: widget.product,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
