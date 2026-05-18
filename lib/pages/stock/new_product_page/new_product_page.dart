import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/stock/view_model/product_view_model.dart';
import 'package:pasella/pages/stock/widgets/product_form.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/forms/confirm_dialog.dart';
import 'package:provider/provider.dart';

class NewProductPage extends StatefulWidget {
  final String? group;
  final Function(Product)? onProductAdded;

  const NewProductPage({Key? key, this.group, this.onProductAdded})
      : super(key: key);

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
            // PAS-UX-05: full migration to TransactionFormScaffold was
            // attempted but blocked by GlobalKey<FormState> uniqueness
            // — `ProductForm` already owns its own internal Form (it's
            // also reused by EditProductPage where that ownership is
            // load-bearing for inline validation), so handing the same
            // formKey to the scaffold's outer Form would cause a
            // duplicate-key crash. Rather than fork ProductForm to
            // strip its inner Form just for this entry point, we
            // replicate the two scaffold benefits the audit actually
            // called for — the unsaved-changes guard and the
            // disabled-on-loading CTA — locally. The scaffold can
            // adopt this page later if/when ProductForm is decoupled
            // from owning its Form.
            floatingActionButton: Padding(
              padding: const EdgeInsets.only(bottom: 35, right: 5),
              child: FloatingActionButton(
                backgroundColor:
                    viewModel.hasUnsavedChanges ? Colors.green : Colors.grey,
                onPressed: viewModel.isLoading || !viewModel.hasUnsavedChanges
                    ? null
                    : () async {
                        if (_formKey.currentState?.validate() ?? false) {
                          Product? addedProduct = await viewModel.saveProduct(
                            context,
                            _newProduct,
                            null,
                            showSuccessSnackbar: false,
                          );
                          if (addedProduct == null) return;
                          if (widget.onProductAdded != null) {
                            widget.onProductAdded!(
                              addedProduct,
                            ); // Indicate product added
                          }
                          SchedulerBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted) return;
                            final rootMessenger = ScaffoldMessenger.maybeOf(
                                  Navigator.of(
                                    context,
                                    rootNavigator: true,
                                  ).context,
                                ) ??
                                ScaffoldMessenger.maybeOf(context);
                            rootMessenger?.hideCurrentSnackBar();
                            rootMessenger?.showSnackBar(
                              const SnackBar(
                                content: Text('Product added successfully.'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            Navigator.pop(context);
                          });
                        }
                      },
                child: viewModel.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Icon(Icons.done, color: Colors.white),
              ),
            ),
            appBar: const CustomAppBar(title: "New Product"),
            body: PopScope(
              // PAS-UX-05: unsaved-changes guard. Previously a swipe-
              // back on this page silently discarded everything the
              // merchant had typed. We now intercept and confirm.
              canPop: !viewModel.hasUnsavedChanges,
              onPopInvokedWithResult: (didPop, _) async {
                if (didPop) return;
                final shouldDiscard = await ConfirmDialog.showDestructive(
                  context,
                  title: 'Discard new product?',
                  message: 'You have unsaved changes. Leaving now will discard '
                      'them.',
                  confirmLabel: 'Discard',
                  cancelLabel: 'Keep editing',
                );
                if (shouldDiscard && context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: SafeArea(
                child: Container(
                  color: Colors.white,
                  height: double.infinity,
                  width: double.infinity,
                  child: Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: LayoutConstants.padding10Horizontal,
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
            ),
          );
        },
      ),
    );
  }
}
