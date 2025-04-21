import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/pages/promote/view_model/promotions_view_model.dart';
import 'package:provider/provider.dart';

class PromotionsTab extends StatefulWidget {
  const PromotionsTab({Key? key}) : super(key: key);

  @override
  State<PromotionsTab> createState() => _PromotionsTabState();
}

class _PromotionsTabState extends State<PromotionsTab> {
  List<Map<String, dynamic>> promotions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final viewModel =
          Provider.of<PromotionsViewModel>(context, listen: false);
      final results = await viewModel.fetchPromotionsReports(viewModel.userId);
      setState(() {
        promotions = results;
        loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (promotions.isEmpty) {
      return const Center(child: Text("No promotions found."));
    }

    return ListView.builder(
      itemCount: promotions.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final promo = promotions[index];
        final createdAt = promo['createdAt']?.toDate();
        final formattedDate = createdAt != null
            ? DateFormat('MMM dd, yyyy • hh:mm a').format(createdAt)
            : "Unknown";
        final status = promo['status'] ?? 'unknown';
        final isTest = promo['testMode'] == true;
        final customersCount = (promo['customerIds'] as List?)?.length ?? 0;
        final templateId = promo['templateId'] ?? 'N/A';

        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: ListTile(
            title: Text("Promo to $customersCount customers",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Status: ${status.toUpperCase()}"),
                Text("Created: $formattedDate"),
                if (isTest)
                  const Text("Test Mode",
                      style: TextStyle(color: Colors.orange)),
              ],
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Later: navigate to detailed promo view if needed
            },
          ),
        );
      },
    );
  }
}
