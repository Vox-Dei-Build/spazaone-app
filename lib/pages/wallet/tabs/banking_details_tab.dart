import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/add_banking_details.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/widgets/private_region.dart';
import 'package:pasella/services/fcm_service.dart';
import 'package:pasella/services/payment_setup_service.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/utils/support_util.dart';

class BankingDetailsTab extends StatefulWidget {
  const BankingDetailsTab({super.key});

  @override
  State<BankingDetailsTab> createState() => _BankingDetailsTabState();
}

class _BankingDetailsTabState extends State<BankingDetailsTab>
    with WidgetsBindingObserver {
  late WalletViewModel walletViewModel;
  late String _merchantId;
  MerchantPaymentOverview? _overview;
  Object? _overviewError;
  bool isLoading = true;
  bool isVerifying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _merchantId = StoreSession.instance.storeId;
    walletViewModel = WalletViewModel();
    _loadBankingDetails();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    walletViewModel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshForCurrentStore());
    }
  }

  Future<void> _refreshForCurrentStore() async {
    final currentMerchantId = StoreSession.instance.storeId;
    if (currentMerchantId != _merchantId) {
      walletViewModel.dispose();
      _merchantId = currentMerchantId;
      walletViewModel = WalletViewModel();
    }
    await _loadBankingDetails();
  }

  Future<void> _loadBankingDetails() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    final merchantId = _merchantId;
    MerchantPaymentOverview? overview;
    Object? overviewError;
    try {
      await walletViewModel.initializeBankingDetails();
      overview = await PaymentSetupService.overview(merchantId);
    } catch (error) {
      overviewError = error;
    }
    if (!mounted) return;
    if (merchantId != _merchantId) return;
    setState(() {
      _overview = overview;
      _overviewError = overviewError;
      isLoading = false;
    });
  }

  Future<void> _requestVerification() async {
    final bankingDetailsId = walletViewModel.editingDocumentId;
    if (bankingDetailsId == null || isVerifying) return;
    final merchantId = _merchantId;
    setState(() => isVerifying = true);
    try {
      final result = await PaymentSetupService.requestSettlementVerification(
        merchantId: merchantId,
        bankingDetailsId: bankingDetailsId,
      );
      if (!mounted || merchantId != _merchantId) return;
      await _loadBankingDetails();
      if (!mounted) return;
      final alreadySubmitted = result['deduped'] == true;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              alreadySubmitted
                  ? 'Your verification request is already in review.'
                  : 'Verification request sent. You can leave this screen while it is reviewed.',
            ),
          ),
        );
      await FCMService().requestPermissionIfNeeded(context);
    } on PaymentSetupException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => isVerifying = false);
    }
  }

  Future<void> _verifyForOnlineSettlements() async {
    if (isVerifying) return;
    final merchantId = _merchantId;
    final details = await showDialog<BankAccountVerificationDetails>(
      context: context,
      builder: (_) => BankAccountVerificationDialog(
        initialAccountType:
            walletViewModel.accountType.text.trim().toLowerCase(),
      ),
    );
    if (details == null || !mounted) return;
    if (merchantId != _merchantId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The active shop changed. Review its details first.'),
        ),
      );
      return;
    }
    setState(() => isVerifying = true);
    try {
      final result = await PaymentSetupService.prepareSettlementProfile(
        merchantId: merchantId,
        bankingDetailsId: walletViewModel.editingDocumentId!,
        accountType: details.accountType,
        documentType: details.documentType,
        documentNumber: details.documentNumber,
      );
      if (!mounted || merchantId != _merchantId) return;
      await _loadBankingDetails();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result['status'] == 'enabled'
                  ? 'Bank account verified for online sales.'
                  : 'Bank details submitted. The final review is now in progress.',
            ),
          ),
        );
      if (result['status'] != 'enabled') {
        await FCMService().requestPermissionIfNeeded(context);
      }
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

    final journey = _effectiveJourney;
    return RefreshIndicator(
      onRefresh: _refreshForCurrentStore,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: SizeConfig.heightMultiplier * 2),
              MerchantVerificationJourneyCard(
                journey: journey,
                isSubmitting: isVerifying,
                hasStatusError: _overviewError != null,
                onRequest: walletViewModel.editingDocumentId == null ||
                        !StoreSession.instance.canManageOperators
                    ? null
                    : _requestVerification,
                onVerify: StoreSession.instance.canManageOperators
                    ? _verifyForOnlineSettlements
                    : null,
                onRetry: _refreshForCurrentStore,
                onSupport: () => SupportUtil.sendWhatsAppMessage(
                  context,
                  WhatsAppMessageType.support,
                ),
              ),
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
                  !StoreSession.instance.canManageOperators) ...[
                const SizedBox(height: 12),
                const Text(
                  'Only the store owner or an administrator can verify the bank account for online sales.',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  MerchantVerificationJourney get _effectiveJourney {
    final overview = _overview;
    if (overview == null) {
      return MerchantVerificationJourney(
        stage: walletViewModel.editingDocumentId == null
            ? 'missing_information'
            : 'not_started',
        reason: 'status_unavailable',
        hasSavedBankingDetails: walletViewModel.editingDocumentId != null,
      );
    }
    final journey = overview.verification;
    if (journey.stage != 'approved' ||
        walletViewModel.editingDocumentId == null) {
      return journey;
    }
    final digits = walletViewModel.accountNumber.text.replaceAll(
      RegExp(r'\D'),
      '',
    );
    final savedMasked =
        digits.length >= 4 ? '•••• ${digits.substring(digits.length - 4)}' : '';
    final approvedMasked = overview.profile.maskedAccount.isNotEmpty
        ? overview.profile.maskedAccount
        : journey.maskedAccount;
    final approvedBank = overview.profile.bankName.isNotEmpty
        ? overview.profile.bankName
        : journey.bankName;
    final bankChanged = savedMasked.isNotEmpty &&
        (savedMasked != approvedMasked ||
            walletViewModel.bankName.text.trim() != approvedBank);
    return bankChanged
        ? MerchantVerificationJourney(
            stage: 'ready_to_submit',
            reason: 'bank_details_changed',
            requestStatus: journey.requestStatus,
            hasSavedBankingDetails: true,
            bankName: walletViewModel.bankName.text.trim(),
            maskedAccount: savedMasked,
          )
        : journey;
  }
}

class MerchantVerificationJourneyCard extends StatelessWidget {
  const MerchantVerificationJourneyCard({
    super.key,
    required this.journey,
    required this.isSubmitting,
    this.hasStatusError = false,
    this.onRequest,
    this.onVerify,
    this.onRetry,
    this.onSupport,
  });

  final MerchantVerificationJourney journey;
  final bool isSubmitting;
  final bool hasStatusError;
  final Future<void> Function()? onRequest;
  final Future<void> Function()? onVerify;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onSupport;

  @override
  Widget build(BuildContext context) {
    var title = 'Set up online payments';
    var body =
        'SpazaOne verifies the bank account that receives online-sale payouts. This protects your shop and prevents money being sent to the wrong account.';
    IconData icon = Icons.account_balance_outlined;
    String? actionLabel;
    Future<void> Function()? action;

    switch (journey.stage) {
      case 'missing_information':
        title = 'Add your bank details';
        body =
            'Add the bank name, account holder, account number, account type and branch code below. You can then submit a verification request.';
        icon = Icons.playlist_add_outlined;
      case 'ready_to_submit':
        title = journey.reason == 'bank_details_changed'
            ? 'Verify the changed bank account'
            : 'Ready to request verification';
        body =
            'We’ll first review your request. When it is ready, you’ll confirm the account owner and identity or business registration details for a secure bank check.';
        icon = Icons.fact_check_outlined;
        actionLabel = 'Request verification';
        action = onRequest;
      case 'submitted':
        title = 'Verification request sent';
        body =
            'SpazaOne is reviewing your request. Your progress is saved, so you can leave this screen. Come back later or pull down to refresh.';
        icon = Icons.schedule_outlined;
      case 'ready_to_verify':
        title = 'Ready for the secure bank check';
        body =
            'Confirm whether this is a personal or business account and enter the matching identity or registration number. It is sent once for validation and is not stored in readable form.';
        icon = Icons.verified_user_outlined;
        actionLabel = 'Continue verification';
        action = onVerify;
      case 'submitting':
        title = 'Checking your bank details';
        body =
            'Keep this screen open while the secure bank check finishes. Do not submit the same details again.';
        icon = Icons.sync_outlined;
      case 'pending_review':
        title = 'Bank details submitted';
        body =
            'The secure bank check passed and the final review is in progress. We’ll update this screen when online payments are ready.';
        icon = Icons.hourglass_top_outlined;
      case 'approved':
        title = 'Online payments are ready';
        body =
            'Your payout bank account is approved. Customers can use the online payment options enabled for your shop.';
        icon = Icons.verified_outlined;
      case 'changes_required':
        title = 'Bank details need changes';
        body =
            'Review and update the saved bank details below, then submit them again.';
        icon = Icons.edit_note_outlined;
        actionLabel = 'Submit updated details';
        action = onRequest;
      case 'rejected':
        title = 'Verification wasn’t approved';
        body =
            'Check the saved bank details or use another payout account, then request verification again. Contact support if you need help.';
        icon = Icons.info_outline;
        actionLabel = 'Try updated details';
        action = onRequest;
      case 'blocked':
        title = 'Verification is paused';
        body = journey.reason == 'authorization_expired'
            ? 'The verification window expired before the bank check finished. Contact support so the request can be reviewed again.'
            : 'A support review is needed before verification can continue. Your saved bank details and progress are still available.';
        icon = Icons.pause_circle_outline;
      case 'not_started':
        break;
      default:
        title = 'Verification status unavailable';
        body = 'Pull down to refresh or try again in a moment.';
        icon = Icons.cloud_off_outlined;
    }

    if (hasStatusError && journey.stage == 'not_started') {
      title = 'Verification status unavailable';
      body =
          'Your bank details are still saved. Check your connection and try loading the status again.';
      icon = Icons.cloud_off_outlined;
    }

    final bankName = journey.bankName.trim();
    final maskedAccount = journey.maskedAccount.trim();
    return DecoratedBox(
      key: const ValueKey('merchant-verification-journey'),
      decoration: BoxDecoration(
        color: kHighLightColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, color: kPrimaryColor, size: 30),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: kTertiaryColor,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: kSecondaryAccent,
                    height: 1.4,
                  ),
            ),
            if (bankName.isNotEmpty && maskedAccount.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '$bankName · $maskedAccount',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (actionLabel != null && action != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                key: ValueKey(
                  journey.stage == 'ready_to_verify'
                      ? 'continue-bank-verification'
                      : 'request-bank-verification',
                ),
                onPressed: isSubmitting ? null : () => unawaited(action!()),
                icon: isSubmitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward_rounded),
                label: Text(actionLabel),
              ),
            ],
            if ((hasStatusError || journey.stage == 'blocked') &&
                (onRetry != null || onSupport != null)) ...[
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  if (onRetry != null)
                    TextButton(
                      onPressed:
                          isSubmitting ? null : () => unawaited(onRetry!()),
                      child: const Text('Refresh status'),
                    ),
                  if (journey.stage == 'blocked' && onSupport != null)
                    TextButton(
                      onPressed:
                          isSubmitting ? null : () => unawaited(onSupport!()),
                      child: const Text('Contact support'),
                    ),
                ],
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
  const BankAccountVerificationDialog({
    super.key,
    this.initialAccountType = 'personal',
  });

  final String initialAccountType;

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
  bool _documentNumberVisible = false;

  @override
  void initState() {
    super.initState();
    _accountType =
        widget.initialAccountType == 'business' ? 'business' : 'personal';
    _documentType = _accountType == 'business'
        ? 'businessRegistrationNumber'
        : 'identityNumber';
  }

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
                  obscureText: !_documentNumberVisible,
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
                    suffixIcon: IconButton(
                      key: const ValueKey(
                        'bank-verification-document-visibility',
                      ),
                      tooltip: _documentNumberVisible
                          ? 'Hide document number'
                          : 'Show document number',
                      onPressed: () => setState(
                        () => _documentNumberVisible = !_documentNumberVisible,
                      ),
                      icon: Icon(
                        _documentNumberVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
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
