import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';

/// PAS-CRASH-_dependents: previously this dialog re-published the
/// ancestor-owned `StockViewModel` via `ChangeNotifierProvider.value` so a
/// local `Consumer<StockViewModel>` could rebuild on loading/error state.
/// That created a short-lived InheritedElement whose teardown raced with
/// `StockViewModel.editProductGroup` (which pops the dialog and then
/// continues to mutate + notifyListeners + pushReplacement in the same
/// frame), tripping the framework assertion
/// `_dependents.isEmpty: is not true` at framework.dart:6179.
///
/// The fix: render against the passed-in notifier directly via
/// `AnimatedBuilder`, with no InheritedWidget in the dialog subtree, and
/// convert to a StatefulWidget so the TextEditingController is disposed
/// properly.
class EditProductGroupDialog extends StatefulWidget {
  const EditProductGroupDialog({
    Key? key,
    required this.viewModel,
    required this.groupName,
  }) : super(key: key);

  final StockViewModel viewModel;
  final String groupName;

  @override
  State<EditProductGroupDialog> createState() => _EditProductGroupDialogState();
}

class _EditProductGroupDialogState extends State<EditProductGroupDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.groupName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return AnimatedBuilder(
      animation: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(22),
              constraints: BoxConstraints(
                maxHeight: SizeConfig.screenHeight * 0.8,
                maxWidth: SizeConfig.screenWidth * 0.8,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Edit Product Group",
                      style: TextStyle(
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (vm.errorMessage != null)
                      Text(
                        vm.errorMessage!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 16,
                        ),
                      ),
                    CustomTextField(
                      hintText: 'Product Group Name',
                      prefixIcon: Icons.category_outlined,
                      label: 'Product Group Name*',
                      textInputType: TextInputType.text,
                      maxLength: 20,
                      controller: _controller,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'This field is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomButton(
                      onTap: vm.isLoading
                          ? () {}
                          : () async {
                              if (_formKey.currentState?.validate() ?? false) {
                                await vm.editProductGroup(
                                  context,
                                  widget.groupName,
                                  _controller.text,
                                );
                              }
                            },
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
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
