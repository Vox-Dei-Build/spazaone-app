import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/contact/contact_management.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/date_util.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/widgets/private_region.dart';

class CustomersWithBadLoansTile extends StatelessWidget {
  final Future<List<dynamic>>? customersWithBadLoansFuture;

  const CustomersWithBadLoansTile({
    super.key,
    required this.customersWithBadLoansFuture,
  });

  bool reminderSentRecently(customer) {
    if (customer['lastReminderSent'] != null) {
      DateTime? lastReminderSent = convertMapToDateTime(
        customer['lastReminderSent'],
      );
      if (lastReminderSent == null) return false;
      return DateTime.now().difference(lastReminderSent).inDays <= 30;
    } else {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return FutureBuilder<List<dynamic>>(
      future: customersWithBadLoansFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return const Text('Could not load customer details.');
        } else {
          final customers = List<dynamic>.of(snapshot.data!)
            ..sort((a, b) => a['balance'].compareTo(b['balance']));
          return Column(
            children: customers.map((customer) {
              final balance = (customer['balance'] as num).toDouble();
              final name = customer['name'].toString();
              final number = customer['number']?.toString();
              final id = customer['id'].toString();
              final profileImageUrl = customer['profileImageUrl']?.toString();
              const avatarSize = 40.0;
              final wasReminded = reminderSentRecently(customer);
              final stack = MediaQuery.sizeOf(context).width < 360 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20;
              final amount = Text(CurrencyUtil.format(balance),
                  style: TextStyle(
                      color: balance >= 0 ? kPrimaryColor : Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5));

              return Padding(
                padding: EdgeInsets.zero,
                child: PrivateRegion(
                  child: Material(
                    key: ValueKey('customer-follow-up-$id'),
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(SpazaRadius.control),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(SpazaRadius.control),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CustomerManagementPage(
                            customerName: name,
                            customerId: id,
                            mobileNumber: number,
                          ),
                        ),
                      ),
                      child: Ink(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                        decoration: const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(color: SpazaColors.border)),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: avatarSize,
                              height: avatarSize,
                              child: profilePicture(
                                context,
                                name,
                                profileImageUrl,
                                number,
                                true,
                                displayIcons: false,
                                radius: avatarSize / 2,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    name,
                                    maxLines: stack ? null : 1,
                                    overflow:
                                        stack ? null : TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: SpazaColors.heading,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  SizedBox(
                                    height: SizeConfig.heightMultiplier * 0.4,
                                  ),
                                  _buildContactLine(
                                    number,
                                    wasReminded: wasReminded,
                                    allowWrap: stack,
                                  ),
                                  if (stack) ...[
                                    const SizedBox(height: 4),
                                    amount,
                                  ],
                                ],
                              ),
                            ),
                            if (!stack) ...[
                              const SizedBox(width: 8),
                              ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 118),
                                  child: amount),
                            ],
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: SpazaColors.muted,
                              size: 18,
                              applyTextScaling: false,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        }
      },
    );
  }

  Widget _buildContactLine(
    String? number, {
    required bool wasReminded,
    required bool allowWrap,
  }) {
    final raw = (number ?? '').trim();
    if (raw.isEmpty) {
      return Row(
        children: [
          const Icon(
            Icons.phone_disabled_outlined,
            color: SpazaColors.muted,
            size: 14,
            applyTextScaling: false,
          ),
          const SizedBox(width: 5),
          Expanded(
              child: Text(
            'No phone number',
            maxLines: allowWrap ? null : 1,
            overflow: allowWrap ? null : TextOverflow.ellipsis,
            style: const TextStyle(color: SpazaColors.muted, fontSize: 13),
          )),
        ],
      );
    }

    final formatted = formatPhoneNumber(raw);
    final isValid = formatted.isNotEmpty;
    final phoneLabel = isValid ? formatted : raw;
    final reminderTooltip = wasReminded
        ? 'Reminder sent in the last 30 days'
        : 'No reminder in the last 30 days';

    return Row(
      children: [
        Icon(
          isValid ? Icons.phone_outlined : Icons.warning_amber_rounded,
          color: isValid ? SpazaColors.muted : Colors.orange.shade700,
          size: 14,
          applyTextScaling: false,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            phoneLabel,
            maxLines: allowWrap ? null : 1,
            overflow: allowWrap ? null : TextOverflow.ellipsis,
            style: TextStyle(
              color: isValid ? SpazaColors.muted : Colors.orange.shade800,
              fontSize: 13,
              letterSpacing: 0.1,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Tooltip(
          message: reminderTooltip,
          triggerMode: TooltipTriggerMode.tap,
          child: Icon(
            wasReminded
                ? Icons.notifications_active_outlined
                : Icons.notifications_none_outlined,
            color: wasReminded ? kPrimaryColor : SpazaColors.muted,
            size: 16,
            applyTextScaling: false,
          ),
        ),
      ],
    );
  }
}
