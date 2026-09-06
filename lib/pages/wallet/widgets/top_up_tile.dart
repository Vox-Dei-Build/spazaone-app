import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/wallet/widgets/wallet_activity_tile.dart';
import 'package:pasella/utils/currency_util.dart';

/// Displays money added to the merchant's SpazaOne balance.
class TopUpTile extends StatelessWidget {
  final num amount;
  final DateTime date;

  const TopUpTile({super.key, required this.amount, required this.date});

  @override
  Widget build(BuildContext context) => WalletActivityTile(
        icon: const Icon(Icons.south_west_rounded,
            color: SpazaColors.action, size: 22),
        title: 'Money added',
        subtitle: DateFormat.yMMMd().format(date),
        amount: '+${CurrencyUtil.format(amount.toDouble())}',
        amountColor: SpazaColors.action,
      );
}
