import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/contact/view_model/add_payment_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:provider/provider.dart';

class AddPaymentScreen extends StatelessWidget {
  final String customerName;
  final String customerId;
  final String? mobileNumber;

  const AddPaymentScreen({
    super.key,
    required this.customerName,
    required this.customerId,
    this.mobileNumber,
  });

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig

    return ChangeNotifierProvider(
      create: (_) => AddPaymentViewModel(
        customerName: customerName,
        customerId: customerId,
        mobileNumber: mobileNumber,
      ),
      child: Consumer<AddPaymentViewModel>(
        builder: (context, viewModel, child) {
          return GestureDetector(
            onTap: () {
              FocusScope.of(context)
                  .unfocus(); // Dismiss the keyboard when tapping outside
            },
            child: Scaffold(
              appBar: CustomAppBar(title: 'Add Payment for $customerName'),
              body: SafeArea(
                child: Padding(
                  padding: LayoutConstants.padding20Horizontal,
                  child: Form(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Column(
                          children: [
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
                                    SizedBox(
                                        height:
                                            SizeConfig.heightMultiplier * 2),
                                    Row(
                                      children: [
                                        Text(
                                          'Date of Payment: ',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize:
                                                SizeConfig.textMultiplier * 1.8,
                                          ),
                                        ),
                                        SizedBox(
                                            width:
                                                SizeConfig.imageSizeMultiplier *
                                                    2),
                                        ElevatedButton(
                                          onPressed: () async {
                                            DateTime? pickedDate =
                                                await showDatePicker(
                                              context: context,
                                              initialDate:
                                                  viewModel.selectedDate,
                                              firstDate: DateTime(2000),
                                              lastDate: DateTime.now(),
                                            );
                                            if (pickedDate != null) {
                                              viewModel.selectedDate =
                                                  pickedDate;
                                            }
                                          },
                                          child: Text(
                                            '${viewModel.selectedDate.toLocal()}'
                                                .split(' ')[0],
                                            style: TextStyle(
                                                fontSize:
                                                    SizeConfig.textMultiplier *
                                                        1.8),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(
                                        height:
                                            SizeConfig.heightMultiplier * 2),
                                    TextFormField(
                                      controller: viewModel.remarksController,
                                      maxLines: 3,
                                      decoration: InputDecoration(
                                        labelText: 'Remarks/Notes',
                                        border: const OutlineInputBorder(),
                                        labelStyle: TextStyle(
                                          fontSize:
                                              SizeConfig.textMultiplier * 2,
                                        ),
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical:
                                              SizeConfig.heightMultiplier * 1.5,
                                          horizontal:
                                              SizeConfig.imageSizeMultiplier *
                                                  3,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                        height:
                                            SizeConfig.heightMultiplier * 2),
                                  ],
                                ),
                              ),
                            ),
                            Column(
                              children: [
                                SizedBox(
                                    height: SizeConfig.heightMultiplier * 1),
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CustomButton(
                                      title: 'Add Payment',
                                      onTap: viewModel.isLoading
                                          ? () {}
                                          : () async {
                                              await viewModel
                                                  .addPaymentTransaction(
                                                      context);
                                            },
                                      color: Colors.green,
                                      icon: Icons.arrow_upward,
                                      fontSize: SizeConfig.textMultiplier * 2,
                                    ),
                                    if (viewModel.isLoading)
                                      const CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
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
