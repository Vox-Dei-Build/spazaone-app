import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:provider/provider.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:intl/intl.dart';

import 'view_template/template_detail_page.dart';

class TemplatesTab extends StatefulWidget {
  const TemplatesTab({Key? key}) : super(key: key);

  @override
  State<TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends State<TemplatesTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewModel =
          Provider.of<PromotionsViewModel>(context, listen: false);
      viewModel.fetchTemplates();
      viewModel.fetchMessageShopName();
      viewModel.initializePricing();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<PromotionsViewModel>(context);

    if (viewModel.loadingTemplates) {
      return const Center(child: CircularProgressIndicator());
    }

    final templates = viewModel.templates;

    if (templates.isEmpty) {
      return const Center(child: Text("No templates found."));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: templates.length,
      itemBuilder: (context, index) {
        final template = templates[index];
        final name = template['name'] ?? "Untitled";
        final contentType = template['contentType'] ?? "Unknown";
        final channels = template['channels'] as Map<String, dynamic>? ?? {};
        final createdAt = template['createdAt']?.toDate();
        final formattedDate = createdAt != null
            ? DateFormat('MMM dd, yyyy').format(createdAt)
            : "Unknown";

        final channelKeys =
            channels.keys.map((key) => key.toUpperCase()).join(', ');
        final whatsappStatus = channels['whatsapp']?['approved'] == true
            ? 'Approved ✅'
            : 'Pending ⏳';
        final mediaUrl = channels['whatsapp']?['mediaUrl'];

        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TemplateDetailPage(
                    viewModel: viewModel,
                    template: template,
                    shopName: viewModel.shopName,
                    whatsappPrice: viewModel.whatsappPrice,
                    smsPricePerSegment: viewModel.smsPricePerSegment,
                  ),
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
                        Text(name,
                            style: TextStyle(
                                fontSize: SizeConfig.textMultiplier * 2,
                                fontWeight: FontWeight.bold)),
                        SizedBox(height: SizeConfig.heightMultiplier * 0.2),
                        Text("Type: $contentType",
                            style: const TextStyle(color: Colors.grey)),
                        Text("Channels: $channelKeys",
                            style: const TextStyle(color: Colors.grey)),
                        if (channels.containsKey('whatsapp'))
                          Text("Status: $whatsappStatus",
                              style: const TextStyle(color: Colors.green)),
                        Text("Created: $formattedDate",
                            style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
