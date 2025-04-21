import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/steps/customer_selection/customer_selection_step.dart';
import 'package:pasella/pages/promote/widgets/promotions/steps/promotion_details/template_and_details_step.dart';
import 'package:pasella/pages/promote/widgets/promotions/steps/review_and_pricing/review_and_pricing_step.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';

enum RunPromotionStep {
  templateAndDetails,
  customerSelection,
  reviewAndPricing,
}

class RunPromotionPage extends StatefulWidget {
  const RunPromotionPage({Key? key}) : super(key: key);

  @override
  State<RunPromotionPage> createState() => _RunPromotionPageState();
}

class _RunPromotionPageState extends State<RunPromotionPage> {
  RunPromotionStep currentStep = RunPromotionStep.templateAndDetails;
  bool calculating = false;
  String? selectedTemplateId;
  bool sendWhatsApp = true;
  bool sendSMS = true;
  bool allCustomers = true;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final vm = Provider.of<PromotionsViewModel>(context, listen: false);
      await vm.fetchTemplates();
      await vm.fetchMessageShopName();
      await vm.initializePricing();
      await vm.fetchCustomers();

      if (allCustomers) {
        vm.selectAllCustomers();
      }
    });
  }

  void nextStep() async {
    final vm = Provider.of<PromotionsViewModel>(context, listen: false);

    // Step 1 validation: template + at least one channel
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

    // Step 2 validation: at least one customer
    if (currentStep == RunPromotionStep.customerSelection) {
      if (vm.selectedCustomerIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one customer.')),
        );
        return;
      }

      // do your pricing calculation only after the above passes
      setState(() => calculating = true);
      final selectedTemplate = vm.templates.firstWhere(
        (t) => t['id'] == selectedTemplateId,
        orElse: () => {},
      );
      final smsContent =
          selectedTemplate['channels']?['sms']?['templateContent'];
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

    // If we got here, all validation passed → advance step
    setState(() {
      currentStep = RunPromotionStep.values[currentStep.index + 1];
    });
  }

  void previousStep() {
    if (currentStep.index == 0) return;
    setState(() {
      currentStep = RunPromotionStep.values[currentStep.index - 1];
    });
  }

  Future<void> _sendPromotion() async {
    final viewModel = Provider.of<PromotionsViewModel>(context);
    if (selectedTemplateId == null) return;

    setState(() => sending = true);

    await viewModel.sendPromotion(
      templateId: selectedTemplateId!,
      customerIds: viewModel.selectedCustomerIds,
      variables: {
        'shopName': viewModel.shopName,
        'customerName': 'Sibusiso',
      },
      testMode: false,
    );

    if (context.mounted) Navigator.pop(context);
  }

  Widget _buildStepContent() {
    final viewModel = Provider.of<PromotionsViewModel>(context);
    switch (currentStep) {
      case RunPromotionStep.templateAndDetails:
        return TemplateAndDetailsStep(
          templates: viewModel.templates,
          shopName: viewModel.shopName,
          selectedTemplateId: selectedTemplateId,
          sendWhatsApp: sendWhatsApp,
          sendSMS: sendSMS,
          whatsappPrice: viewModel.whatsappPrice,
          smsPricePerSegment: viewModel.smsPricePerSegment,
          onTemplateChanged: (val) {
            setState(() {
              selectedTemplateId = val;
              if (val != null) viewModel.selectTemplate(val);
            });
          },
          onWhatsAppChanged: (val) => setState(() => sendWhatsApp = val),
          onSMSChanged: (val) => setState(() => sendSMS = val),
        );

      case RunPromotionStep.customerSelection:
        return CustomerSelectionStep(
          allCustomers: allCustomers,
          customers: viewModel.customers,
          selectedCustomerIds: viewModel.selectedCustomerIds.toSet(),
          onAllCustomersChanged: (val) {
            setState(() {
              allCustomers = val;
              if (val) {
                viewModel.selectAllCustomers();
              } else {
                viewModel.clearCustomerSelection();
              }
            });
          },
          onCustomerToggle: (customerId) {
            setState(() {
              viewModel.toggleCustomerSelection(customerId);
            });
          },
        );

      case RunPromotionStep.reviewAndPricing:
        final selectedTemplate = viewModel.templates.firstWhere(
          (t) => t['id'] == selectedTemplateId,
          orElse: () => {},
        );

        final content =
            selectedTemplate['channels']?['whatsapp']?['templateContent'];
        final mediaUrl = selectedTemplate['channels']?['whatsapp']?['mediaUrl'];

        return ReviewAndPricingStep(
          templateContent: content,
          mediaUrl: mediaUrl,
          shopName: viewModel.shopName,
          sendWhatsApp: sendWhatsApp,
          sendSMS: sendSMS,
          totalCost: viewModel.totalPrice,
          breakdown: viewModel.promoBreakdown,
        );
    }
  }

  Widget _buildNavigationButtons() {
    final isLastStep = currentStep == RunPromotionStep.reviewAndPricing;
    final vm = Provider.of<PromotionsViewModel>(context, listen: false);

    // 1) Step‐1 is valid if template && (whatsapp||sms)
    final step1Valid = selectedTemplateId != null && (sendWhatsApp || sendSMS);
    // 2) Step‐2 is valid if at least one customer
    final step2Valid = vm.selectedCustomerIds.isNotEmpty;
    // 3) Step‐3 is always valid (it’s the send screen)
    final canProceed = currentStep == RunPromotionStep.templateAndDetails
        ? step1Valid
        : currentStep == RunPromotionStep.customerSelection
            ? step2Valid
            : true;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (currentStep != RunPromotionStep.templateAndDetails)
          OutlinedButton(onPressed: previousStep, child: const Text('Back')),
        ElevatedButton(
          onPressed: (sending || !canProceed)
              ? null
              : isLastStep
                  ? _sendPromotion
                  : nextStep,
          child: sending
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isLastStep ? 'Send Promotion' : 'Next'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<PromotionsViewModel>(context);
    return Scaffold(
      appBar: const CustomAppBar(title: 'Run Promotion'),
      // if templates are still loading, keep that indicator
      body: viewModel.loadingTemplates
          ? const Center(child: CircularProgressIndicator())
          // otherwise, if we’re doing our price calc, show full‑screen loader
          : calculating
              ? const Center(child: CircularProgressIndicator())
              // else show the normal step UI
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
}
