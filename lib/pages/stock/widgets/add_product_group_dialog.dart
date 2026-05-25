import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';

/// PAS-CRASH-_dependents: previously this dialog re-published the
/// ancestor-owned `StockViewModel` via `ChangeNotifierProvider.value` so a
/// local `Consumer<StockViewModel>` could rebuild on loading/error state.
/// `StockViewModel.onAddProductGroup` schedules `Navigator.pop` in a
/// post-frame callback and then continues mutating state +
/// notifyListeners(), which races with the InheritedElement teardown and
/// surfaces the framework assertion `_dependents.isEmpty: is not true` at
/// framework.dart:6179.
///
/// The fix: render directly against the passed-in notifier with an
/// `AnimatedBuilder`, so the dialog subtree contains no InheritedWidget
/// for the framework to deactivate while dependents are still live.
class AddProductGroupDialog extends StatefulWidget {
  const AddProductGroupDialog({
    Key? key,
    required this.viewModel,
  }) : super(key: key);

  final StockViewModel viewModel;

  @override
  State<AddProductGroupDialog> createState() => _AddProductGroupDialogState();
}

class _AddProductGroupDialogState extends State<AddProductGroupDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 4),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Create Product Group",
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 2,
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    if (vm.errorMessage != null)
                      Text(
                        vm.errorMessage!,
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: SizeConfig.textMultiplier * 1.8,
                        ),
                      ),
                    CustomTextField(
                      hintText: 'Product Group Name',
                      prefixIcon: Icons.category_outlined,
                      label: 'Product Group Name*',
                      textInputType: TextInputType.text,
                      maxLength: 20,
                      controller: vm.newProductGroupController,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'This field is required';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    CustomButton(
                      onTap: vm.isLoading
                          ? () {}
                          : () async {
                              if (_formKey.currentState?.validate() ??
                                  false) {
                                await vm.onAddProductGroup(context);
                              }
                            },
                      margin: EdgeInsets.symmetric(
                        horizontal: SizeConfig.imageSizeMultiplier * 2.5,
                        vertical: SizeConfig.heightMultiplier * 1,
                      ),
                      title: vm.isLoading ? 'Loading...' : 'Done',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
