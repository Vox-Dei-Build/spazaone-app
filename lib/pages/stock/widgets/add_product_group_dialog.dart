import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/stock/view_model/stock_view_model.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:provider/provider.dart';

class AddProductGroupDialog extends StatelessWidget {
  final StockViewModel viewModel;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  AddProductGroupDialog({
    Key? key,
    required this.viewModel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig for responsiveness

    return ChangeNotifierProvider.value(
      value: viewModel,
      child: Consumer<StockViewModel>(
        builder: (context, viewModel, child) {
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
                        controller: viewModel.newProductGroupController,
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
                                  await viewModel.onAddProductGroup(context);
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
