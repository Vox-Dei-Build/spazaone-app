import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/pages/wallet/view_model/wallet_view_model.dart';
import 'package:pasella/pages/wallet/widgets/notification_tile.dart';
import 'package:pasella/pages/wallet/widgets/top_up_tile.dart';
import 'package:pasella/pages/wallet/widgets/icon_helper.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/wallet/widgets/wallet_activity_tile.dart';
import 'package:pasella/shared/widgets/spaza_shimmer.dart';

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
      padding: const EdgeInsets.all(8),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _transactionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _WalletHistoryLoading();
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

          return WalletHistoryList(entries: merged, embedded: widget.embedded);
        },
      ),
    );
  }
}

/// Already-loaded wallet history; amounts and statuses are provided by the ledger.
class WalletHistoryList extends StatelessWidget {
  const WalletHistoryList(
      {super.key, required this.entries, this.embedded = false});

  final List<Map<String, dynamic>> entries;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final item = entries[index];
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
            return WalletActivityTile(
              icon: getIconForStatus(item['status']),
              title: 'Payout',
              amount: CurrencyUtil.format(
                  (item['amount'] as num?)?.toDouble() ?? 0),
              subtitle: DateFormat('dd MMM yyyy, HH:mm').format(timestamp),
              status: (item['status'] ?? 'Unknown').toString().toUpperCase(),
            );

          default:
            return const SizedBox.shrink();
        }
      },
    );
  }
}

class _WalletHistoryLoading extends StatelessWidget {
  const _WalletHistoryLoading();

  @override
  Widget build(BuildContext context) => SpazaShimmer(
        key: const ValueKey('wallet-history-loading-shimmer'),
        semanticsLabel: 'Loading wallet activity',
        child: Column(
          children: [
            for (var index = 0; index < 5; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  height: 68,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(SpazaRadius.surface),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// 🟢 Empty State Widget
class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: const TextStyle(
            fontSize: 16,
            color: SpazaColors.muted,
          ),
        ),
      ),
    );
  }
}
