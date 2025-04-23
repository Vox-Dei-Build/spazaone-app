import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/customer_selection/customer_selection_step.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/promotion_details/template_and_details_step.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/review_and_pricing/review_and_pricing_step.dart';
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
  final userId = FirebaseAuth.instance.currentUser?.uid;
  late var userRef;
  late var walletRef;

  @override
  void initState() {
    super.initState();
    userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    walletRef = userRef.collection('wallet').doc('current');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (allCustomers) {
        Provider.of<PromotionsViewModel>(context, listen: false)
            .selectAllCustomers();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ────────────────────────────────────────
  // Navigation
  // ────────────────────────────────────────
  void nextStep() async {
    final vm = Provider.of<PromotionsViewModel>(context, listen: false);

    if (currentStep == RunPromotionStep.templateAndDetails) {
      if (selectedTemplateId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a template.')));
        return;
      }
      if (!sendWhatsApp && !sendSMS) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Please choose at least one channel.')));
        return;
      }
    }

    if (currentStep == RunPromotionStep.customerSelection) {
      if (vm.selectedCustomerIds.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Select at least one customer.')));
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
      vm.totalPrice = breakdown['total'];
      vm.promoBreakdown = breakdown;
      setState(() => calculating = false);
    }

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

  // ────────────────────────────────────────
  // Save & Send
  // ────────────────────────────────────────
  Future<void> _savePromotion() async {
    final vm = Provider.of<PromotionsViewModel>(context, listen: false);
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
    if (promoId != null) {
      isSaved = true;
      savedPromotionId = promoId;
      await vm.fetchPromotionsReports();
    }
    setState(() => sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isSaved
            ? 'Promotion saved. You can send it now.'
            : 'Failed to save promotion.'),
      ),
    );
  }

  Future<void> _runSavedPromotion() async {
    if (savedPromotionId == null) return;
    setState(() => sending = true);
    await Provider.of<PromotionsViewModel>(context, listen: false)
        .sendSavedPromotion(savedPromotionId!);
    setState(() => sending = false);
    if (context.mounted) Navigator.pop(context);
  }

  Widget _buildNavigationButtons() {
    final isLastStep = currentStep == RunPromotionStep.reviewAndPricing;
    final vm = Provider.of<PromotionsViewModel>(context, listen: false);

    if (!isLastStep) {
      final step1Valid =
          selectedTemplateId != null && (sendWhatsApp || sendSMS);
      final step2Valid = vm.selectedCustomerIds.isNotEmpty;
      final canProceed = currentStep == RunPromotionStep.templateAndDetails
          ? step1Valid
          : step2Valid;

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

    // ── Final review: balance + Save/Send or Top-Up ──
    return StreamBuilder<DocumentSnapshot>(
      stream: walletRef.snapshots(),
      builder: (context, snap) {
        final loadingBalance = snap.connectionState == ConnectionState.waiting;
        final data = snap.data?.data() as Map<String, dynamic>?;
        final balance = data?['virtualBalance'] ?? 0.0;
        final totalCost = vm.totalPrice;
        final canAfford = balance >= totalCost;

        final statusText = loadingBalance
            ? 'Checking wallet…'
            : 'You have R${balance.toStringAsFixed(2)}, cost is R${totalCost.toStringAsFixed(2)}';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              statusText,
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.6),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(
                    onPressed: previousStep, child: const Text('Back')),

                // Always allow saving if not saved yet
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
                  // Once saved, allow sending only if balance suffices
                  (canAfford
                      ? ElevatedButton(
                          onPressed: sending ? null : _runSavedPromotion,
                          child: sending
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Send Promotion'),
                        )
                      : ElevatedButton(
                          onPressed: () {
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                            Provider.of<AppModel>(context, listen: false)
                                .goToBilling(context);
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange),
                          child: loadingBalance
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Top Up Wallet'),
                        )),
              ],
            ),
          ],
        );
      },
    );
  }

  // ───────────────────────────────────────────────────
  // Build Steps Content
  // ───────────────────────────────────────────────────
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
          onCustomerToggle: (id) =>
              setState(() => vm.toggleCustomerSelection(id)),
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
}
