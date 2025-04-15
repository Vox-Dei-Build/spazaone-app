import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pasella/pages/promotions/view_model/promotions_view_model.dart';
import 'package:intl/intl.dart';

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
      itemCount: templates.length,
      itemBuilder: (context, index) {
        final template = templates[index];
        final name = template['name'] ?? "Untitled";
        final contentType = template['contentType'] ?? "Unknown";
        final channels = template['channels'] as Map<String, dynamic>? ?? {};
        final createdAt = template['createdAt']?.toDate();
        final formattedDate = createdAt != null
            ? DateFormat('yyyy-MM-dd').format(createdAt)
            : "Unknown";

        final channelKeys = channels.keys.join(', ');
        final whatsappStatus =
            channels['whatsapp']?['approved'] == true ? 'Approved' : 'Pending';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: ListTile(
            title: Text(name),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Type: $contentType"),
                Text("Channel: $channelKeys"),
                if (channels.containsKey('whatsapp'))
                  Text("Status: $whatsappStatus"),
                Text("Created: $formattedDate"),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                // TODO: Navigate to edit page
              },
            ),
          ),
        );
      },
    );
  }
}
