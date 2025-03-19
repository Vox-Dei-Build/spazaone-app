import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/contact/widgets/product_selection.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

class AddSale extends StatelessWidget {
  final SalesViewModel salesViewModel;

  const AddSale({super.key, required this.salesViewModel});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return ChangeNotifierProvider(
      create: (_) => SalesViewModel(),
      child: Consumer<SalesViewModel>(
        builder: (context, transactionViewModel, child) {
          return Scaffold(
            key: transactionViewModel.scaffoldKey,
            appBar: const CustomAppBar(title: 'Add Sale'),
            body: SafeArea(
              child: Padding(
                padding: LayoutConstants.padding20Horizontal,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Form(
                          key: transactionViewModel.formKey,
                          child: Column(
                            children: [
                              CustomTextField(
                                label: 'Amount',
                                hintText: 'Enter Amount',
                                prefixIcon: Icons.money,
                                controller:
                                    transactionViewModel.amountController,
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
                                    'Date of Sale: ',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: SizeConfig.textMultiplier * 2,
                                    ),
                                  ),
                                  SizedBox(
                                      width:
                                          SizeConfig.imageSizeMultiplier * 2),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () async {
                                        DateFormat dateFormat =
                                            DateFormat("dd-MM-yyyy HH:mm");
                                        DateTime? pickedDate =
                                            await showDatePicker(
                                          context: context,
                                          initialDate: dateFormat.parse(
                                              transactionViewModel
                                                  .salesSelectedDate),
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime.now(),
                                        );
                                        if (pickedDate != null) {
                                          transactionViewModel
                                                  .salesSelectedDate =
                                              dateFormat.format(pickedDate);
                                        }
                                      },
                                      child: Text(
                                        transactionViewModel.salesSelectedDate
                                            .split(' ')[0],
                                        style: TextStyle(
                                            fontSize:
                                                SizeConfig.textMultiplier *
                                                    1.8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: SizeConfig.heightMultiplier * 2),
                              TextFormField(
                                controller:
                                    transactionViewModel.remarksController,
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
                              SizedBox(height: SizeConfig.heightMultiplier * 2),
                              ProductSelectionWidget(
                                  viewModel: transactionViewModel),
                              SizedBox(height: SizeConfig.heightMultiplier * 2),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    Text(
                      'Total Amount: ${CurrencyUtil.format(transactionViewModel.calculateTotalAmount())}',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 2.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomButton(
                          title: 'Add Sale',
                          onTap: transactionViewModel.isLoading
                              ? () {}
                              : () async {
                                  await transactionViewModel
                                      .addSalesTransaction(context);
                                  salesViewModel.updateSelectedPeriod('All');
                                },
                          color: Colors.green,
                          icon: Icons.money,
                        ),
                        if (transactionViewModel.isLoading)
                          const CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                      ],
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
