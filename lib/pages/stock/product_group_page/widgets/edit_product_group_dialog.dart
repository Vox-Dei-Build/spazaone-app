import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:provider/provider.dart';

class EditProductGroupDialog extends StatelessWidget {
  final StockViewModel viewModel;
  final String groupName;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();

  EditProductGroupDialog({
    Key? key,
    required this.viewModel,
    required this.groupName,
  }) : super(key: key) {
    _controller.text = groupName; // Pre-fill the current group name
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return ChangeNotifierProvider.value(
      value: viewModel,
      child: Consumer<StockViewModel>(
        builder: (context, viewModel, child) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                  SizeConfig.imageSizeMultiplier *
                      2), // Responsive border radius
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: EdgeInsets.all(
                    SizeConfig.imageSizeMultiplier * 5), // Responsive padding
                constraints: BoxConstraints(
                  maxHeight: SizeConfig.screenHeight * 0.8,
                  maxWidth: SizeConfig.screenWidth * 0.8,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Edit Product Group",
                        style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 2,
                        ),
                      ),
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
                      if (viewModel.errorMessage != null)
                        Text(
                          viewModel.errorMessage!,
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
                        controller: _controller,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'This field is required';
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
                      CustomButton(
                        onTap: viewModel.isLoading
                            ? () => null
                            : () async {
                                if (_formKey.currentState?.validate() ??
                                    false) {
                                  await viewModel.editProductGroup(
                                    context,
                                    groupName,
                                    _controller.text,
                                  );
                                }
                              },
                        margin: EdgeInsets.symmetric(
                          horizontal: SizeConfig.imageSizeMultiplier * 2.5,
                          vertical: SizeConfig.heightMultiplier * 1,
                        ),
                        title: viewModel.isLoading ? 'Loading...' : 'Done',
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
