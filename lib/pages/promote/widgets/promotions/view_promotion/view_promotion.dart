import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/review_and_pricing/review_and_pricing_step.dart';
import 'package:pasella/pages/promote/widgets/confirmation_dialog.dart';
import 'package:pasella/shared/billing/wallet_affordability_footer.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';

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
    widget.viewModel
        .loadPromotionIntoState(widget.promo)
        .whenComplete(() => setState(() => _loading = false));
  }

  Future<void> _sendNow(String promoId) async {
    setState(() => _actionLoading = true);
    await widget.viewModel.sendSavedPromotion(promoId);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final promo = widget.promo;
    final ts = (promo['createdAt'] as Timestamp).toDate();
    final formattedDate = DateFormat('MMM dd, yyyy – hh:mm a').format(ts);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'View Promotion',
        trailing: IconButton(
          icon: Icon(Icons.delete, size: SizeConfig.imageSizeMultiplier * 5),
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => ConfirmationDialog(
                title: 'Delete Promotion',
                message: 'Are you sure you want to delete this promotion?',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                onConfirm: () async {
                  setState(() => _actionLoading = true);
                  final success =
                      await vm.deletePromotion(promo['id'] as String);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? 'Promotion deleted successfully'
                          : 'Failed to delete promotion'),
                    ),
                  );
                  if (success) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            );
          },
        ),
      ),
      body: _loading || _actionLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: LayoutConstants.padding10Horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Created: $formattedDate',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.4),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 1),
                  Expanded(
                    child: ReviewAndPricingStep(
                      templateContent: vm.currentTemplateContent,
                      mediaUrl: vm.currentMediaUrl,
                      shopName: vm.shopName,
                      sendWhatsApp: promo['sendWhatsApp'] as bool,
                      sendSMS: promo['sendSMS'] as bool,
                      totalCost: vm.totalPrice,
                      breakdown: vm.promoBreakdown,
                      customers: vm.customers,
                      selectedCustomerIds: vm.selectedCustomerIds.toSet(),
                    ),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 1),

                  // Only show send/top-up if promo is saved
                  if (promo['status'] == 'saved')
                    WalletAffordabilityFooter(
                      cost: vm.totalPrice,
                      confirmLabel: 'Send Now',
                      confirmIcon: Icons.send,
                      busy: _actionLoading,
                      onConfirm: () => _sendNow(promo['id'] as String),
                    ),
                ],
              ),
            ),
    );
  }
}
