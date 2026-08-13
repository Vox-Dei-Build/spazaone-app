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
    final documentNumber = TextEditingController();
    var accountType = 'personal';
    var documentType = 'identityNumber';
    final details = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Verify settlement account'),
          content: PrivateRegion(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: accountType,
                  decoration: const InputDecoration(labelText: 'Account owner'),
                  items: const [
                    DropdownMenuItem(
                      value: 'personal',
                      child: Text('Personal'),
                    ),
                    DropdownMenuItem(
                      value: 'business',
                      child: Text('Business'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      accountType = value;
                      documentType = value == 'business'
                          ? 'businessRegistrationNumber'
                          : 'identityNumber';
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (accountType == 'personal')
                  DropdownButtonFormField<String>(
                    value: documentType,
                    decoration:
                        const InputDecoration(labelText: 'Identity document'),
                    items: const [
                      DropdownMenuItem(
                        value: 'identityNumber',
                        child: Text('South African ID'),
                      ),
                      DropdownMenuItem(
                        value: 'passportNumber',
                        child: Text('Passport'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => documentType = value);
                      }
                    },
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: documentNumber,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: accountType == 'business'
                        ? 'Business registration number'
                        : documentType == 'passportNumber'
                            ? 'Passport number'
                            : 'Identity number',
                    helperText:
                        'Sent once to Paystack for validation. SpazaOne stores only a protected fingerprint.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final number = documentNumber.text.trim();
                if (number.length < 5) return;
                Navigator.pop(dialogContext, {
                  'accountType': accountType,
                  'documentType': documentType,
                  'documentNumber': number,
                });
              },
              child: const Text('Validate'),
            ),
          ],
        ),
      ),
    );
    documentNumber.clear();
    documentNumber.dispose();
    if (details == null || !mounted) return;
    setState(() => isVerifying = true);
    try {
      final result = await PaymentSetupService.prepareSettlementProfile(
        merchantId: StoreSession.instance.storeId,
        bankingDetailsId: walletViewModel.editingDocumentId!,
        accountType: details['accountType']!,
        documentType: details['documentType']!,
        documentNumber: details['documentNumber']!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['status'] == 'enabled'
                ? 'Settlement account verified. Online collections will use this destination when payments are enabled.'
                : 'Account validated. SpazaOne review is required before online collections.',
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
            if (walletViewModel.editingDocumentId != null) ...[
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
                label: const Text('Verify for online settlements'),
              ),
              const SizedBox(height: 8),
              Text(
                'New or changed bank accounts are validated before customer payments can settle here. Bank changes may require SpazaOne review.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
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
