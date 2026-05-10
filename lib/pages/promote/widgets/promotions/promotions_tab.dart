// promotions_tab.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:pasella/pages/promote/widgets/promotions/view_promotion/view_promotion.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pasella/utils/text_sanitizer.dart';

class PromotionsTab extends StatefulWidget {
  const PromotionsTab({Key? key}) : super(key: key);

  @override
  State<PromotionsTab> createState() => _PromotionsTabState();
}

class _PromotionsTabState extends State<PromotionsTab> {
  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<PromotionsViewModel>(context);
    if (vm.loadingPromotions) {
      return const Center(child: CircularProgressIndicator());
    }
    final promos = vm.promotionsReports;
    if (promos.isEmpty) {
      return const Center(child: Text("No saved promotions."));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: promos.length,
      itemBuilder: (ctx, i) {
        final promo = promos[i];
        final created = (promo['createdAt'] as Timestamp).toDate();
        final date = DateFormat('MMM dd, yyyy').format(created);
        final status = sanitizeMalformedUtf16(promo['status'] as String? ?? '');
        // PAS-UX-11: 'saved' is the audit's saved-but-unsent state.
        // Surface it more strongly than the rest because every other
        // state on this list is terminal (processing/sent), but a
        // saved promotion is sitting there waiting for the merchant
        // to come back and pay+send. Without an explicit affordance
        // they were getting lost in the list.
        final isPendingSend = status == 'saved';
        final statusColor = isPendingSend
            ? Colors.blue
            : status == 'processing'
                ? Colors.orange
                : Colors.green;

        // lookup template name
        final templateId = promo['templateId'] as String;
        final template = vm.templates.firstWhere(
          (t) => t['id'] == templateId,
          orElse: () => {},
        );

        final channels = template['channels'] as Map<String, dynamic>? ?? {};
        final name = sanitizeMalformedUtf16(template['name'] as String? ?? '–');
        final mediaUrl = channels['whatsapp']?['mediaUrl'];
        final total = promos.length;
        final displayIndex = total - i;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ViewPromotionPage(viewModel: vm, promo: promo),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (mediaUrl != null && mediaUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        mediaUrl,
                        height: 80,
                        width: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image, size: 80),
                      ),
                    )
                  else
                    Container(
                      height: 80,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.description,
                          size: 40, color: Colors.grey),
                    ),
                  SizedBox(width: SizeConfig.imageSizeMultiplier * 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                sanitizeMalformedUtf16(
                                    'Promotion $displayIndex: $name'),
                                style: TextStyle(
                                  fontSize: SizeConfig.textMultiplier * 1.8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // PAS-UX-11: pending-send chip. Inline
                            // 'Send now' is intentionally a tap on
                            // the whole card (which already opens
                            // the detail page where the existing
                            // WalletAffordabilityFooter handles the
                            // pay+send flow). A second tap target
                            // here would have to duplicate the
                            // affordability check, which the audit
                            // explicitly warned against.
                            if (isPendingSend)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius:
                                      BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.schedule_send,
                                        size: 12,
                                        color: Colors.blue.shade700),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Pending send',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: SizeConfig.heightMultiplier * 0.3),
                        RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 1.5,
                              color:
                                  Theme.of(context).textTheme.bodyLarge!.color,
                            ),
                            children: [
                              const TextSpan(text: "Status: "),
                              TextSpan(
                                text: status.isNotEmpty
                                    ? sanitizeMalformedUtf16(
                                        '${status[0].toUpperCase()}${status.substring(1)}',
                                      )
                                    : status,
                                style: TextStyle(color: statusColor),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: SizeConfig.heightMultiplier * 0.2),
                        Text(
                          "Date: $date",
                          style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 1.5,
                          ),
                        ),
                        if (isPendingSend) ...[
                          SizedBox(height: SizeConfig.heightMultiplier * 0.5),
                          Row(
                            children: [
                              Icon(Icons.send,
                                  size: 14, color: Colors.blue.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Tap to review and send',
                                style: TextStyle(
                                  fontSize: SizeConfig.textMultiplier * 1.4,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
