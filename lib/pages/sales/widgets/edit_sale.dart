import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/sales/sales_model.dart';
import 'package:pasella/pages/transactions/widgets/product_selection.dart';
import 'package:pasella/pages/sales/view_model/sale_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:provider/provider.dart';

class EditSale extends StatefulWidget {
  final Sale sale;

  const EditSale({super.key, required this.sale});

  @override
  _EditSaleState createState() => _EditSaleState();
}

class _EditSaleState extends State<EditSale> {
  late SalesViewModel transactionViewModel;

  @override
  void initState() {
    super.initState();
    transactionViewModel = SalesViewModel()..loadSaleDetails(widget.sale);
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return ChangeNotifierProvider(
      create: (_) => transactionViewModel,
      child: Consumer<SalesViewModel>(
        builder: (context, transactionViewModel, child) {
          return Scaffold(
            key: transactionViewModel.scaffoldKey,
            appBar: const CustomAppBar(title: 'Edit Sale'),
            body: SafeArea(
              child: Padding(
                padding: LayoutConstants.padding10Horizontal,
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
                                          setState(() {
                                            transactionViewModel
                                                    .salesSelectedDate =
                                                dateFormat.format(pickedDate);
                                          });
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
                              if (transactionViewModel
                                  .isTransactionLoading) ...[
                                SizedBox(
                                    height: SizeConfig.heightMultiplier * 10),
                                const CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.green),
                                )
                              ] else
                                ProductSelectionWidget(
                                    viewModel: transactionViewModel),
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
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    Text(
                      'Total Amount: ${CurrencyUtil.format(transactionViewModel.calculateTotalAmount())}',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomButton(
                          title: 'Update Sale',
                          onTap: transactionViewModel.isLoading
                              ? () {}
                              : () async {
                                  await transactionViewModel.updateSale(
                                      widget.sale,
                                      double.tryParse(transactionViewModel
                                              .amountController.text) ??
                                          0.0,
                                      transactionViewModel.selectedProducts,
                                      context);
                                },
                          color: Colors.green,
                          icon: Icons.save,
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
