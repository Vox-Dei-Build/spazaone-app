import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/contact/view_model/edit_transaction_view_model.dart';
import 'package:pasella/pages/contact/widgets/product_selection.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

class EditTransactionScreen extends StatefulWidget {
  final String customerName;
  final String customerId;
  final String transactionId;
  final Map<String, dynamic> transaction;
  final String? mobileNumber;

  const EditTransactionScreen(
      {super.key,
      required this.customerName,
      required this.customerId,
      required this.transactionId,
      required this.transaction,
      this.mobileNumber});

  @override
  _EditTransactionScreenState createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  late String customerName;
  late String customerId;
  late String transactionId;
  late Map<String, dynamic> transaction;
  late String transactionType;
  late String? mobileNumber;

  @override
  void initState() {
    super.initState();
    customerName = widget.customerName;
    customerId = widget.customerId;
    transactionId = widget.transactionId;
    transaction = widget.transaction;
    transactionType = transaction['type'];
    mobileNumber = widget.mobileNumber;
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // Initialize SizeConfig
    final bool isCredit = transactionType == "Credit";

    return ChangeNotifierProvider(
      create: (_) => EditTransactionViewModel(
        customerName: customerName,
        customerId: customerId,
        transaction: transaction,
        transactionId: transactionId,
        transactionType: transactionType,
        mobileNumber: mobileNumber,
      ),
      child: Consumer<EditTransactionViewModel>(
        builder: (context, viewModel, child) {
          return Scaffold(
            key: viewModel.scaffoldKey,
            appBar:
                CustomAppBar(title: 'Edit $transactionType for $customerName'),
            body: SafeArea(
              child: Padding(
                padding: LayoutConstants.padding10Horizontal,
                child: Form(
                  child: Column(
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
                              SizedBox(height: SizeConfig.heightMultiplier * 2),
                              if (isCredit) ...[
                                // Repayment Date only for credit transactions
                                Row(
                                  children: [
                                    Text(
                                      'Date of Credit: ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize:
                                            SizeConfig.textMultiplier * 1.8,
                                      ),
                                    ),
                                    SizedBox(
                                        width: SizeConfig.heightMultiplier * 1),
                                    ElevatedButton(
                                      onPressed: () async {
                                        DateTime? pickedDate =
                                            await showDatePicker(
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
                                                SizeConfig.textMultiplier *
                                                    1.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
                                      DateTime? pickedDate =
                                          await showDatePicker(
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
                              if (isCredit) ...[
                                SizedBox(
                                    height: SizeConfig.heightMultiplier * 2),
                                if (viewModel.isProductsLoading) ...[
                                  SizedBox(
                                      height: SizeConfig.heightMultiplier * 10),
                                  const CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.green),
                                  )
                                ] else
                                  ProductSelectionWidget<
                                          EditTransactionViewModel>(
                                      viewModel: viewModel),
                              ],
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
                      SizedBox(height: SizeConfig.heightMultiplier * 1),
                      if (isCredit) ...[
                        Text(
                          'Total Amount: ${CurrencyUtil.format(viewModel.calculateTotalAmount())}',
                          style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: SizeConfig.heightMultiplier * 1),
                      ],
                      Column(
                        children: [
                          SizedBox(height: SizeConfig.heightMultiplier * 1),
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomButton(
                                title: 'Update $transactionType',
                                onTap: viewModel.isLoading
                                    ? () {}
                                    : () async {
                                        await viewModel
                                            .updateTransaction(context);
                                      },
                                color: isCredit ? Colors.red : Colors.green,
                                icon: isCredit
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                fontSize: SizeConfig.textMultiplier * 2,
                              ),
                              if (viewModel.isLoading)
                                const CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                            ],
                          ),
                        ],
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
