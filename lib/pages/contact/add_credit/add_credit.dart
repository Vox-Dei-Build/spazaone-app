import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/contact/view_model/add_credit_view_model.dart';
import 'package:pasella/pages/contact/widgets/product_selection.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

class AddCreditScreen extends StatelessWidget {
  final String customerName;
  final String customerId;
  final String? mobileNumber;

  const AddCreditScreen({
    super.key,
    required this.customerName,
    required this.customerId,
    this.mobileNumber,
  });

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return ChangeNotifierProvider(
      create: (_) => AddCreditViewModel(
        customerName: customerName,
        customerId: customerId,
        mobileNumber: mobileNumber,
      ),
      child: Consumer<AddCreditViewModel>(
        builder: (context, viewModel, child) {
          return Scaffold(
            key: viewModel.scaffoldKey,
            appBar: CustomAppBar(title: 'Add Credit for $customerName'),
            body: SafeArea(
              child: Padding(
                padding: LayoutConstants.padding10Horizontal,
                child: Form(
                  key: viewModel.formKey,
                  child: Column(children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            CustomTextField(
                              label: 'Amount',
                              hintText: 'Enter Amount',
                              prefixIcon: Icons.money,
                              controller: viewModel.amountController,
                              textInputType: TextInputType.number,
                              validator: (value) {
                                if (value == null ||
                                    value.isEmpty ||
                                    double.tryParse(value) == null) {
                                  return 'Please enter a valid amount';
                                }
                                return null;
                              },
                            ),
                            Row(
                              children: [
                                Text(
                                  'Date of Credit: ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: SizeConfig.textMultiplier * 1.8,
                                  ),
                                ),
                                SizedBox(
                                    width: SizeConfig.heightMultiplier * 1),
                                ElevatedButton(
                                  onPressed: () async {
                                    DateTime? pickedDate = await showDatePicker(
                                      context: context,
                                      initialDate: viewModel.selectedDate,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime.now(),
                                    );
                                    if (pickedDate != null) {
                                      viewModel.selectedDate = pickedDate;
                                    }
                                  },
                                  child: Text(
                                    '${viewModel.selectedDate.toLocal()}'
                                        .split(' ')[0],
                                    style: TextStyle(
                                        fontSize:
                                            SizeConfig.textMultiplier * 1.8),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: SizeConfig.heightMultiplier * 1),
                            Row(
                              children: [
                                Text(
                                  'Repayment Date: ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: SizeConfig.textMultiplier * 1.8,
                                  ),
                                ),
                                SizedBox(
                                    width: SizeConfig.heightMultiplier * 1),
                                ElevatedButton(
                                  onPressed: () async {
                                    DateTime? pickedDate = await showDatePicker(
                                      context: context,
                                      initialDate: viewModel.repaymentDate,
                                      firstDate: viewModel.selectedDate,
                                      lastDate: DateTime(2100),
                                    );
                                    if (pickedDate != null) {
                                      viewModel.repaymentDate = pickedDate;
                                    }
                                  },
                                  child: Text(
                                    '${viewModel.repaymentDate.toLocal()}'
                                        .split(' ')[0],
                                    style: TextStyle(
                                        fontSize:
                                            SizeConfig.textMultiplier * 1.8),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: SizeConfig.heightMultiplier * 2),
                            ProductSelectionWidget<AddCreditViewModel>(
                                viewModel: viewModel),
                            SizedBox(height: SizeConfig.heightMultiplier * 2),
                            TextFormField(
                              controller: viewModel.remarksController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: 'Remarks/Notes',
                                border: const OutlineInputBorder(),
                                labelStyle: TextStyle(
                                  fontSize: SizeConfig.textMultiplier * 2,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: SizeConfig.heightMultiplier * 1.5,
                                  horizontal:
                                      SizeConfig.imageSizeMultiplier * 3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      'Total Amount: ${CurrencyUtil.format(viewModel.calculateTotalAmount())}',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomButton(
                          title: 'Add Credit',
                          onTap: viewModel.isLoading
                              ? () {}
                              : () async {
                                  await viewModel.addCreditTransaction(context);
                                },
                          color: Colors.red,
                          icon: Icons.arrow_downward,
                          fontSize: SizeConfig.textMultiplier * 2,
                        ),
                        if (viewModel.isLoading)
                          const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                      ],
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
