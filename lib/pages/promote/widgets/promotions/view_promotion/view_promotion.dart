import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/product_link/product_picker_sheet.dart';
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
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? 'Promotion deleted successfully'
                          : 'Failed to delete promotion'),
                    ),
                  );
                  if (success) {
                    if (!context.mounted) return;
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
                  // PAS-UX-rel #5: show the linked product (if any)
                  // above the review/preview so merchants reviewing
                  // a saved promotion can immediately see what it
                  // was about. We read from the denormalized snapshot
                  // stored on the promotion doc (see
                  // PromotionsViewModel.savePromotion), so this keeps
                  // working even if the underlying product was later
                  // edited or deleted in stock.
                  if (LinkedProductRef.fromMap(
                          promo['linkedProduct'] as Map<String, dynamic>?) !=
                      null) ...[
                    _LinkedProductChip(
                      ref: LinkedProductRef.fromMap(
                          promo['linkedProduct'] as Map<String, dynamic>?)!,
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                  ],
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

/// Compact "this promotion is about X" chip shown at the top of a
/// saved promotion view. Reads from the denormalized snapshot stored
/// on the promotion document — see [PromotionsViewModel.savePromotion]
/// for why we copy fields onto the promo (the short version: so the
/// view doesn't silently break if the product is later edited or
/// deleted).
class _LinkedProductChip extends StatelessWidget {
  final LinkedProductRef ref;
  const _LinkedProductChip({required this.ref});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          if (ref.imageUrl != null && ref.imageUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                ref.imageUrl!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.inventory_2_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
            )
          else
            Icon(Icons.inventory_2_outlined,
                color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'About this product',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.disabledColor),
                ),
                Text(
                  ref.name,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
