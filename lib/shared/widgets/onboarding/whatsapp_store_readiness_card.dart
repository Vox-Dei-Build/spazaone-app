import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/stock/product_model.dart';
import 'package:pasella/pages/promote/utils/template_status.dart';

class WhatsAppStoreReadinessCard extends StatelessWidget {
  const WhatsAppStoreReadinessCard({
    super.key,
    required this.userId,
    required this.products,
    required this.onAddProduct,
    required this.onChooseWhatsAppProduct,
    required this.onOpenCustomers,
    required this.onOpenPromotions,
    required this.onOpenBanking,
  });

  final String userId;
  final List<Product> products;
  final VoidCallback onAddProduct;
  final VoidCallback onChooseWhatsAppProduct;
  final VoidCallback onOpenCustomers;
  final VoidCallback onOpenPromotions;
  final VoidCallback onOpenBanking;

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) return const SizedBox.shrink();

    final firestore = FirebaseFirestore.instance;
    final userScope = firestore.collection('users').doc(userId);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: userScope.collection('customers').limit(1).snapshots(),
      builder: (context, customerSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: userScope.collection('bankingDetails').limit(1).snapshots(),
          builder: (context, bankSnap) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: firestore
                  .collection('messagingTemplates')
                  .where('userId', isEqualTo: userId)
                  .limit(10)
                  .snapshots(),
              builder: (context, templateSnap) {
                final hasCustomers =
                    (customerSnap.data?.docs.isNotEmpty ?? false);
                final hasBank = bankSnap.data?.docs.isNotEmpty ?? false;
                final hasApprovedTemplate = templateSnap.data?.docs.any((doc) {
                      return templateStatusOf(doc.data()) ==
                          TemplateStatus.approved;
                    }) ??
                    false;

                return _ReadinessBody(
                  products: products,
                  hasCustomers: hasCustomers,
                  hasApprovedTemplate: hasApprovedTemplate,
                  hasBank: hasBank,
                  loading: customerSnap.connectionState ==
                          ConnectionState.waiting ||
                      bankSnap.connectionState == ConnectionState.waiting ||
                      templateSnap.connectionState == ConnectionState.waiting,
                  onAddProduct: onAddProduct,
                  onChooseWhatsAppProduct: onChooseWhatsAppProduct,
                  onOpenCustomers: onOpenCustomers,
                  onOpenPromotions: onOpenPromotions,
                  onOpenBanking: onOpenBanking,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ReadinessBody extends StatelessWidget {
  const _ReadinessBody({
    required this.products,
    required this.hasCustomers,
    required this.hasApprovedTemplate,
    required this.hasBank,
    required this.loading,
    required this.onAddProduct,
    required this.onChooseWhatsAppProduct,
    required this.onOpenCustomers,
    required this.onOpenPromotions,
    required this.onOpenBanking,
  });

  final List<Product> products;
  final bool hasCustomers;
  final bool hasApprovedTemplate;
  final bool hasBank;
  final bool loading;
  final VoidCallback onAddProduct;
  final VoidCallback onChooseWhatsAppProduct;
  final VoidCallback onOpenCustomers;
  final VoidCallback onOpenPromotions;
  final VoidCallback onOpenBanking;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final listedCount =
        products.where((product) => product.whatsappListed).length;
    final steps = [
      _ReadinessStep(
        title: 'Products added',
        body: 'Create the items you sell before building the store.',
        done: products.isNotEmpty,
        actionLabel: 'Add product',
        action: onAddProduct,
      ),
      _ReadinessStep(
        title: 'WhatsApp listing chosen',
        body: listedCount > 0
            ? '$listedCount ${listedCount == 1 ? 'product is' : 'products are'} visible to WhatsApp customers.'
            : 'Turn on WhatsApp listing only for items customers may order. Leave internal stock off.',
        done: listedCount > 0,
        actionLabel: products.isEmpty ? null : 'Choose products',
        action: products.isEmpty ? null : onChooseWhatsAppProduct,
      ),
      _ReadinessStep(
        title: 'Customers ready',
        body:
            'Saved customers are needed for messages, order history, and targeted promotions.',
        done: hasCustomers,
        actionLabel: 'Add customer',
        action: onOpenCustomers,
      ),
      _ReadinessStep(
        title: 'Promotions ready',
        body:
            'Approved WhatsApp templates let you send specials and updates when the store is ready.',
        done: hasApprovedTemplate,
        actionLabel: 'Open Marketing',
        action: onOpenPromotions,
      ),
      _ReadinessStep(
        title: 'Bank account added',
        body:
            'Add banking details before store deposits or withdrawals need to be paid out.',
        done: hasBank,
        actionLabel: 'Add bank',
        action: onOpenBanking,
      ),
    ];

    final completed = steps.where((step) => step.done).length;
    final nextStep = steps.firstWhere(
      (step) => !step.done,
      orElse: () => steps.last,
    );
    final progressText = completed == steps.length
        ? '$completed / ${steps.length} ready. WhatsApp Store setup looks ready.'
        : '$completed / ${steps.length} ready. Next: ${nextStep.title}.';

    return Card(
      margin: EdgeInsets.fromLTRB(
        SizeConfig.imageSizeMultiplier * 2,
        SizeConfig.heightMultiplier,
        SizeConfig.imageSizeMultiplier * 2,
        SizeConfig.heightMultiplier * 1.5,
      ),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.green.withValues(alpha: 0.25)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 3,
            vertical: SizeConfig.heightMultiplier * 0.4,
          ),
          childrenPadding: EdgeInsets.fromLTRB(
            SizeConfig.imageSizeMultiplier * 3,
            0,
            SizeConfig.imageSizeMultiplier * 3,
            SizeConfig.heightMultiplier * 1.5,
          ),
          initiallyExpanded: completed < 2,
          leading: CircleAvatar(
            radius: SizeConfig.imageSizeMultiplier * 5,
            backgroundColor: Colors.green.withValues(alpha: 0.1),
            child: Icon(
              Icons.storefront_outlined,
              color: Colors.green.shade700,
              size: SizeConfig.imageSizeMultiplier * 5,
            ),
          ),
          title: Text(
            'WhatsApp Store readiness',
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.75,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Padding(
            padding: EdgeInsets.only(top: SizeConfig.heightMultiplier * 0.5),
            child: Text(
              loading ? 'Checking setup...' : progressText,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 1.35,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Use this before taking WhatsApp orders: list customer-facing products, keep internal stock unlisted, add customers, promotions, and banking details.',
                style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.45,
                  color: Colors.grey.shade800,
                  height: 1.3,
                ),
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            ...steps.map((step) => _ReadinessStepTile(step: step)),
          ],
        ),
      ),
    );
  }
}

class _ReadinessStepTile extends StatelessWidget {
  const _ReadinessStepTile({required this.step});

  final _ReadinessStep step;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final color = step.done ? Colors.green.shade700 : Colors.grey.shade700;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: SizeConfig.heightMultiplier * 0.7,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            step.done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: color,
            size: SizeConfig.imageSizeMultiplier * 5,
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.55,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 0.2),
                Text(
                  step.body,
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 1.35,
                    color: Colors.grey.shade700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (!step.done && step.action != null && step.actionLabel != null)
            TextButton(onPressed: step.action, child: Text(step.actionLabel!)),
        ],
      ),
    );
  }
}

class _ReadinessStep {
  const _ReadinessStep({
    required this.title,
    required this.body,
    required this.done,
    this.actionLabel,
    this.action,
  });

  final String title;
  final String body;
  final bool done;
  final String? actionLabel;
  final VoidCallback? action;
}
