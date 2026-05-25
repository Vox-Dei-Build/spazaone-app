import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart'; // ✅ NEW
import 'package:pasella/pages/wallet/tabs/banking_details_tab.dart';
import 'package:pasella/pages/wallet/tabs/pricing_tab.dart';
import 'package:pasella/pages/wallet/tabs/unified_history_tab.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/utils/feature_flags.dart';

enum InfoView { history, banking, info }

class InfoCenterTab extends StatefulWidget {
  final WalletViewModel walletVM;
  final InfoView? initialView;

  const InfoCenterTab({super.key, required this.walletVM, this.initialView});

  @override
  State<InfoCenterTab> createState() => _InfoCenterTabState();
}

class _InfoCenterTabState extends State<InfoCenterTab> {
  late InfoView _selected;

  @override
  void initState() {
    super.initState();
    _selected =
        _isEnabled(widget.initialView) ? widget.initialView! : _initialView();
  }

  InfoView _initialView() {
    if (FeatureFlags.enableTransactionHistory) return InfoView.history;
    if (FeatureFlags.enableBankingDetails) return InfoView.banking;
    return InfoView.info;
  }

  bool _isEnabled(InfoView? view) {
    switch (view) {
      case InfoView.history:
        return FeatureFlags.enableTransactionHistory;
      case InfoView.banking:
        return FeatureFlags.enableBankingDetails;
      case InfoView.info:
        return FeatureFlags.enablePricingInfo;
      case null:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context); // ✅ ensure SizeConfig is available

    final labelStyle = TextStyle(
      // ✅ matches Sales tab
      fontSize: SizeConfig.textMultiplier * 1.5,
      fontWeight: FontWeight.bold,
    );
    final iconSize = SizeConfig.textMultiplier * 1.5; // ✅ matches Sales tab

    final segments = <ButtonSegment<InfoView>>[];

    if (FeatureFlags.enableTransactionHistory) {
      segments.add(
        ButtonSegment(
          value: InfoView.history,
          label: Text('History', style: labelStyle), // ✅
          icon: Icon(Icons.history, size: iconSize), // ✅
        ),
      );
    }
    if (FeatureFlags.enableBankingDetails) {
      segments.add(
        ButtonSegment(
          value: InfoView.banking,
          label: Text('Banking', style: labelStyle), // ✅
          icon: Icon(Icons.account_balance, size: iconSize), // ✅
        ),
      );
    }
    if (FeatureFlags.enablePricingInfo) {
      segments.add(
        ButtonSegment(
          value: InfoView.info,
          label: Text('Info', style: labelStyle), // ✅
          icon: Icon(Icons.info_outline, size: iconSize), // ✅
        ),
      );
    }

    if (segments.isEmpty) {
      return const Center(child: Text('No information available'));
    }

    Widget contentFor(InfoView view) {
      switch (view) {
        case InfoView.history:
          return UnifiedHistoryTab(viewModel: widget.walletVM);
        case InfoView.banking:
          return const BankingDetailsTab();
        case InfoView.info:
          return const PricingInfoTab();
      }
    }

    if (segments.length == 1) {
      return contentFor(segments.first.value);
    }

    return Column(
      children: [
        const SizedBox(height: 16), // ✅ same top spacing as Sales
        Theme(
          data: Theme.of(context).copyWith(
            segmentedButtonTheme: SegmentedButtonThemeData(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Colors.green
                      : Colors.white,
                ),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? Colors.white
                      : Colors.black87,
                ),
              ),
            ),
          ),
          child: SegmentedButton<InfoView>(
            segments: segments,
            selected: <InfoView>{_selected},
            onSelectionChanged: (selection) {
              setState(() => _selected = selection.first);
            },
          ),
        ),
        const SizedBox(height: 16), // optional: mirrors Sales layout rhythm
        Expanded(child: contentFor(_selected)),
      ],
    );
  }
}
