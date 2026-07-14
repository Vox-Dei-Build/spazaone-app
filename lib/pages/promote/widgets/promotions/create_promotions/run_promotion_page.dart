import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/utils/template_status.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/customer_selection/customer_selection_step.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/promotion_details/template_and_details_step.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/review_and_pricing/review_and_pricing_step.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/create_template.dart';
import 'package:pasella/pages/promote/widgets/templates/create_template/template_submitted_success_page.dart';
import 'package:pasella/shared/billing/wallet_affordability_footer.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/forms/confirm_dialog.dart';
import 'package:pasella/shared/widgets/wizard_stepper.dart';
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
  /// PAS-UX-06: pre-select a template on first frame.
  ///
  /// When the merchant taps "Use this template" on the Templates tab,
  /// the audit found they were dropped on Step 1 with an empty
  /// template picker and forced to find the template they had just
  /// been looking at. This field lets the launcher carry the choice
  /// across so the wizard opens already on Step 1 with that template
  /// selected. The merchant can still change it before tapping Next.
  final String? initialTemplateId;

  /// PAS-UX-18: pre-fill the wizard from a previously-run promotion
  /// so merchants can launch the same promotion again without
  /// re-picking the template, channels and linked product. Recipients
  /// are intentionally NOT carried: the merchant is on a fresh send
  /// flow and almost always wants to revisit "who" (new customers may
  /// have signed up, some may no longer be relevant). They reach
  /// step 2 with a clean selection.
  ///
  /// Shape matches a promotion document read from Firestore
  /// (`templateId`, `sendWhatsApp`, `sendSMS`, `linkedProduct`).
  final Map<String, dynamic>? rerunFromPromo;

  // PAS-UX-17: removed `promoToEdit` field and `RunPromotionPage.edit`
  // named constructor. Both were dead -- no callsite anywhere in the
  // codebase, and `promoToEdit` was never read inside the State. The
  // wizard has only ever supported the "new promotion" flow; editing
  // a saved-but-not-sent promotion happens through the existing
  // promotions tab review path (see PAS-UX-11), not through
  // re-entering this wizard with a pre-filled draft.

  const RunPromotionPage({
    Key? key,
    this.initialTemplateId,
    this.rerunFromPromo,
  }) : super(key: key);

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
  bool _completed = false;

  // ─── Save vs. Send Flow ───────────────────────────
  bool isSaved = false;
  String? savedPromotionId;

  // ─── User Selections ─────────────────────────────
  String? selectedTemplateId;
  bool sendWhatsApp = true;
  // SMS is opt-in to avoid surprise charges; merchants can enable explicitly.
  bool sendSMS = false;
  bool allCustomers = true;

  // PAS-UX-rel #5: optional product attached to this promotion. Kept
  // as a single field (not a list) — the audit decision was Option B:
  // one product per promotion to keep the mental model simple. Null
  // means "no product attached" and is the default.
  LinkedProductRef? linkedProduct;

  @override
  void initState() {
    super.initState();
    // PAS-UX-06: honour the launcher-supplied template id so the
    // merchant arriving from "Use this template" sees their choice
    // already selected on Step 1.
    selectedTemplateId = widget.initialTemplateId;
    // PAS-UX-18: pre-fill from a previously-run promotion when the
    // wizard is opened via "Run again". Recipients are deliberately
    // not carried — see the field doc.
    final rerun = widget.rerunFromPromo;
    if (rerun != null) {
      selectedTemplateId = rerun['templateId'] as String? ?? selectedTemplateId;
      sendWhatsApp = rerun['sendWhatsApp'] as bool? ?? sendWhatsApp;
      sendSMS = rerun['sendSMS'] as bool? ?? sendSMS;
      final lp = rerun['linkedProduct'];
      if (lp is Map<String, dynamic>) {
        linkedProduct = LinkedProductRef.fromMap(lp);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = Provider.of<PromotionsViewModel>(context, listen: false);
      // PAS-UX-rel #3c: targeted refresh on entry. Approval state can
      // have flipped server-side since the merchant last opened the
      // Promote surface; without this, they could land on Step 1
      // looking at a stale "pending" pill on a template that is
      // actually approved (or vice versa). Cheap one-shot fetch —
      // we'd reach for a Firestore stream only if this proves
      // insufficient in practice.
      vm.loadTemplatesData();
      // PAS-UX-18: when re-running, also push the selected template
      // into the VM so price calculation & template-content getters
      // line up with what initState pre-filled.
      final tplId = selectedTemplateId;
      if (tplId != null) {
        vm.selectTemplate(tplId);
      }
      if (allCustomers) {
        vm.selectAllCustomers();
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

    // Step 1 validation is shown inline via canProceed/UI hints — no SnackBar.

    if (currentStep == RunPromotionStep.templateAndDetails) {
      // PAS-WA-03: load WhatsApp capability for the loaded customers
      // so the channel-aware filter and banner on step 2 have real
      // data to work with. Cheap one-shot batched read; we only do
      // it here (not in `loadInitialData`) so merchants who never
      // reach step 2 don't pay for it.
      setState(() => calculating = true);
      await vm.loadWhatsAppCapability();
      if (!mounted) return;
      // Re-sync the "All customers" selection against the filtered
      // eligibility set so we don't carry forward selections of
      // customers who are about to be hidden.
      if (allCustomers) {
        final filtered = vm.filterCustomersForChannels(
          sendWhatsApp: sendWhatsApp,
          sendSMS: sendSMS,
        );
        vm.selectAllFromEligible(filtered.eligible);
      }
      setState(() => calculating = false);
    }

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
      vm.totalPrice = breakdown['total'];
      vm.promoBreakdown = breakdown;
      if (!mounted) return;
      setState(() => calculating = false);
    }

    if (!mounted) return;
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
      variables: {'shopName': vm.shopName, 'customerName': '[Customer Name]'},
      sendWhatsApp: sendWhatsApp,
      sendSMS: sendSMS,
      testMode: false,
      // PAS-UX-rel #5: persist denormalized product snapshot so the
      // saved promo can render the linked product even if the
      // underlying product is later edited/deleted.
      linkedProduct: linkedProduct?.toMap(),
    );
    if (promoId != null) {
      isSaved = true;
      savedPromotionId = promoId;
      await vm.fetchPromotionsReports();
    }
    if (!mounted) return;
    setState(() => sending = false);
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
    // PAS-WA-01: surface backend send outcomes. Previously this
    // awaited a `Future<void>`, ignored exceptions entirely and
    // popped — leaving the merchant with no idea whether anything
    // failed. The view-model now returns a structured result with
    // a message that is always populated (provider detail when
    // present, SpazaOne fallback otherwise).
    final result = await Provider.of<PromotionsViewModel>(
      context,
      listen: false,
    ).sendSavedPromotion(savedPromotionId!);
    if (!mounted) return;
    setState(() => sending = false);
    final messenger = ScaffoldMessenger.of(context);
    if (result.isOk) {
      messenger.showSnackBar(const SnackBar(content: Text('Promotion sent.')));
      _completed = true;
      Navigator.pop(context);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Send failed.'),
          backgroundColor:
              result.outcome == SendPromotionOutcome.failed ? Colors.red : null,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _openCreateTemplate() async {
    final vm = Provider.of<PromotionsViewModel>(context, listen: false);
    final beforeIds = vm.templates.map((t) => t['id']).toSet();

    final result = await Navigator.push<TemplateSubmitResult>(
      context,
      MaterialPageRoute(builder: (_) => CreateTemplatePage(viewModel: vm)),
    );

    if (result == null || !mounted) return;

    // If the merchant tapped "View pending templates", we owe them a
    // visit to the Templates tab. Easiest correct path: pop the
    // promotion wizard back to the host and propagate the result so
    // the host (PromotionsPage) switches tabs.
    if (result == TemplateSubmitResult.viewPending) {
      if (!context.mounted) return;
      Navigator.of(context).pop(TemplateSubmitResult.viewPending);
      return;
    }

    // "Done" path: refresh + try to auto-select the newly-created
    // template if it's already approved (e.g. previously approved
    // duplicate). Otherwise leave the picker as-is so the merchant
    // can see the pending row land in the list.
    await vm.loadTemplatesData();
    if (!mounted) return;

    final newTemplates =
        vm.templates.where((t) => !beforeIds.contains(t['id'])).toList();
    if (newTemplates.isEmpty) return;
    final newest = newTemplates.first;
    // Use canonical reader so we correctly detect newly-approved templates
    // whose status string was set without flipping the legacy boolean.
    final approved = templateStatusOf(newest).isUsable;

    if (approved) {
      setState(() {
        selectedTemplateId = newest['id'] as String?;
      });
      vm.selectTemplate(newest['id'] as String);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Selected your new template "${newest['displayName'] ?? newest['name']}".',
          ),
        ),
      );
    }
    // No fallback snackbar: TemplateSubmittedSuccessPage already explained
    // the pending state and the next-steps. Adding another toast on top
    // would just create noise.
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
    // Save flow: before saving, the user always sees a "Save Promotion"
    // button regardless of balance. After saving, the affordability footer
    // gates Send vs. Top-Up based on the live wallet balance.
    if (!isSaved) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          OutlinedButton(onPressed: previousStep, child: const Text('Back')),
          ElevatedButton(
            onPressed: sending ? null : _savePromotion,
            child: sending
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Promotion'),
          ),
        ],
      );
    }

    return WalletAffordabilityFooter(
      cost: vm.totalPrice,
      confirmLabel: 'Send Promotion',
      confirmIcon: Icons.send,
      busy: sending,
      onBack: previousStep,
      onConfirm: _runSavedPromotion,
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
          onCreateTemplate: _openCreateTemplate,
          linkedProduct: linkedProduct,
          onLinkedProductChanged: (p) => setState(() => linkedProduct = p),
        );

      case RunPromotionStep.customerSelection:
        // PAS-WA-03: filter the customer list by the selected
        // channels so the merchant only sees recipients that are
        // actually reachable on the chosen channel(s). Banner copy
        // (rendered inside CustomerSelectionStep) reflects the
        // current channel selection and explains hidden/unknown
        // counts.
        final filtered = vm.filterCustomersForChannels(
          sendWhatsApp: sendWhatsApp,
          sendSMS: sendSMS,
        );
        return CustomerSelectionStep(
          allCustomers: allCustomers,
          customers: filtered.eligible,
          hiddenWithoutNumberCount: vm.customersWithoutNumberCount,
          sendWhatsApp: sendWhatsApp,
          sendSMS: sendSMS,
          hiddenNotWhatsAppCount: filtered.hiddenNotWhatsApp,
          unknownWhatsAppCount: filtered.unknownIncluded,
          selectedCustomerIds: vm.selectedCustomerIds.toSet(),
          onAllCustomersChanged: (val) {
            setState(() {
              allCustomers = val;
              if (val) {
                vm.selectAllFromEligible(filtered.eligible);
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
          linkedProduct: linkedProduct,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<PromotionsViewModel>(context);
    final hasProgress = !_completed &&
        (currentStep != RunPromotionStep.templateAndDetails ||
            selectedTemplateId != null ||
            linkedProduct != null ||
            vm.selectedCustomerIds.isNotEmpty ||
            sendSMS ||
            !sendWhatsApp);
    return PopScope(
      canPop: !hasProgress,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await ConfirmDialog.showDestructive(
          context,
          title: 'Discard promotion?',
          message: 'Leaving now will discard your promotion selections.',
          confirmLabel: 'Discard',
          cancelLabel: 'Keep editing',
        );
        if (discard && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: const CustomAppBar(title: 'Run Promotion'),
        body: vm.loadingTemplates
            ? const Center(child: CircularProgressIndicator())
            : calculating
                ? const Center(child: CircularProgressIndicator())
                : Padding(
                    padding: LayoutConstants.padding10Horizontal,
                    child: Column(
                      children: [
                        WizardStepper(
                          steps: const ['Template', 'Customers', 'Review'],
                          currentIndex: currentStep.index,
                        ),
                        Expanded(child: _buildStepContent()),
                        SizedBox(height: SizeConfig.heightMultiplier * 2),
                        _buildNavigationButtons(),
                      ],
                    ),
                  ),
      ),
    );
  }
}
