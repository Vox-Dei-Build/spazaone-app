import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/utils/run_promotion_launcher.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/run_promotion_page.dart';
import 'package:pasella/pages/promote/widgets/promotions/view_promotion/promotion_detail_content.dart';
import 'package:pasella/pages/promote/widgets/confirmation_dialog.dart';
import 'package:pasella/shared/billing/wallet_affordability_footer.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/spaza_shimmer.dart';

/// PAS-UX-18: a promotion is in a terminal state once the backend has
/// written one of `complete`, `partial` or `failed`. `saved` is
/// waiting for the merchant to send; `processing` is in flight.
/// Anything else (legacy / unknown) is treated as terminal so we
/// don't accidentally hide the re-run affordance on older docs.
bool _isTerminalStatus(String? status) {
  if (status == null || status.isEmpty) return false;
  return status != 'saved' && status != 'processing';
}

class ViewPromotionPage extends StatefulWidget {
  final PromotionsViewModel viewModel;
  final Map<String, dynamic> promo;

  const ViewPromotionPage({
    Key? key,
    required this.viewModel,
    required this.promo,
  }) : super(key: key);

  @override
  State<ViewPromotionPage> createState() => _ViewPromotionPageState();
}

class _ViewPromotionPageState extends State<ViewPromotionPage> {
  bool _loading = true;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.loadPromotionIntoState(widget.promo).whenComplete(() {
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  Future<void> _sendNow(String promoId) async {
    setState(() => _actionLoading = true);
    // PAS-WA-01: show the merchant what happened. The previous code
    // awaited a `Future<void>` and popped without feedback even when
    // every recipient failed. We now read the structured result and
    // surface either the provider error or the SpazaOne fallback.
    final result = await widget.viewModel.sendSavedPromotion(promoId);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (result.isOk) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Promotion sent.')),
      );
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
    Navigator.pop(context);
  }

  /// PAS-UX-18: launch the run-promotion wizard pre-filled from this
  /// promotion (template, channels, linked product). Recipients are
  /// deliberately not carried — see `RunPromotionPage.rerunFromPromo`.
  /// We clear the VM's selection state before pushing so the merchant
  /// arrives on step 2 with a clean slate rather than the recipients
  /// from the promotion they were viewing.
  Future<void> _runAgain() async {
    final vm = widget.viewModel;
    vm.clearCustomerSelection();
    if (!mounted) return;
    final linkedValue = widget.promo['linkedProduct'];
    final linkedProduct = linkedValue is Map<String, dynamic>
        ? LinkedProductRef.fromMap(linkedValue)
        : null;
    if (linkedProduct != null) {
      await RunPromotionLauncher.launch(
        context,
        viewModel: vm,
        initialProduct: linkedProduct,
      );
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunPromotionPage(rerunFromPromo: widget.promo),
      ),
    );
    if (!mounted) return;
    // After returning from the wizard, pop this view so the merchant
    // lands back on the promotions list (which already refreshes its
    // own reports). Avoids leaving a stale "viewing the old promo"
    // surface behind a freshly-sent newer one.
    Navigator.of(context).pop();
  }

  void _confirmDelete() {
    final vm = widget.viewModel;
    final promo = widget.promo;
    showDialog<void>(
      context: context,
      builder: (_) => ConfirmationDialog(
        title: 'Delete campaign?',
        message: 'This removes the campaign from your history.',
        confirmLabel: 'Delete',
        cancelLabel: 'Keep campaign',
        onConfirm: () async {
          setState(() => _actionLoading = true);
          final success = await vm.deletePromotion(promo['id'] as String);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success ? 'Campaign deleted.' : 'Could not delete campaign.',
              ),
            ),
          );
          if (success && mounted) {
            Navigator.of(context).pop();
          } else if (mounted) {
            setState(() => _actionLoading = false);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final promo = widget.promo;
    final status = promo['status'] as String?;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Campaign details',
        trailing: IconButton(
          tooltip: 'Delete campaign',
          icon: const Icon(Icons.delete_outline_rounded, size: 22),
          onPressed: _actionLoading ? null : _confirmDelete,
        ),
      ),
      body: _loading
          ? const SpazaDetailSkeleton(
              semanticsLabel: 'Loading campaign details',
            )
          : _actionLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: PromotionDetailContent(
                        promo: promo,
                        templateContent: vm.currentTemplateContent,
                        shopName: vm.shopName,
                        estimatedCost: vm.totalPrice,
                        customers: vm.customers,
                        selectedCustomerIds: vm.selectedCustomerIds.toSet(),
                        mediaUrl: vm.currentMediaUrl,
                      ),
                    ),
                    if (status == 'saved' || _isTerminalStatus(status))
                      Container(
                        padding: const EdgeInsets.fromLTRB(
                          LayoutConstants.spaceLg,
                          LayoutConstants.spaceMd,
                          LayoutConstants.spaceLg,
                          LayoutConstants.spaceSm,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            top: BorderSide(color: Color(0xFFE0E5E1)),
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: status == 'saved'
                              ? WalletAffordabilityFooter(
                                  cost: vm.totalPrice,
                                  confirmLabel: 'Send campaign',
                                  confirmIcon: Icons.send_outlined,
                                  busy: _actionLoading,
                                  onConfirm: () =>
                                      _sendNow(promo['id'] as String),
                                )
                              : SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed:
                                        _actionLoading ? null : _runAgain,
                                    icon: const Icon(Icons.replay_rounded),
                                    label:
                                        const Text('Run this campaign again'),
                                  ),
                                ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
