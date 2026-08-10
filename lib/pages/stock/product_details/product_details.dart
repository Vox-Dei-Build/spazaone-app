import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/promote/utils/run_promotion_launcher.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/stock/product_details/widgets/delete_product_confirmation_dialog.dart';
import 'package:pasella/pages/stock/widgets/product_form.dart';
import 'package:pasella/pages/stock/view_model/product_view_model.dart';
import 'package:pasella/pages/stock/dropship/dropship_listing_page.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/forms/confirm_dialog.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:provider/provider.dart';

@visibleForTesting
bool productDetailsCanPop({
  required bool hasUnsavedChanges,
  required bool exitAuthorized,
}) =>
    exitAuthorized || !hasUnsavedChanges;

class ProductDetailsPage extends StatefulWidget {
  final Product product;
  final String docID;

  const ProductDetailsPage({
    Key? key,
    required this.product,
    required this.docID,
  }) : super(key: key);

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPage();
}

class _ProductDetailsPage extends State<ProductDetailsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _exitAuthorized = false;

  Future<void> _deleteProduct(ProductViewModel viewModel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const DeleteConfirmationDialog(),
    );
    if (confirmed != true || !mounted) return;

    final deleted = await viewModel.deleteProduct(widget.docID);
    if (!mounted) return;

    if (!deleted) {
      showErrorSnackBar(context, 'Failed to delete product!');
      return;
    }

    // Rebuild PopScope with an explicit successful-delete exit before
    // navigating. A merchant may delete after editing a field, in which case
    // the ordinary unsaved-changes guard must not trap an already-deleted
    // product on screen or show the discard prompt.
    setState(() => _exitAuthorized = true);
    showSnackbar(context, 'Deleted Successfully!', Colors.green);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _promote(
    BuildContext context,
    ProductViewModel productViewModel,
  ) {
    return RunPromotionLauncher.launch(
      context,
      viewModel: context.read<PromotionsViewModel>(),
      initialProduct: LinkedProductRef(
        id: widget.docID,
        name: widget.product.name ?? 'Product',
        sellingPrice: widget.product.sellingPrice,
        imageUrl: productViewModel.imageUrl,
        whatsappListed: widget.product.whatsappListed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.product.isDropshipListing) {
      return DropshipListingPage(
        product: widget.product,
        docID: widget.docID,
      );
    }
    return ChangeNotifierProvider(
      create: (_) => ProductViewModel(widget.product),
      child: Consumer<ProductViewModel>(
        builder: (context, viewModel, child) {
          return Scaffold(
            bottomNavigationBar: widget.product.whatsappListed
                ? SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: ElevatedButton.icon(
                        onPressed:
                            viewModel.isLoading || viewModel.hasUnsavedChanges
                                ? null
                                : () => _promote(context, viewModel),
                        icon: const Icon(Icons.campaign_outlined),
                        label: Text(
                          viewModel.hasUnsavedChanges
                              ? 'Save before promoting'
                              : 'Promote on WhatsApp',
                        ),
                      ),
                    ),
                  )
                : null,
            floatingActionButton: Padding(
              padding: const EdgeInsets.only(bottom: 35, right: 5),
              child: FloatingActionButton.extended(
                backgroundColor:
                    viewModel.hasUnsavedChanges ? Colors.green : Colors.grey,
                onPressed: viewModel.isLoading || !viewModel.hasUnsavedChanges
                    ? null
                    : () async {
                        if (_formKey.currentState?.validate() ?? false) {
                          await viewModel.saveProduct(
                            context,
                            widget.product,
                            widget.docID,
                          );
                        }
                      },
                icon: viewModel.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.done, color: Colors.white),
                label: Text(
                  viewModel.isLoading ? 'Saving…' : 'Save changes',
                  style: const TextStyle(color: Colors.white),
                ),
                tooltip: 'Save product changes',
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
                    : () => _deleteProduct(viewModel),
              ),
            ),
            body: PopScope(
              canPop: productDetailsCanPop(
                hasUnsavedChanges: viewModel.hasUnsavedChanges,
                exitAuthorized: _exitAuthorized,
              ),
              onPopInvokedWithResult: (didPop, _) async {
                if (didPop) return;
                final discard = await ConfirmDialog.showDestructive(
                  context,
                  title: 'Discard product changes?',
                  message: 'Leaving now will discard your unsaved changes.',
                  confirmLabel: 'Discard',
                  cancelLabel: 'Keep editing',
                );
                if (discard && context.mounted) {
                  setState(() => _exitAuthorized = true);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) Navigator.of(context).pop();
                  });
                }
              },
              child: SafeArea(
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
            ),
          );
        },
      ),
    );
  }
}
