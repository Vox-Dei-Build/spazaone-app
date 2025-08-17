import 'package:flutter/material.dart';
import 'package:pasella/pages/wallet/tabs/banking_details_tab.dart';
import 'package:pasella/pages/wallet/tabs/pricing_tab.dart';
import 'package:pasella/pages/wallet/tabs/unified_history_tab.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/utils/feature_flags.dart';

enum InfoView { history, banking, info }

class InfoCenterTab extends StatefulWidget {
  final WalletViewModel walletVM;
  const InfoCenterTab({super.key, required this.walletVM});

  @override
  State<InfoCenterTab> createState() => _InfoCenterTabState();
}

class _InfoCenterTabState extends State<InfoCenterTab> {
  late InfoView _selected;

  @override
  void initState() {
    super.initState();
    _selected = _initialView();
  }

  InfoView _initialView() {
    if (FeatureFlags.enableTransactionHistory) return InfoView.history;
    if (FeatureFlags.enableBankingDetails) return InfoView.banking;
    return InfoView.info;
  }

  @override
  Widget build(BuildContext context) {
    final segments = <ButtonSegment<InfoView>>[];

    if (FeatureFlags.enableTransactionHistory) {
      segments.add(const ButtonSegment(
        value: InfoView.history,
        label: Text('Transaction History'),
        icon: Icon(Icons.history),
      ));
    }
    if (FeatureFlags.enableBankingDetails) {
      segments.add(const ButtonSegment(
        value: InfoView.banking,
        label: Text('Banking Details'),
        icon: Icon(Icons.account_balance),
      ));
    }
    if (FeatureFlags.enablePricingInfo) {
      segments.add(const ButtonSegment(
        value: InfoView.info,
        label: Text('Info'),
        icon: Icon(Icons.info_outline),
      ));
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
        Theme(
          data: Theme.of(context).copyWith(
            segmentedButtonTheme: SegmentedButtonThemeData(
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.resolveWith(
                  (states) => states.contains(MaterialState.selected)
                      ? Colors.green
                      : Colors.white,
                ),
                foregroundColor: MaterialStateProperty.resolveWith(
                  (states) => states.contains(MaterialState.selected)
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
        Expanded(child: contentFor(_selected)),
      ],
    );
  }
}
