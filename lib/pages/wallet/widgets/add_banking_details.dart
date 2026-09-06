import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:flutter/services.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/models/wallet/banking_detail_model.dart';
import 'package:pasella/services/payment_setup_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
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

/// An isolated edit draft. Saved values change only after [onSave] succeeds.
class AddBankingDetailsPage extends StatefulWidget {
  const AddBankingDetailsPage({
    super.key,
    required this.initialDetails,
    required this.onSave,
    this.isEditing = false,
    this.canEdit,
    this.loadSupportedBanks,
  });

  final BankingDetails initialDetails;
  final Future<void> Function(BankingDetails details) onSave;
  final bool isEditing;
  final bool Function()? canEdit;
  final Future<List<SupportedSettlementBank>> Function()? loadSupportedBanks;

  @override
  State<AddBankingDetailsPage> createState() => _AddBankingDetailsPageState();
}

class _BankingDetailsDraft {
  _BankingDetailsDraft(BankingDetails details)
      : bankName = TextEditingController(text: details.bankName),
        accountHolderName =
            TextEditingController(text: details.accountHolderName),
        accountNumber = TextEditingController(text: details.accountNumber),
        accountType = TextEditingController(text: details.accountType),
        branchCode = TextEditingController(text: details.branchCode),
        reference = TextEditingController(text: details.reference);

  final TextEditingController bankName;
  final TextEditingController accountHolderName;
  final TextEditingController accountNumber;
  final TextEditingController accountType;
  final TextEditingController branchCode;
  final TextEditingController reference;

  BankingDetails get value => BankingDetails(
        bankName: bankName.text.trim(),
        accountHolderName: accountHolderName.text.trim(),
        accountNumber: accountNumber.text.trim(),
        accountType: accountType.text.trim(),
        branchCode: branchCode.text.trim(),
        reference: reference.text.trim(),
      );

  void dispose() {
    bankName.dispose();
    accountHolderName.dispose();
    accountNumber.dispose();
    accountType.dispose();
    branchCode.dispose();
    reference.dispose();
  }
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
  late final _BankingDetailsDraft _details;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _details = _BankingDetailsDraft(widget.initialDetails);
    _selectedAccountType = canonicalSettlementAccountType(
      _details.accountType.text,
    );
    _loadBanks();
  }

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
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
    const borderColor = SpazaColors.border;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(SpazaRadius.control),
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
        borderSide: const BorderSide(color: SpazaColors.border),
      ),
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: kPrimaryColor, width: 1.5),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    if (widget.canEdit?.call() == false) {
      setState(() => _saveError =
          'Only the active shop owner or an administrator can edit these details.');
      return;
    }
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await widget.onSave(_details.value);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Banking details saved')));
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saveError =
          'Banking details could not be saved. Your previous details are unchanged. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: CustomAppBar(
            title: widget.isEditing
                ? 'Edit banking details'
                : 'Add banking details'),
        backgroundColor: SpazaColors.canvas,
        body: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: PrivateRegion(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BankingIntro(isEditing: widget.isEditing),
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
                          items:
                              (_selectedBank?.supportedAccountTypes ?? const [])
                                  .map(
                                    (accountType) => DropdownMenuItem(
                                      value: accountType,
                                      child: Text(
                                        _accountTypeLabels[accountType] ??
                                            accountType,
                                        overflow: TextOverflow.ellipsis,
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
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
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
                    if (_saveError case final message?) ...[
                      Semantics(
                          liveRegion: true,
                          child: Text(message,
                              key: const ValueKey('banking-save-error'),
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      key: const ValueKey('save-banking-details'),
                      onPressed:
                          _saving || _loadingBanks || _bankLoadError != null
                              ? null
                              : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check_rounded),
                      label: Text(_saving ? 'Saving…' : 'Save banking details',
                          textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      key: const ValueKey('cancel-banking-details'),
                      onPressed:
                          _saving ? null : () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BankingIntro extends StatelessWidget {
  const _BankingIntro({required this.isEditing});

  final bool isEditing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpazaColors.subtle,
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.payments_outlined,
              color: SpazaColors.heading, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing
                      ? 'Update your payout account'
                      : 'Where should payouts go?',
                  style: const TextStyle(
                    color: SpazaColors.heading,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  isEditing
                      ? 'Review the saved details below. Changes may need a new bank verification.'
                      : 'Save the account that should receive money from your shop.',
                  style:
                      const TextStyle(color: SpazaColors.muted, height: 1.35),
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
        borderRadius: BorderRadius.circular(SpazaRadius.surface),
        border: Border.all(color: SpazaColors.border),
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
                  borderRadius: BorderRadius.circular(SpazaRadius.small),
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
                        fontWeight: FontWeight.w500,
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
        borderRadius: BorderRadius.circular(SpazaRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.numbers_rounded, color: kPrimaryColor, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Universal branch code',
                  style: TextStyle(
                    color: kSecondaryAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            branchCode,
            style: const TextStyle(
              color: kTertiaryColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
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
        borderRadius: BorderRadius.circular(SpazaRadius.control),
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
