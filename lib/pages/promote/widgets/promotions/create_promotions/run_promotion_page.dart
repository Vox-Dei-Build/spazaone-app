// ┌──────────────────────────────────────────────────┐
// │ 🌟 RUN PROMOTION PAGE                             │
// │ A three-step wizard for merchants to             │
// │ save and send promotional messages seamlessly.   │
// └──────────────────────────────────────────────────┘
//
// Steps:
//   1. Select Template & Channels
//   2. Choose Customers
//   3. Review & Pricing

import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/customer_selection/customer_selection_step.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/promotion_details/template_and_details_step.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/review_and_pricing/review_and_pricing_step.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';

// ───────────────────────────────────────────────────
// Step Enumeration
// ───────────────────────────────────────────────────
enum RunPromotionStep {
  templateAndDetails,
  customerSelection,
  reviewAndPricing,
}

// ───────────────────────────────────────────────────
// Main Widget
// ───────────────────────────────────────────────────
class RunPromotionPage extends StatefulWidget {
  final Map<String, dynamic>? promoToEdit;

  /// normal “new” promotion
  const RunPromotionPage({Key? key})
      : promoToEdit = null,
        super(key: key);

  /// edit mode
  const RunPromotionPage.edit(this.promoToEdit, {Key? key}) : super(key: key);

  @override
  State<RunPromotionPage> createState() => _RunPromotionPageState();
}

// ───────────────────────────────────────────────────
// State Class
// ───────────────────────────────────────────────────
class _RunPromotionPageState extends State<RunPromotionPage> {
  // ─── Wizard state ─────────────────────────────────
  RunPromotionStep currentStep = RunPromotionStep.templateAndDetails;
  bool calculating = false;
  bool sending = false;

  // ─── Save vs. Send Flow ───────────────────────────
  bool isSaved = false;
  String? savedPromotionId;

  // ─── User Selections ─────────────────────────────
  String? selectedTemplateId;
  bool sendWhatsApp = true;
  bool sendSMS = true;
  bool allCustomers = true;

  final WalletViewModel walletVM = WalletViewModel();

  // ─────────────────────────────────────────────────
  // Lifecycle Hooks
  // ─────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = Provider.of<PromotionsViewModel>(context, listen: false);
      if (allCustomers) vm.selectAllCustomers();
    });
  }

  @override
  void dispose() {
    walletVM.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────
  // Navigation: Next & Previous
  // ─────────────────────────────────────────────────
  void nextStep() async {
    final vm = Provider.of<PromotionsViewModel>(context, listen: false);

    // Step 1: Validate template selection and channels
    if (currentStep == RunPromotionStep.templateAndDetails) {
      if (selectedTemplateId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a template.')),
        );
        return;
      }
      if (!sendWhatsApp && !sendSMS) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose at least one channel.')),
        );
        return;
      }
    }

    // Step 2: Validate customer selection and calculate pricing
    if (currentStep == RunPromotionStep.customerSelection) {
      if (vm.selectedCustomerIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one customer.')),
        );
        return;
      }
      setState(() => calculating = true);
      final template = vm.templates.firstWhere(
        (t) => t['id'] == selectedTemplateId,
        orElse: () => {},
      );
      final smsContent = template['channels']?['sms']?['templateContent'];
      final breakdown = await vm.calculatePriceWithBreakdown(
        sendWhatsApp,
        sendSMS,
        smsContent,
      );
      setState(() {
        vm.totalPrice = breakdown['total'];
        vm.promoBreakdown = breakdown;
        calculating = false;
      });
    }

    // Advance
    setState(() {
      currentStep = RunPromotionStep.values[currentStep.index + 1];
    });
  }

  void previousStep() {
    if (currentStep.index > 0) {
      setState(() {
        currentStep = RunPromotionStep.values[currentStep.index - 1];
      });
    }
  }

  // ─────────────────────────────────────────────────
  // Save & Send Actions
  // ─────────────────────────────────────────────────
  Future<void> _savePromotion() async {
    final vm = Provider.of<PromotionsViewModel>(context, listen: false);
    if (selectedTemplateId == null) return;

    setState(() => sending = true);
    final promoId = await vm.savePromotion(
      templateId: selectedTemplateId!,
      customerIds: vm.selectedCustomerIds,
      variables: {
        'shopName': vm.shopName,
        'customerName': '[Customer Name]',
      },
      sendWhatsApp: sendWhatsApp,
      sendSMS: sendSMS,
      testMode: false,
    );
    setState(() {
      sending = false;
      if (promoId != null) {
        isSaved = true;
        savedPromotionId = promoId;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isSaved
              ? 'Promotion saved. You can send it now.'
              : 'Failed to save promotion.',
        ),
      ),
    );
  }

  Future<void> _runSavedPromotion() async {
    if (savedPromotionId == null) return;
    setState(() => sending = true);
    final vm = Provider.of<PromotionsViewModel>(context, listen: false);
    await vm.sendSavedPromotion(savedPromotionId!);
    setState(() => sending = false);
    if (context.mounted) Navigator.pop(context);
  }

  // ─────────────────────────────────────────────────
  // Build Navigation Buttons
  // ─────────────────────────────────────────────────
  Widget _buildNavigationButtons() {
    final isLast = currentStep == RunPromotionStep.reviewAndPricing;
    final vm = Provider.of<PromotionsViewModel>(context, listen: false);

    if (!isLast) {
      final validStep1 =
          selectedTemplateId != null && (sendWhatsApp || sendSMS);
      final validStep2 = vm.selectedCustomerIds.isNotEmpty;
      final canProceed = currentStep == RunPromotionStep.templateAndDetails
          ? validStep1
          : validStep2;
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (currentStep != RunPromotionStep.templateAndDetails)
            OutlinedButton(onPressed: previousStep, child: const Text('Back')),
          ElevatedButton(
            onPressed: (sending || !canProceed) ? null : nextStep,
            child: sending
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Next'),
          ),
        ],
      );
    }

    // Final step: Save or Send
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: SizeConfig.heightMultiplier * 1),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(onPressed: previousStep, child: const Text('Back')),
            if (!isSaved)
              ElevatedButton(
                onPressed: sending ? null : _savePromotion,
                child: sending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Promotion'),
              )
            else
              ElevatedButton(
                onPressed: sending ? null : _runSavedPromotion,
                child: sending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send Promotion'),
              ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────
  // Main Build
  // ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<PromotionsViewModel>(context);
    return Scaffold(
      appBar: const CustomAppBar(title: 'Run Promotion'),
      body: vm.loadingTemplates
          ? const Center(child: CircularProgressIndicator())
          : calculating
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: LayoutConstants.padding10Horizontal,
                  child: Column(
                    children: [
                      Expanded(child: _buildStepContent()),
                      SizedBox(height: SizeConfig.heightMultiplier * 2),
                      _buildNavigationButtons(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStepContent() {
    final vm = Provider.of<PromotionsViewModel>(context);
    switch (currentStep) {
      case RunPromotionStep.templateAndDetails:
        return TemplateAndDetailsStep(
          templates: vm.templates,
          shopName: vm.shopName,
          selectedTemplateId: selectedTemplateId,
          sendWhatsApp: sendWhatsApp,
          sendSMS: sendSMS,
          whatsappPrice: vm.whatsappPrice,
          smsPricePerSegment: vm.smsPricePerSegment,
          onTemplateChanged: (val) {
            setState(() {
              selectedTemplateId = val;
              if (val != null) vm.selectTemplate(val);
            });
          },
          onWhatsAppChanged: (val) => setState(() => sendWhatsApp = val),
          onSMSChanged: (val) => setState(() => sendSMS = val),
        );

      case RunPromotionStep.customerSelection:
        return CustomerSelectionStep(
          allCustomers: allCustomers,
          customers: vm.customers,
          selectedCustomerIds: vm.selectedCustomerIds.toSet(),
          onAllCustomersChanged: (val) {
            setState(() {
              allCustomers = val;
              if (val) {
                vm.selectAllCustomers();
              } else {
                vm.clearCustomerSelection();
              }
            });
          },
          onCustomerToggle: (id) {
            setState(() => vm.toggleCustomerSelection(id));
          },
        );

      case RunPromotionStep.reviewAndPricing:
        final template = vm.templates.firstWhere(
          (t) => t['id'] == selectedTemplateId,
          orElse: () => {},
        );
        final content = template['channels']?['whatsapp']?['templateContent'];
        final mediaUrl = template['channels']?['whatsapp']?['mediaUrl'];
        return ReviewAndPricingStep(
          templateContent: content,
          mediaUrl: mediaUrl,
          shopName: vm.shopName,
          sendWhatsApp: sendWhatsApp,
          sendSMS: sendSMS,
          totalCost: vm.totalPrice,
          breakdown: vm.promoBreakdown,
        );
    }
  }
}
