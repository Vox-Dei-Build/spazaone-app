import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/utils/template_status.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/customer_selection/customer_selection_step.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/review_and_pricing/review_and_pricing_step.dart';
import 'package:pasella/services/whatsapp_capability_cache.dart';
import 'package:pasella/shared/billing/wallet_affordability_footer.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/wizard_stepper.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:provider/provider.dart';

enum _ProductPromotionStep { customers, review }

String productPromotionFailureMessage(String? providerMessage) {
  if (providerMessage?.contains('63032') == true) {
    return 'Meta is temporarily blocking marketing messages to this '
        'customer. Choose another customer or try again later. You were not '
        'charged.';
  }
  final message = providerMessage?.trim();
  return message == null || message.isEmpty
      ? 'The promotion was not delivered. You were not charged.'
      : message;
}

String buildProductPromotionSmsPreview({
  required String shopName,
  required LinkedProductRef product,
  required String merchantMobileNumber,
}) {
  final price = product.sellingPrice == null
      ? 'a price available in WhatsApp'
      : 'R${product.sellingPrice!.toStringAsFixed(2)}';
  final contact = normalizePhoneNumber(merchantMobileNumber);
  final orderInstruction = contact.isEmpty
      ? 'Contact the shop to order.'
      : 'Call $contact to order.';
  final resolvedShopName =
      shopName.trim().isEmpty ? 'Spaza One' : shopName.trim();
  return '$resolvedShopName: ${product.name.trim()} is $price. '
      '$orderInstruction Reply STOP to opt out.';
}

class ProductPromotionPage extends StatefulWidget {
  const ProductPromotionPage({super.key, required this.product});

  final LinkedProductRef product;

  @override
  State<ProductPromotionPage> createState() => _ProductPromotionPageState();
}

class _ProductPromotionPageState extends State<ProductPromotionPage> {
  _ProductPromotionStep _step = _ProductPromotionStep.customers;
  Map<String, dynamic>? _template;
  bool _loading = true;
  bool _retrying = false;
  bool _sending = false;
  bool _allCustomers = false;
  SendPromotionResult? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare({bool retry = false}) async {
    final vm = context.read<PromotionsViewModel>();
    setState(() {
      if (retry) {
        _retrying = true;
      } else {
        _loading = true;
      }
    });

    await vm.loadInitialData();
    final template = await vm.ensureProductPromotionTemplate(retry: retry);
    if (!mounted) return;
    _template = template;

    if (template != null && templateStatusOf(template).isUsable) {
      final templateId = template['id'] as String?;
      if (templateId != null) vm.selectTemplate(templateId);
      await vm.loadWhatsAppCapability();
      if (!mounted) return;
      final filtered = vm.filterCustomersForChannels(
        sendWhatsApp: true,
        sendSMS: true,
      );
      final recommended = PromotionsViewModel.recommendedCustomers(
        filtered.eligible,
      );
      vm.selectCustomerIds(
        recommended.map((customer) => customer['id'] as String),
      );
      _allCustomers = recommended.isNotEmpty &&
          recommended.length == filtered.eligible.length;
      final estimate = vm.estimateProductPromotion(
        smsContent: _smsContent(vm),
      );
      vm.promoBreakdown = estimate;
      vm.totalPrice = (estimate['total'] as num).toDouble();
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _retrying = false;
    });
  }

  void _continueToReview() {
    final vm = context.read<PromotionsViewModel>();
    if (vm.selectedCustomerIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one customer.')),
      );
      return;
    }
    final estimate = vm.estimateProductPromotion(
      smsContent: _smsContent(vm),
    );
    vm.promoBreakdown = estimate;
    vm.totalPrice = (estimate['total'] as num).toDouble();
    setState(() => _step = _ProductPromotionStep.review);
  }

  Future<void> _saveAndSend() async {
    final vm = context.read<PromotionsViewModel>();
    final templateId = _template?['id'] as String?;
    if (templateId == null || !templateStatusOf(_template!).isUsable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp promotions are not ready yet.'),
        ),
      );
      return;
    }

    setState(() => _sending = true);
    final promoId = await vm.savePromotion(
      templateId: templateId,
      customerIds: vm.selectedCustomerIds,
      variables: {
        'shopName': vm.shopName,
        'customerName': '[Customer Name]',
        'productName': widget.product.name.trim(),
        'productPrice': widget.product.sellingPrice == null
            ? 'Price available in WhatsApp'
            : CurrencyUtil.format(widget.product.sellingPrice!),
      },
      sendWhatsApp: true,
      sendSMS: true,
      testMode: false,
      linkedProduct: widget.product.toMap(),
    );

    if (promoId == null) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not prepare the promotion.')),
      );
      return;
    }

    final result = await vm.sendSavedPromotion(promoId);
    if (!mounted) return;
    final selectedIds = vm.selectedCustomerIds.toSet();
    await WhatsAppCapabilityCache.instance.refreshFor(
      vm.customers
          .where((customer) => selectedIds.contains(customer['id']))
          .map((customer) => customer['number']?.toString()),
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final vm = context.watch<PromotionsViewModel>();

    return Scaffold(
      appBar: const CustomAppBar(title: 'Promote product'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _result?.isOk == true
              ? _SuccessView(
                  productName: widget.product.name.trim(),
                  sentCount: _result!.succeededCount,
                  onDone: () => Navigator.of(context).pop(),
                )
              : _result != null
                  ? _TemplateStatusView(
                      icon: Icons.error_outline,
                      iconColor: Colors.orange,
                      title: 'Promotion not delivered',
                      body: productPromotionFailureMessage(_result!.message),
                      actionLabel: 'Choose another customer',
                      busy: false,
                      onAction: () => setState(() {
                        _result = null;
                        _step = _ProductPromotionStep.customers;
                      }),
                    )
                  : _buildReadyOrStatus(vm),
    );
  }

  Widget _buildReadyOrStatus(PromotionsViewModel vm) {
    final template = _template;
    if (template == null) {
      return _TemplateStatusView(
        icon: Icons.cloud_off_outlined,
        title: 'Could not prepare promotions',
        body: 'Check your connection and try again.',
        actionLabel: 'Try again',
        busy: _retrying,
        onAction: () => _prepare(retry: true),
      );
    }

    final status = templateStatusOf(template);
    if (!status.isUsable) {
      final failed = status == TemplateStatus.rejected ||
          status == TemplateStatus.submissionFailed;
      return _TemplateStatusView(
        icon: failed ? Icons.warning_amber_rounded : Icons.hourglass_top,
        title: failed
            ? 'WhatsApp setup needs another try'
            : 'Preparing WhatsApp promotions',
        body: failed
            ? templateFailureReason(template) ??
                'Spaza One could not submit the reusable product message.'
            : 'Spaza One created the product message for you. Meta is reviewing '
                'it; there is nothing else you need to complete.',
        actionLabel: failed ? 'Retry setup' : 'Check again',
        busy: _retrying,
        onAction: () => _prepare(retry: failed),
      );
    }

    return Padding(
      padding: LayoutConstants.padding10Horizontal,
      child: Column(
        children: [
          WizardStepper(
            steps: const ['Customers', 'Send'],
            currentIndex: _step.index,
          ),
          Expanded(
            child: _step == _ProductPromotionStep.customers
                ? _customerStep(vm)
                : ReviewAndPricingStep(
                    templateContent: template['channels']?['whatsapp']
                        ?['templateContent'] as String?,
                    mediaUrl: widget.product.imageUrl,
                    shopName: vm.shopName,
                    sendWhatsApp: true,
                    sendSMS: true,
                    smsContent: _smsContent(vm),
                    totalCost: vm.totalPrice,
                    breakdown: vm.promoBreakdown,
                    linkedProduct: widget.product,
                  ),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 1.5),
          if (_step == _ProductPromotionStep.customers)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: vm.selectedCustomerIds.isEmpty
                        ? null
                        : _continueToReview,
                    child: const Text('Review promotion'),
                  ),
                ),
              ],
            )
          else
            WalletAffordabilityFooter(
              cost: vm.totalPrice,
              confirmLabel: 'Send promotion',
              confirmIcon: Icons.send,
              busy: _sending,
              onBack: () => setState(
                () => _step = _ProductPromotionStep.customers,
              ),
              onConfirm: _saveAndSend,
            ),
          SizedBox(height: SizeConfig.heightMultiplier * 1.5),
        ],
      ),
    );
  }

  Widget _customerStep(PromotionsViewModel vm) {
    final filtered = vm.filterCustomersForChannels(
      sendWhatsApp: true,
      sendSMS: true,
    );
    final selectedCount = vm.selectedCustomerIds.length;
    final recommendation = selectedCount == filtered.eligible.length
        ? 'Spaza One selected all $selectedCount reachable customers.'
        : 'Spaza One selected $selectedCount '
            'customer${selectedCount == 1 ? '' : 's'}. You can adjust the list.';
    return CustomerSelectionStep(
      heading: 'Who should receive it?',
      recommendationText: recommendation,
      allCustomersLabel: 'All customers with a number',
      allCustomers: _allCustomers,
      customers: filtered.eligible,
      selectedCustomerIds: vm.selectedCustomerIds.toSet(),
      hiddenWithoutNumberCount: vm.customersWithoutNumberCount,
      sendWhatsApp: true,
      sendSMS: true,
      hiddenNotWhatsAppCount: filtered.hiddenNotWhatsApp,
      unknownWhatsAppCount: filtered.unknownIncluded,
      onAllCustomersChanged: (selected) {
        setState(() => _allCustomers = selected);
        if (selected) {
          vm.selectAllFromEligible(filtered.eligible);
        } else {
          vm.clearCustomerSelection();
        }
      },
      onCustomerToggle: (id) {
        vm.toggleCustomerSelection(id);
        setState(() {
          _allCustomers =
              vm.selectedCustomerIds.length == filtered.eligible.length;
        });
      },
    );
  }

  String _smsContent(PromotionsViewModel vm) {
    return buildProductPromotionSmsPreview(
      shopName: vm.shopName,
      product: widget.product,
      merchantMobileNumber: vm.merchantMobileNumber,
    );
  }
}

class _TemplateStatusView extends StatelessWidget {
  const _TemplateStatusView({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.busy,
    required this.onAction,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String body;
  final String actionLabel;
  final bool busy;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: iconColor ?? theme.colorScheme.primary,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: busy ? null : onAction,
              child: busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({
    required this.productName,
    required this.sentCount,
    required this.onDone,
  });

  final String productName;
  final int sentCount;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 72, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              'Promotion sent',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '$productName promotion sent to $sentCount '
              'customer${sentCount == 1 ? '' : 's'}.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onDone, child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
