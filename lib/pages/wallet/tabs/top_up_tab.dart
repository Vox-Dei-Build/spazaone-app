import 'package:flutter/material.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';

class TopUpTab extends StatelessWidget {
  const TopUpTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final WalletViewModel walletVM = WalletViewModel();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🔥 Feature-flagged Paystack button
          if (FeatureFlags.enableTopUpPaystack)
            ElevatedButton(
              onPressed: () => walletVM.openPaystackForm(context),
              child: const Text("Top Up with Paystack"),
            ),

          const SizedBox(height: 16), // Spacing between buttons

          // 🟢 Always show WhatsApp button
          ElevatedButton.icon(
            icon: const Icon(Icons.chat, color: Colors.white),
            label: const Text(
              "Top Up via WhatsApp",
              style: TextStyle(color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            onPressed: () => walletVM.sendWhatsAppMessage(context),
          ),
        ],
      ),
    );
  }
}
