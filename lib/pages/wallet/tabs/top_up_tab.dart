import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
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
            CustomButton(
              title: 'Top up via Paystack',
              onTap: () => walletVM.openPaystackForm(context),
              color: Colors.green,
              fontSize: SizeConfig.textMultiplier * 2,
              width: SizeConfig.imageSizeMultiplier * 60,
            ),

          SizedBox(height: SizeConfig.heightMultiplier * 2),

          CustomButton(
            title: 'Top up via WhatsApp',
            onTap: () => walletVM.sendTopUpWhatsAppMessage(context),
            color: Colors.green,
            icon: Icons.chat,
            fontSize: SizeConfig.textMultiplier * 2,
            width: SizeConfig.imageSizeMultiplier * 60,
          ),
        ],
      ),
    );
  }
}
