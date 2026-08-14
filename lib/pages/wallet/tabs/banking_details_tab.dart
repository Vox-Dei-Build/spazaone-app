import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/add_banking_details.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/widgets/private_region.dart';
import 'package:pasella/services/payment_setup_service.dart';
import 'package:pasella/services/store_session.dart';

class BankingDetailsTab extends StatefulWidget {
  const BankingDetailsTab({super.key});

  @override
  State<BankingDetailsTab> createState() => _BankingDetailsTabState();
}

class _BankingDetailsTabState extends State<BankingDetailsTab> {
  late WalletViewModel walletViewModel = WalletViewModel();
  bool isLoading = true;
  bool isVerifying = false;

  @override
  void initState() {
    super.initState();
    _loadBankingDetails();
  }

  @override
  void dispose() {
    walletViewModel.dispose();
    super.dispose();
  }

  Future<void> _loadBankingDetails() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    await walletViewModel.initializeBankingDetails();
    if (!mounted) return;
    setState(() => isLoading = false);
  }

  Future<void> _verifyForOnlineSettlements() async {
    final details = await showDialog<BankAccountVerificationDetails>(
      context: context,
      builder: (_) => const BankAccountVerificationDialog(),
    );
    if (details == null || !mounted) return;
    setState(() => isVerifying = true);
    try {
      final result = await PaymentSetupService.prepareSettlementProfile(
        merchantId: StoreSession.instance.storeId,
        bankingDetailsId: walletViewModel.editingDocumentId!,
        accountType: details.accountType,
        documentType: details.documentType,
        documentNumber: details.documentNumber,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['status'] == 'enabled'
                ? 'Bank account verified for online sales.'
                : 'Bank account checked. SpazaOne review is required before online payments can start.',
          ),
        ),
      );
    } on PaymentSetupException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            if (walletViewModel.editingDocumentId == null)
              Text(
                'Add banking details before store deposits or withdrawals need to be paid out.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.red,
                  fontSize: SizeConfig.textMultiplier * 1.5,
                ),
              )
            else
              BankingDetailsSummary(
                bankName: walletViewModel.bankName.text,
                accountHolderName: walletViewModel.accountHolderName.text,
                accountNumber: walletViewModel.accountNumber.text,
                accountType: walletViewModel.accountType.text,
                branchCode: walletViewModel.branchCode.text,
                reference: walletViewModel.reference.text,
              ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            if (StoreSession.instance.canManageOperators)
              CustomButton(
                title: 'Add / Edit Bank Account',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AddBankingDetailsPage(
                        walletViewModel: walletViewModel,
                      ),
                    ),
                  );
                  await _loadBankingDetails();
                },
                color: Colors.green,
                icon: Icons.add,
                fontSize: SizeConfig.textMultiplier * 2,
                width: SizeConfig.imageSizeMultiplier * 65,
              ),
            if (walletViewModel.editingDocumentId != null &&
                StoreSession.instance.canManageOperators) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('verify-paystack-settlement-account'),
                onPressed: isVerifying ? null : _verifyForOnlineSettlements,
                icon: isVerifying
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user_outlined),
                label: const Text('Verify for online payments'),
              ),
              const SizedBox(height: 8),
              Text(
                'New or changed bank accounts are checked before online sales can be paid into them. Bank changes may require SpazaOne review.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if (walletViewModel.editingDocumentId != null) ...[
              const SizedBox(height: 12),
              const Text(
                'Only the store owner or an administrator can verify the bank account for online sales.',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sensitive values collected only long enough to call the protected bank
/// validation endpoint. Nothing in this object is persisted or logged.
class BankAccountVerificationDetails {
  const BankAccountVerificationDetails({
    required this.accountType,
    required this.documentType,
    required this.documentNumber,
  });

  final String accountType;
  final String documentType;
  final String documentNumber;
}

/// Keyboard-safe bank validation form.
///
/// The controller belongs to the dialog route so it is disposed only after
/// the closing animation has removed every InputDecorator from the tree.
class BankAccountVerificationDialog extends StatefulWidget {
  const BankAccountVerificationDialog({super.key});

  @override
  State<BankAccountVerificationDialog> createState() =>
      _BankAccountVerificationDialogState();
}

class _BankAccountVerificationDialogState
    extends State<BankAccountVerificationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _documentNumber = TextEditingController();
  String _accountType = 'personal';
  String _documentType = 'identityNumber';

  @override
  void dispose() {
    _documentNumber.clear();
    _documentNumber.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(
      BankAccountVerificationDetails(
        accountType: _accountType,
        documentType: _documentType,
        documentNumber: _documentNumber.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('bank-account-verification-dialog'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('Verify bank account'),
      content: PrivateRegion(
        child: SizedBox(
          width: double.maxFinite,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: const ValueKey('bank-verification-account-type'),
                  value: _accountType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Account owner'),
                  items: const [
                    DropdownMenuItem(
                      value: 'personal',
                      child: Text('Personal', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'business',
                      child: Text('Business', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _accountType = value;
                      _documentType = value == 'business'
                          ? 'businessRegistrationNumber'
                          : 'identityNumber';
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (_accountType == 'personal')
                  DropdownButtonFormField<String>(
                    key: const ValueKey('bank-verification-document-type'),
                    value: _documentType,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Identity document'),
                    items: const [
                      DropdownMenuItem(
                        value: 'identityNumber',
                        child: Text(
                          'South African ID',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'passportNumber',
                        child:
                            Text('Passport', overflow: TextOverflow.ellipsis),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _documentType = value);
                      }
                    },
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('bank-verification-document-number'),
                  controller: _documentNumber,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) => (value?.trim().length ?? 0) < 5
                      ? 'Enter a valid document number.'
                      : null,
                  decoration: InputDecoration(
                    labelText: _accountType == 'business'
                        ? 'Business registration number'
                        : _documentType == 'passportNumber'
                            ? 'Passport number'
                            : 'Identity number',
                    helperText:
                        'Sent once for validation. SpazaOne stores only a protected fingerprint.',
                    helperMaxLines: 3,
                    errorMaxLines: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('submit-bank-account-verification'),
          onPressed: _submit,
          child: const Text('Validate'),
        ),
      ],
    );
  }
}

/// Copy-friendly, read-only presentation of the merchant's saved account.
class BankingDetailsSummary extends StatelessWidget {
  const BankingDetailsSummary({
    super.key,
    required this.bankName,
    required this.accountHolderName,
    required this.accountNumber,
    required this.accountType,
    required this.branchCode,
    required this.reference,
  });

  final String bankName;
  final String accountHolderName;
  final String accountNumber;
  final String accountType;
  final String branchCode;
  final String reference;

  List<MapEntry<String, String>> get _details => [
        MapEntry('Bank', bankName),
        MapEntry('Account Holder Name', accountHolderName),
        MapEntry('Account Number', accountNumber),
        MapEntry('Account Type', accountType),
        MapEntry('Branch Code', branchCode),
        if (reference.trim().isNotEmpty) MapEntry('Reference', reference),
      ];

  Future<void> _copy(BuildContext context, String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final allDetails =
        _details.map((detail) => '${detail.key}: ${detail.value}').join('\n');

    // Account details are intentionally visible and selectable here, but the
    // whole surface remains masked from replay and screenshot analytics.
    return PrivateRegion(
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: EdgeInsets.all(SizeConfig.heightMultiplier * 1.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final detail in _details)
                _BankingInfoRow(
                  label: detail.key,
                  value: detail.value,
                  onCopy: () => _copy(
                    context,
                    detail.value,
                    '${detail.key} copied',
                  ),
                ),
              const Divider(),
              TextButton.icon(
                key: const ValueKey('copy-all-banking-details'),
                onPressed: () => _copy(
                  context,
                  allDetails,
                  'Banking details copied',
                ),
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copy all banking details'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BankingInfoRow extends StatelessWidget {
  const _BankingInfoRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.5,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: SelectableText(
              value,
              style: const TextStyle(color: Colors.black54),
              textAlign: TextAlign.right,
            ),
          ),
          IconButton(
            key: ValueKey('copy-banking-${label.toLowerCase()}'),
            tooltip: 'Copy $label',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}
