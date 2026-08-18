import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/services/payment_setup_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/widgets/private_region.dart';

@visibleForTesting
String? canonicalSettlementAccountType(String value) {
  switch (value.trim().toLowerCase()) {
    case 'personal':
      return 'personal';
    case 'business':
      return 'business';
    default:
      return null;
  }
}

@visibleForTesting
abstract interface class BankingDetailsFormController {
  TextEditingController get bankName;
  TextEditingController get accountHolderName;
  TextEditingController get accountNumber;
  TextEditingController get accountType;
  TextEditingController get branchCode;
  TextEditingController get reference;
  ValueListenable<bool> get isProcessing;

  Future<void> saveBankingDetails();
}

class _WalletBankingDetailsFormController
    implements BankingDetailsFormController {
  const _WalletBankingDetailsFormController(this.walletViewModel);

  final WalletViewModel walletViewModel;

  @override
  TextEditingController get bankName => walletViewModel.bankName;

  @override
  TextEditingController get accountHolderName =>
      walletViewModel.accountHolderName;

  @override
  TextEditingController get accountNumber => walletViewModel.accountNumber;

  @override
  TextEditingController get accountType => walletViewModel.accountType;

  @override
  TextEditingController get branchCode => walletViewModel.branchCode;

  @override
  TextEditingController get reference => walletViewModel.reference;

  @override
  ValueListenable<bool> get isProcessing => walletViewModel.isProcessing;

  @override
  Future<void> saveBankingDetails() => walletViewModel.saveBankingDetails();
}

class AddBankingDetailsPage extends StatefulWidget {
  final WalletViewModel? walletViewModel;
  final BankingDetailsFormController? formController;
  final Future<List<SupportedSettlementBank>> Function()? loadSupportedBanks;

  const AddBankingDetailsPage({
    super.key,
    required this.walletViewModel,
    this.loadSupportedBanks,
  }) : formController = null;

  @visibleForTesting
  const AddBankingDetailsPage.forTesting({
    super.key,
    required this.formController,
    this.loadSupportedBanks,
  }) : walletViewModel = null;

  @override
  State<AddBankingDetailsPage> createState() => _AddBankingDetailsPageState();
}

class _AddBankingDetailsPageState extends State<AddBankingDetailsPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  static const _accountTypeLabels = <String, String>{
    'personal': 'Personal',
    'business': 'Business',
  };
  List<SupportedSettlementBank> _banks = const [];
  SupportedSettlementBank? _selectedBank;
  String? _selectedAccountType;
  String? _bankLoadError;
  bool _loadingBanks = true;
  late final BankingDetailsFormController _details;

  @override
  void initState() {
    super.initState();
    _details = widget.formController ??
        _WalletBankingDetailsFormController(widget.walletViewModel!);
    _selectedAccountType = canonicalSettlementAccountType(
      _details.accountType.text,
    );
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    setState(() {
      _loadingBanks = true;
      _bankLoadError = null;
    });
    try {
      final banks = await (widget.loadSupportedBanks ??
          PaymentSetupService.supportedSettlementBanks)();
      if (!mounted) return;
      final savedName = _details.bankName.text.trim();
      final savedBranchCode = _details.branchCode.text.trim();
      SupportedSettlementBank? selected;
      for (final bank in banks) {
        if (bank.branchCode == savedBranchCode ||
            bank.name.toLowerCase() == savedName.toLowerCase()) {
          selected = bank;
          break;
        }
      }
      setState(() {
        _banks = banks;
        _selectedBank = selected;
        _loadingBanks = false;
        if (selected != null) {
          _details.bankName.text = selected.name;
          _details.branchCode.text = selected.branchCode;
          if (!selected.supportedAccountTypes.contains(_selectedAccountType)) {
            _selectedAccountType = null;
            _details.accountType.clear();
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingBanks = false;
        _bankLoadError =
            'Supported banks are unavailable right now. Your saved details have not changed.';
      });
    }
  }

  void _selectBank(SupportedSettlementBank? bank) {
    setState(() {
      _selectedBank = bank;
      if (bank == null ||
          !bank.supportedAccountTypes.contains(_selectedAccountType)) {
        _selectedAccountType = null;
        _details.accountType.clear();
      }
    });
    _details.bankName.text = bank?.name ?? '';
    _details.branchCode.text = bank?.branchCode ?? '';
  }

  void _selectAccountType(String? accountType) {
    setState(() => _selectedAccountType = accountType);
    _details.accountType.text = _accountTypeLabels[accountType] ?? '';
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
    String? helper,
    Widget? suffixIcon,
  }) {
    const borderColor = Color(0xFFDDE2E7);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: borderColor),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      errorMaxLines: 2,
      prefixIcon: Icon(icon, size: 21),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: border,
      enabledBorder: border,
      disabledBorder: border.copyWith(
        borderSide: const BorderSide(color: Color(0xFFE8EBEE)),
      ),
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: kPrimaryColor, width: 1.5),
      ),
    );
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await _details.saveBankingDetails();
      if (!mounted) return;
      showSnackbar(context, 'Banking details saved', kPrimaryColor);
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(
        context,
        'Banking details could not be saved. Try again.',
        Theme.of(context).colorScheme.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Banking Details'),
      backgroundColor: const Color(0xFFF6F7F9),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: PrivateRegion(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                const _BankingIntro(),
                const SizedBox(height: 16),
                _FormSection(
                  title: 'Bank account',
                  subtitle:
                      'Choose the bank first. We will fill in its universal branch code.',
                  icon: Icons.account_balance_outlined,
                  children: [
                    DropdownButtonFormField<SupportedSettlementBank>(
                      key: const ValueKey('supported-settlement-bank'),
                      value: _selectedBank,
                      isExpanded: true,
                      decoration: _fieldDecoration(
                        label: 'Bank',
                        hint: _loadingBanks
                            ? 'Loading supported banks…'
                            : 'Choose a supported bank',
                        icon: Icons.account_balance_outlined,
                        suffixIcon: _loadingBanks
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      items: _banks
                          .map(
                            (bank) => DropdownMenuItem(
                              value: bank,
                              child: Text(
                                bank.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _loadingBanks || _bankLoadError != null
                          ? null
                          : _selectBank,
                      validator: (value) =>
                          value == null ? 'Choose a supported bank.' : null,
                    ),
                    if (_bankLoadError case final message?) ...[
                      const SizedBox(height: 12),
                      _BankLoadError(message: message, onRetry: _loadBanks),
                    ],
                    if (_selectedBank case final bank?) ...[
                      const SizedBox(height: 12),
                      _BranchCodeSummary(branchCode: bank.branchCode),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('settlement-bank-account-type'),
                      value: _selectedAccountType,
                      isExpanded: true,
                      decoration: _fieldDecoration(
                        label: 'Account type',
                        hint: _selectedBank == null
                            ? 'Choose a bank first'
                            : 'Choose account type',
                        helper: 'Use the type registered with your bank.',
                        icon: Icons.account_box_outlined,
                      ),
                      items: (_selectedBank?.supportedAccountTypes ?? const [])
                          .map(
                            (accountType) => DropdownMenuItem(
                              value: accountType,
                              child: Text(
                                _accountTypeLabels[accountType] ?? accountType,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged:
                          _selectedBank == null ? null : _selectAccountType,
                      validator: (value) =>
                          value == null ? 'Choose the account type.' : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _FormSection(
                  title: 'Account details',
                  subtitle:
                      'Enter the details exactly as they appear on the bank account.',
                  icon: Icons.badge_outlined,
                  children: [
                    TextFormField(
                      key: const ValueKey('settlement-account-holder'),
                      controller: _details.accountHolderName,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: _fieldDecoration(
                        label: 'Account holder',
                        hint: 'Full registered name',
                        icon: Icons.person_outline,
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 2
                          ? 'Enter the account holder name.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('settlement-account-number'),
                      controller: _details.accountNumber,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 20,
                      decoration: _fieldDecoration(
                        label: 'Account number',
                        hint: '5–20 digits',
                        icon: Icons.account_balance_wallet_outlined,
                      ).copyWith(counterText: ''),
                      validator: (value) => !RegExp(
                        r'^\d{5,20}$',
                      ).hasMatch(value?.trim() ?? '')
                          ? 'Enter a valid account number.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('settlement-reference'),
                      controller: _details.reference,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                      decoration: _fieldDecoration(
                        label: 'Payment reference (optional)',
                        hint: 'Name shown on payout records',
                        icon: Icons.notes_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const _PrivacyNote(),
                const SizedBox(height: 20),
                ValueListenableBuilder<bool>(
                  valueListenable: _details.isProcessing,
                  builder: (context, isProcessing, _) {
                    return SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        key: const ValueKey('save-banking-details'),
                        onPressed: isProcessing ? null : _save,
                        icon: isProcessing
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(
                          isProcessing ? 'Saving…' : 'Save banking details',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: kPrimaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BankingIntro extends StatelessWidget {
  const _BankingIntro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kTertiaryColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.payments_outlined, color: Colors.white, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Where should payouts go?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Save the account that should receive money from your shop.',
                  style: TextStyle(color: Color(0xFFDDE0EE), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6E9ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: kHighLightColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: kPrimaryColor, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: kTertiaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: kSecondaryAccent,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _BranchCodeSummary extends StatelessWidget {
  const _BranchCodeSummary({required this.branchCode});

  final String branchCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('settlement-branch-code'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kHighLightColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.numbers_rounded, color: kPrimaryColor, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Universal branch code',
              style: TextStyle(
                color: kSecondaryAccent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SelectableText(
            branchCode,
            style: const TextStyle(
              color: kTertiaryColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _BankLoadError extends StatelessWidget {
  const _BankLoadError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Container(
      key: const ValueKey('supported-bank-load-error'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: error.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.cloud_off_outlined, color: error, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message, style: const TextStyle(height: 1.35)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, color: kSecondaryAccent, size: 18),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Saving does not switch on online payments. Bank verification is a separate, protected step.',
            style: TextStyle(color: kSecondaryAccent, height: 1.35),
          ),
        ),
      ],
    );
  }
}
