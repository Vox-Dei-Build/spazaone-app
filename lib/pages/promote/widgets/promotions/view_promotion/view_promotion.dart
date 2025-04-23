import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/create_promotions/review_and_pricing/review_and_pricing_step.dart';
import 'package:pasella/pages/promote/widgets/confirmation_dialog.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:provider/provider.dart';

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
  final userId = FirebaseAuth.instance.currentUser?.uid;
  late var userRef;
  late var walletRef;

  @override
  void initState() {
    super.initState();
    userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    walletRef = userRef.collection('wallet').doc('current');
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
  void dispose() {
    super.dispose();
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

                  // ── Only show send/top-up if promo is saved ──
                  if (promo['status'] == 'saved')
                    StreamBuilder<DocumentSnapshot>(
                      stream: walletRef.snapshots(),
                      builder: (context, snap) {
                        final loadingBal =
                            snap.connectionState == ConnectionState.waiting;
                        final data = snap.data?.data() as Map<String, dynamic>?;
                        final balance = data?['virtualBalance'] ?? 0.0;
                        final cost = vm.totalPrice;
                        final canAfford = balance >= cost;

                        // status line
                        final statusText = loadingBal
                            ? 'Checking wallet…'
                            : 'You have R${balance.toStringAsFixed(2)}, '
                                'cost is R${cost.toStringAsFixed(2)}';

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(statusText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: SizeConfig.textMultiplier * 1.6)),
                            SizedBox(height: SizeConfig.heightMultiplier * 1),
                            if (canAfford)
                              ElevatedButton.icon(
                                icon: const Icon(Icons.send),
                                label: const Text('Send Now'),
                                onPressed: _actionLoading
                                    ? null
                                    : () => _sendNow(promo['id'] as String),
                              )
                            else
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange),
                                onPressed: () {
                                  Navigator.of(context)
                                      .popUntil((r) => r.isFirst);
                                  Provider.of<AppModel>(context, listen: false)
                                      .goToBilling(context);
                                },
                                child: loadingBal
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Top Up Wallet'),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
