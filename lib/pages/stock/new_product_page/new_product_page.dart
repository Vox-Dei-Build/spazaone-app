import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/view_model/product_view_model.dart';
import 'package:pasella/pages/stock/widgets/product_form.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';

class NewProductPage extends StatefulWidget {
  final String? group;
  final Function(Product)? onProductAdded;

  NewProductPage({Key? key, this.group, this.onProductAdded}) : super(key: key);

  @override
  _NewProductPageState createState() => _NewProductPageState();
}

class _NewProductPageState extends State<NewProductPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Product _newProduct = Product();

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ProductViewModel(_newProduct),
      child: Consumer<ProductViewModel>(
        builder: (context, viewModel, child) {
          if (widget.group != null) {
            _newProduct.group = widget.group;
          }

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
                          Product? addedProduct = await viewModel.saveProduct(
                              context, _newProduct, null);
                          if (addedProduct != null &&
                              widget.onProductAdded != null) {
                            widget.onProductAdded!(
                                addedProduct); // Indicate product added
                          }
                          SchedulerBinding.instance.addPostFrameCallback((_) {
                            Navigator.pop(context);
                          });
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
              title: "New Product",
            ),
            body: SafeArea(
              child: Container(
                color: Colors.white,
                height: double.infinity,
                width: double.infinity,
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: ProductForm(
                          formKey: _formKey,
                          product: _newProduct,
                          initialGroup: widget.group,
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
