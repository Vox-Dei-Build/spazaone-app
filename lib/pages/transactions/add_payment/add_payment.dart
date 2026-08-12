import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/transactions/view_model/add_payment_view_model.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/date_row.dart';
import 'package:pasella/shared/widgets/forms/transaction_form_scaffold.dart';
import 'package:provider/provider.dart';
import 'package:pasella/utils/feature_flags.dart';

/// Add Payment screen — migrated onto [TransactionFormScaffold]. The
/// pre-migration version shipped with a `Form` and no `formKey`, which
/// meant the inline validator never blocked submission. The scaffold
/// owns the formKey + validate() gate, closing that hole.
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

  Future<void> _preparePaymentLink(
    BuildContext context,
    AddPaymentViewModel viewModel,
  ) async {
    final emailController = TextEditingController();
    var channel = 'eft';
    final selection = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Send payment link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Paystack will collect the amount entered on this screen. '
                'The customer balance changes only after verified payment.',
              ),
              const SizedBox(height: LayoutConstants.spaceMd),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Customer email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: LayoutConstants.spaceMd),
              DropdownButtonFormField<String>(
                value: channel,
                decoration: const InputDecoration(
                  labelText: 'Payment method',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'eft', child: Text('Instant EFT')),
                  DropdownMenuItem(
                    value: 'capitec_pay',
                    child: Text('Capitec Pay'),
                  ),
                  DropdownMenuItem(value: 'qr', child: Text('QR payment')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                ],
                onChanged: (value) => setState(() => channel = value ?? 'eft'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, {
                'email': emailController.text.trim(),
                'channel': channel,
              }),
              child: const Text('Create link'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    if (selection == null || !context.mounted) return;
    await viewModel.createAndSharePaymentLink(
      context,
      email: selection['email'] ?? '',
      channel: selection['channel'] ?? 'eft',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AddPaymentViewModel(
        customerName: customerName,
        customerId: customerId,
        mobileNumber: mobileNumber,
      ),
      child: Consumer<AddPaymentViewModel>(
        builder: (context, viewModel, child) {
          return TransactionFormScaffold(
            title: 'Add Payment for $customerName',
            scaffoldKey: viewModel.scaffoldKey,
            formKey: viewModel.formKey,
            isLoading: viewModel.isLoading,
            isDirty: viewModel.isDirty,
            primaryActionLabel: 'Add Payment',
            primaryActionIcon: Icons.arrow_upward,
            primaryActionColor: Colors.green,
            onPrimaryAction: () => viewModel.addPaymentTransaction(context),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomTextField(
                  label: 'Amount',
                  hintText: 'Enter Amount',
                  prefixIcon: Icons.money,
                  controller: viewModel.amountController,
                  textInputType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.isEmpty ||
                        double.tryParse(value) == null) {
                      return 'Please enter a valid amount';
                    }
                    return null;
                  },
                ),
                DateRow(
                  label: 'Date of Payment',
                  value: viewModel.selectedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  onPick: viewModel.setSelectedDate,
                ),
                const SizedBox(height: LayoutConstants.spaceLg),
                TextFormField(
                  controller: viewModel.remarksController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Remarks/Notes',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      vertical: LayoutConstants.spaceMd,
                      horizontal: LayoutConstants.spaceMd,
                    ),
                  ),
                ),
                if (FeatureFlags.enableOnlineSales) ...[
                  const SizedBox(height: LayoutConstants.spaceLg),
                  OutlinedButton.icon(
                    onPressed: viewModel.isLoading
                        ? null
                        : () => _preparePaymentLink(context, viewModel),
                    icon: const Icon(Icons.link),
                    label: const Text('Send Payment Link'),
                  ),
                  const SizedBox(height: LayoutConstants.spaceSm),
                  const Text(
                    'Manual Add Payment remains available for cash and external EFT.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
