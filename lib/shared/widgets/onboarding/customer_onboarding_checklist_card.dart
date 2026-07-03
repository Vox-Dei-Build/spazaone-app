import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/utils/template_status.dart';
import 'package:share_plus/share_plus.dart';

class CustomerOnboardingChecklistCard extends StatefulWidget {
  const CustomerOnboardingChecklistCard({
    super.key,
    required this.userId,
    required this.onAddCustomer,
    required this.onChooseWhatsAppProduct,
    required this.onOpenOrderingLink,
    required this.onOpenPromotions,
    required this.onOpenBanking,
  });

  final String userId;
  final VoidCallback onAddCustomer;
  final VoidCallback onChooseWhatsAppProduct;
  final VoidCallback onOpenOrderingLink;
  final VoidCallback onOpenPromotions;
  final VoidCallback onOpenBanking;

  @override
  State<CustomerOnboardingChecklistCard> createState() =>
      _CustomerOnboardingChecklistCardState();
}

class _CustomerOnboardingChecklistCardState
    extends State<CustomerOnboardingChecklistCard> {
  static const _boxName = 'appBox';

  late final String _storeLinkDismissedKey =
      'customer_store_link_card:${widget.userId}:dismissed';

  bool _storeLinkDismissed = false;

  @override
  void initState() {
    super.initState();
    if (widget.userId.isNotEmpty) {
      _storeLinkDismissed = Hive.box(
        _boxName,
      ).get(_storeLinkDismissedKey, defaultValue: false) as bool;
    }
  }

  Future<void> _hideStoreLink() async {
    await Hive.box(_boxName).put(_storeLinkDismissedKey, true);
    if (!mounted) return;
    setState(() => _storeLinkDismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.userId.isEmpty) return const SizedBox.shrink();

    final firestore = FirebaseFirestore.instance;
    final userScope = firestore.collection('users').doc(widget.userId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userScope.snapshots(),
      builder: (context, userSnap) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: userScope.collection('customers').limit(1).snapshots(),
          builder: (context, customerSnap) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: userScope.collection('products').limit(1).snapshots(),
              builder: (context, productSnap) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: userScope
                      .collection('products')
                      .where('whatsappListed', isEqualTo: true)
                      .limit(1)
                      .snapshots(),
                  builder: (context, listedProductSnap) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: userScope
                          .collection('bankingDetails')
                          .limit(1)
                          .snapshots(),
                      builder: (context, bankSnap) {
                        return StreamBuilder<
                            QuerySnapshot<Map<String, dynamic>>>(
                          stream: firestore
                              .collection('messagingTemplates')
                              .where('userId', isEqualTo: widget.userId)
                              .limit(10)
                              .snapshots(),
                          builder: (context, templateSnap) {
                            final userData = userSnap.data?.data();
                            final ordering = userData?['whatsappOrdering'];
                            final orderingData =
                                ordering is Map ? ordering : const {};
                            final orderingCode = _mapString(
                              orderingData,
                              'code',
                            );
                            final storedOrderingUrl = _mapString(
                              orderingData,
                              'orderingUrl',
                            );
                            final pasellaWhatsappNumber = _mapString(
                              orderingData,
                              'pasellaWhatsappNumber',
                            );
                            final orderingUrl = storedOrderingUrl.isNotEmpty
                                ? storedOrderingUrl
                                : _buildOrderingUrl(
                                    code: orderingCode,
                                    pasellaWhatsappNumber:
                                        pasellaWhatsappNumber,
                                  );
                            final fallbackText = _mapString(
                              orderingData,
                              'fallbackText',
                            );
                            final hasOrderingLink =
                                orderingData['status'] == 'active' &&
                                    orderingCode.isNotEmpty;
                            final shopName = _firstNonEmpty([
                              userData?['shopName'],
                              userData?['name'],
                              'your shop',
                            ]);
                            final hasApprovedTemplate =
                                templateSnap.data?.docs.any((doc) {
                                      return templateStatusOf(doc.data()) ==
                                          TemplateStatus.approved;
                                    }) ??
                                    false;

                            return _ChecklistBody(
                              hasCustomers:
                                  customerSnap.data?.docs.isNotEmpty ?? false,
                              hasProducts:
                                  productSnap.data?.docs.isNotEmpty ?? false,
                              hasListedProduct:
                                  listedProductSnap.data?.docs.isNotEmpty ??
                                      false,
                              hasOrderingLink: hasOrderingLink,
                              hasApprovedTemplate: hasApprovedTemplate,
                              hasBank: bankSnap.data?.docs.isNotEmpty ?? false,
                              shopName: shopName,
                              orderingUrl: orderingUrl,
                              orderingCode: orderingCode,
                              fallbackText: fallbackText,
                              storeLinkDismissed: _storeLinkDismissed,
                              loading: userSnap.connectionState ==
                                      ConnectionState.waiting ||
                                  customerSnap.connectionState ==
                                      ConnectionState.waiting ||
                                  productSnap.connectionState ==
                                      ConnectionState.waiting ||
                                  listedProductSnap.connectionState ==
                                      ConnectionState.waiting ||
                                  bankSnap.connectionState ==
                                      ConnectionState.waiting ||
                                  templateSnap.connectionState ==
                                      ConnectionState.waiting,
                              onAddCustomer: widget.onAddCustomer,
                              onChooseWhatsAppProduct:
                                  widget.onChooseWhatsAppProduct,
                              onOpenOrderingLink: widget.onOpenOrderingLink,
                              onOpenPromotions: widget.onOpenPromotions,
                              onOpenBanking: widget.onOpenBanking,
                              onHideStoreLink: () => _hideStoreLink(),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ChecklistBody extends StatelessWidget {
  const _ChecklistBody({
    required this.hasCustomers,
    required this.hasProducts,
    required this.hasListedProduct,
    required this.hasOrderingLink,
    required this.hasApprovedTemplate,
    required this.hasBank,
    required this.shopName,
    required this.orderingUrl,
    required this.orderingCode,
    required this.fallbackText,
    required this.storeLinkDismissed,
    required this.loading,
    required this.onAddCustomer,
    required this.onChooseWhatsAppProduct,
    required this.onOpenOrderingLink,
    required this.onOpenPromotions,
    required this.onOpenBanking,
    required this.onHideStoreLink,
  });

  final bool hasCustomers;
  final bool hasProducts;
  final bool hasListedProduct;
  final bool hasOrderingLink;
  final bool hasApprovedTemplate;
  final bool hasBank;
  final String shopName;
  final String orderingUrl;
  final String orderingCode;
  final String fallbackText;
  final bool storeLinkDismissed;
  final bool loading;
  final VoidCallback onAddCustomer;
  final VoidCallback onChooseWhatsAppProduct;
  final VoidCallback onOpenOrderingLink;
  final VoidCallback onOpenPromotions;
  final VoidCallback onOpenBanking;
  final VoidCallback onHideStoreLink;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final steps = [
      _ChecklistStep(
        title: 'First customer saved',
        body: hasCustomers
            ? 'Customer capture is ready for transactions, orders, and follow-up.'
            : 'Save one real customer before setting up the rest.',
        done: hasCustomers,
        actionLabel: 'Add customer',
        action: onAddCustomer,
        icon: Icons.person_add_alt_1_outlined,
      ),
      _ChecklistStep(
        title: 'First product added',
        body: hasProducts
            ? 'Products can now support item-level sales and orders.'
            : 'Add the product customers buy most often before setup moves to ordering or marketing.',
        done: hasProducts,
        actionLabel: 'Add product',
        action: onChooseWhatsAppProduct,
        icon: Icons.inventory_2_outlined,
      ),
      _ChecklistStep(
        title: 'WhatsApp products chosen',
        body: hasListedProduct
            ? 'Customer-facing products are visible for WhatsApp orders.'
            : hasProducts
                ? 'Choose which products customers can order on WhatsApp.'
                : 'Available after a product exists.',
        done: hasListedProduct,
        actionLabel: hasProducts ? 'Choose products' : null,
        action: hasProducts ? onChooseWhatsAppProduct : null,
        icon: Icons.storefront_outlined,
      ),
      _ChecklistStep(
        title: 'Ordering link ready',
        body: hasOrderingLink
            ? 'Your customer ordering link is ready to share.'
            : hasProducts
                ? 'Generate the link customers use to place orders.'
                : 'Available after a product exists.',
        done: hasOrderingLink,
        actionLabel: hasOrderingLink
            ? 'View link'
            : hasProducts
                ? 'Get link'
                : null,
        action: hasProducts ? onOpenOrderingLink : null,
        icon: Icons.link_outlined,
      ),
      _ChecklistStep(
        title: 'Payout details added',
        body: hasBank
            ? 'Banking details are saved for payouts.'
            : 'Add banking details before deposits or withdrawals.',
        done: hasBank,
        actionLabel: 'Add bank',
        action: onOpenBanking,
        icon: Icons.account_balance_outlined,
      ),
      _ChecklistStep(
        title: 'Promotion template approved',
        body: hasApprovedTemplate
            ? 'Marketing messages are ready when you need them.'
            : hasProducts
                ? 'Open Marketing to get a WhatsApp template approved.'
                : 'Available after a product exists.',
        done: hasApprovedTemplate,
        actionLabel: hasProducts ? 'Open Marketing' : null,
        action: hasProducts ? onOpenPromotions : null,
        icon: Icons.campaign_outlined,
      ),
    ];

    final completed = steps.where((step) => step.done).length;
    final actionableSteps =
        steps.where((step) => !step.done && step.action != null).toList();
    final nextStep = actionableSteps.isEmpty ? null : actionableSteps.first;
    final allDone = completed == steps.length;
    final progress = completed / steps.length;

    if (allDone && storeLinkDismissed) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.fromLTRB(
        SizeConfig.imageSizeMultiplier * 2,
        SizeConfig.heightMultiplier * 0.8,
        SizeConfig.imageSizeMultiplier * 2,
        SizeConfig.heightMultiplier * 1.2,
      ),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.green.withValues(alpha: 0.22)),
      ),
      child: allDone
          ? _StoreLinkCard(
              shopName: shopName,
              orderingUrl: orderingUrl,
              orderingCode: orderingCode,
              fallbackText: fallbackText,
              onOpenOrderingLink: onOpenOrderingLink,
              onHide: onHideStoreLink,
            )
          : _SetupProgressCard(
              loading: loading,
              completed: completed,
              total: steps.length,
              progress: progress,
              nextStep: nextStep,
              steps: steps,
            ),
    );
  }
}

class _SetupProgressCard extends StatelessWidget {
  const _SetupProgressCard({
    required this.loading,
    required this.completed,
    required this.total,
    required this.progress,
    required this.nextStep,
    required this.steps,
  });

  final bool loading;
  final int completed;
  final int total;
  final double progress;
  final _ChecklistStep? nextStep;
  final List<_ChecklistStep> steps;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.imageSizeMultiplier * 2.5,
        SizeConfig.imageSizeMultiplier * 3,
        SizeConfig.imageSizeMultiplier * 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.checklist_rtl_outlined,
                  color: Colors.green.shade700,
                  size: 22,
                ),
              ),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2.5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Customer setup',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.65,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loading
                          ? 'Checking setup...'
                          : '$completed of $total done',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.25,
                        color: Colors.grey.shade700,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              _ProgressPill(completed: completed, total: total),
            ],
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 1),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.green.shade700,
              ),
            ),
          ),
          if (nextStep != null) ...[
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            _NextActionPanel(step: nextStep!),
          ],
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              title: Text(
                'Show setup steps',
                style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.3,
                  fontWeight: FontWeight.w800,
                  color: Colors.green.shade700,
                ),
              ),
              children: [
                ...steps.map((step) => _ChecklistStepRow(step: step)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreLinkCard extends StatelessWidget {
  const _StoreLinkCard({
    required this.shopName,
    required this.orderingUrl,
    required this.orderingCode,
    required this.fallbackText,
    required this.onOpenOrderingLink,
    required this.onHide,
  });

  final String shopName;
  final String orderingUrl;
  final String orderingCode;
  final String fallbackText;
  final VoidCallback onOpenOrderingLink;
  final VoidCallback onHide;

  String get _copyValue {
    if (orderingUrl.isNotEmpty) return orderingUrl;
    if (orderingCode.isNotEmpty) return 'shop $orderingCode';
    return '';
  }

  String get _shareMessage {
    return [
      'You can order from $shopName on WhatsApp:',
      orderingUrl,
      '',
      'Open the link to place an order.',
      if (fallbackText.isNotEmpty) fallbackText,
    ].whereType<String>().where((line) => line.trim().isNotEmpty).join('\n');
  }

  Future<void> _copy(BuildContext context) async {
    if (_copyValue.isEmpty) {
      onOpenOrderingLink();
      return;
    }
    await Clipboard.setData(ClipboardData(text: _copyValue));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Order link copied.')));
  }

  Future<void> _share() async {
    if (_shareMessage.trim().isEmpty) {
      onOpenOrderingLink();
      return;
    }
    await Share.share(_shareMessage);
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final green = Colors.green.shade700;
    final linkLabel =
        orderingUrl.isNotEmpty ? orderingUrl : 'shop $orderingCode';

    return Padding(
      padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  FontAwesomeIcons.whatsapp,
                  color: green,
                  size: 20,
                ),
              ),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2.5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order link ready',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.65,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Share this with anyone so they can place an order.',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.25,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Hide',
                onPressed: onHide,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 1),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 2.5,
              vertical: SizeConfig.heightMultiplier * 0.9,
            ),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(Icons.link, color: Colors.grey.shade700, size: 20),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                Expanded(
                  child: Text(
                    linkLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (orderingCode.isNotEmpty) ...[
                  SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      orderingCode,
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 1),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copy(context),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({required this.completed, required this.total});

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.green.withValues(alpha: 0.24)),
      ),
      child: Text(
        '$completed/$total',
        style: TextStyle(
          color: Colors.green.shade800,
          fontSize: SizeConfig.textMultiplier * 1.1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _NextActionPanel extends StatelessWidget {
  const _NextActionPanel({required this.step});

  final _ChecklistStep step;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Container(
      padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 2.5),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(step.icon, color: Colors.green.shade700, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next: ${step.title}',
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.45,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      step.body,
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.3,
                        color: Colors.grey.shade800,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 1),
          ElevatedButton(
            onPressed: step.action,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(step.actionLabel!),
          ),
        ],
      ),
    );
  }
}

class _ChecklistStepRow extends StatelessWidget {
  const _ChecklistStepRow({required this.step});

  final _ChecklistStep step;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final color = step.done ? Colors.green.shade700 : Colors.grey.shade600;

    return InkWell(
      onTap: step.done ? null : step.action,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: SizeConfig.heightMultiplier * 0.65,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              step.done ? Icons.check_circle : step.icon,
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
                      fontSize: SizeConfig.textMultiplier * 1.45,
                      fontWeight: FontWeight.w800,
                      color: step.done ? Colors.grey.shade700 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.body,
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.25,
                      color: Colors.grey.shade700,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            if (!step.done && step.action != null)
              Icon(Icons.chevron_right, color: Colors.grey.shade500, size: 20),
          ],
        ),
      ),
    );
  }
}

class _ChecklistStep {
  const _ChecklistStep({
    required this.title,
    required this.body,
    required this.done,
    required this.actionLabel,
    required this.action,
    required this.icon,
  });

  final String title;
  final String body;
  final bool done;
  final String? actionLabel;
  final VoidCallback? action;
  final IconData icon;
}

String _mapString(Map<dynamic, dynamic> map, String key) {
  final value = map[key];
  return value is String ? value.trim() : '';
}

String _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _buildOrderingUrl({
  required String code,
  required String pasellaWhatsappNumber,
}) {
  final digitsOnly = pasellaWhatsappNumber.replaceAll(RegExp(r'\D'), '');
  if (code.isEmpty || digitsOnly.isEmpty) return '';
  return 'https://wa.me/$digitsOnly?text=${Uri.encodeComponent('shop $code')}';
}
