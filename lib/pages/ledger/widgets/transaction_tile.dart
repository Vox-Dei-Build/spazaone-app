import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/contact/contact_management.dart';
import 'package:pasella/shared/widgets/channel_capability_badge.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/widgets/private_region.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.color,
    required this.name,
    required this.amount,
    required this.remarks,
    required this.status,
    required this.type,
    required this.date,
    required this.selectedCustomerId,
    required this.balance,
    this.isNPA,
    this.number,
    this.profileImageUrl, // Add profileImageUrl
    required this.unreadCount,
    this.hasWhatsApp,
    this.showChannelCapability = false,
    this.onTap,
  });

  final int color;
  final String name;
  final double amount;
  final String remarks;
  final String type;
  final String status;
  final String date;
  final String selectedCustomerId;
  final double balance;
  final bool? isNPA;
  final String? number;
  final String? profileImageUrl; // Add profileImageUrl
  final int? unreadCount;
  final bool? hasWhatsApp;
  final bool showChannelCapability;

  /// Optional navigation callback, also used by local presentation previews.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = unreadCount ?? 0;
    void openCustomer() => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CustomerManagementPage(
              customerName: name,
              customerId: selectedCustomerId,
              mobileNumber: number,
            ),
          ),
        );
    SizeConfig().init(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? openCustomer,
        // Keep customer names and balances masked in replay recordings.
        child: PrivateRegion(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: LayoutBuilder(builder: (context, constraints) {
                  // Keep production's simple list at ordinary sizes. Larger
                  // text gets its own balance line instead of shrinking money.
                  final stack = constraints.maxWidth < 280 ||
                      MediaQuery.textScalerOf(context).scale(14.5) > 21;
                  final balanceDetails = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: stack
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyUtil.format(balance.abs()),
                        key: const ValueKey('customer-row-balance'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 14.5,
                          color: balance < 0
                              ? Colors.orange.shade800
                              : kPrimaryColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(balance < 0 ? 'Owes you' : 'Paid up',
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12, color: kSecondaryAccent)),
                    ],
                  );
                  final identity = Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            maxLines: stack ? null : 1,
                            overflow: stack ? null : TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontSize: 14.5)),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 6),
                        Semantics(
                          label: '$unread unread messages and orders',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: kPrimaryColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('$unread',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: Colors.white)),
                          ),
                        ),
                      ],
                    ],
                  );
                  return Row(
                    crossAxisAlignment: stack
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      SizedBox.square(
                        dimension: 44,
                        child: Stack(clipBehavior: Clip.none, children: [
                          profilePicture(
                              context, name, profileImageUrl, number, isNPA,
                              displayIcons: !showChannelCapability,
                              balance: balance,
                              showNPAIndicator: false,
                              radius: 22),
                          if (showChannelCapability)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: ChannelCapabilityBadge(
                                hasNumber: number != null && number!.isNotEmpty,
                                hasWhatsApp: hasWhatsApp,
                                compact: true,
                                iconSize: 12,
                              ),
                            ),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            identity,
                            const SizedBox(height: 2),
                            Text(_subtitle,
                                maxLines: stack ? null : 1,
                                overflow: stack ? null : TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: kSecondaryAccent)),
                            if (stack) ...[
                              const SizedBox(height: 8),
                              balanceDetails,
                            ],
                          ],
                        ),
                      ),
                      if (!stack) ...[
                        const SizedBox(width: 12),
                        // Bound unusually large balances so the identity keeps
                        // usable space; money wraps rather than disappearing.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * .42),
                          child: balanceDetails,
                        ),
                      ],
                    ],
                  );
                }),
              ),
              const Divider(height: 1),
            ],
          ),
        ),
      ),
    );
  }

  String get _subtitle {
    if (showChannelCapability && number != null && number!.isNotEmpty) {
      final channel = hasWhatsApp == true
          ? 'WhatsApp'
          : hasWhatsApp == false
              ? 'SMS'
              : 'Phone';
      return '$channel · $number';
    }
    if (remarks == 'No transactions yet') return 'No activity yet';
    final displayType = type == 'Credit' ? 'Transaction' : type;
    return '${CurrencyUtil.format(amount)} · $displayType · $date';
  }
}
