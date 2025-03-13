import 'package:flutter/material.dart';

class CashAdvanceTab extends StatelessWidget {
  const CashAdvanceTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.request_quote),
        label: const Text('Request Cash Advance'),
        onPressed: () {
          // Handle cash advance requests here
        },
      ),
    );
  }
}
