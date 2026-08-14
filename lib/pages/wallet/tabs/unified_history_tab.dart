import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/notification_tile.dart';
import 'package:pasella/pages/wallet/widgets/top_up_tile.dart';
import 'package:pasella/pages/wallet/widgets/icon_helper.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/config/size_config.dart';

class UnifiedHistoryTab extends StatefulWidget {
  final WalletViewModel viewModel;
  final bool embedded;
  const UnifiedHistoryTab({
    super.key,
    required this.viewModel,
    this.embedded = false,
  });

  @override
  State<UnifiedHistoryTab> createState() => _UnifiedHistoryTabState();
}

class _UnifiedHistoryTabState extends State<UnifiedHistoryTab> {
  late final WalletViewModel _viewModel;
  late Future<List<Map<String, dynamic>>> _transactionsFuture;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel;
    _transactionsFuture = _viewModel.fetchMergedTransactionHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(SizeConfig.heightMultiplier * 1),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _transactionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('Could not load billing history. Please try again.'),
            );
          }

          final merged = snapshot.data ?? [];

          if (merged.isEmpty) {
            return const _EmptyState(
              message: "No money activity yet.",
            );
          }

          return ListView.separated(
            shrinkWrap: widget.embedded,
            physics:
                widget.embedded ? const NeverScrollableScrollPhysics() : null,
            separatorBuilder: (_, __) =>
                const Divider(color: Colors.grey, thickness: .3),
            itemCount: merged.length,
            itemBuilder: (context, index) {
              final item = merged[index];
              final type = item['type'];
              final timestamp = item['timestamp'] as DateTime?;

              if (timestamp == null) return const SizedBox.shrink();

              switch (type) {
                case 'top-up':
                  return TopUpTile(
                    amount: item['amount'] ?? 0,
                    date: timestamp,
                  );

                case 'message':
                  return NotificationTile(
                    message: item['message'] ?? 'Message',
                    messageCost: item['messageCost'] ?? 0,
                    phone: item['phone'] ?? 'Unknown',
                    date: timestamp,
                    templateType: item['templateType'] ?? 'sms',
                  );

                case 'payout':
                  return ListTile(
                    leading: getIconForStatus(item['status']),
                    title: Text(
                      CurrencyUtil.format(item['amount'] ?? 0),
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      DateFormat('dd MMM yyyy, HH:mm').format(timestamp),
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    trailing: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: SizeConfig.blockSizeHorizontal * 2,
                        vertical: SizeConfig.heightMultiplier * 0.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(
                          SizeConfig.blockSizeHorizontal * 2,
                        ),
                      ),
                      child: Text(
                        (item['status'] ?? 'Unknown').toString().toUpperCase(),
                        style: TextStyle(
                          fontSize: SizeConfig.textMultiplier * 1.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  );

                default:
                  return const SizedBox.shrink();
              }
            },
          );
        },
      ),
    );
  }
}

/// 🟢 Empty State Widget
class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.heightMultiplier * 3),
        child: Text(
          message,
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.8,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}
