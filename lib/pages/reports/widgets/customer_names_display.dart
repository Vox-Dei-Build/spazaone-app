import 'package:flutter/material.dart';
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
              final avatarSize = SizeConfig.heightMultiplier * 5.2;
              final wasReminded = reminderSentRecently(customer);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PrivateRegion(
                  child: Material(
                    key: ValueKey('customer-follow-up-$id'),
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: .42),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
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
                        padding: const EdgeInsets.fromLTRB(13, 12, 10, 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
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
                                    style: TextStyle(
                                      color: const Color(0xFF1A1F1B),
                                      fontWeight: FontWeight.w700,
                                      fontSize:
                                          SizeConfig.textMultiplier * 1.75,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  SizedBox(
                                    height: SizeConfig.heightMultiplier * 0.4,
                                  ),
                                  _buildContactLine(
                                    number,
                                    wasReminded: wasReminded,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 92),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  CurrencyUtil.format(balance),
                                  style: TextStyle(
                                    color: balance >= 0
                                        ? kPrimaryColor
                                        : Colors.red,
                                    fontWeight: FontWeight.w800,
                                    fontSize: SizeConfig.textMultiplier * 1.65,
                                  ),
                                  maxLines: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.grey.shade500,
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
  }) {
    final raw = (number ?? '').trim();
    if (raw.isEmpty) {
      return Row(
        children: [
          Icon(
            Icons.phone_disabled_outlined,
            color: Colors.grey.shade500,
            size: SizeConfig.textMultiplier * 1.55,
            applyTextScaling: false,
          ),
          const SizedBox(width: 5),
          Text(
            'No phone number',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: SizeConfig.textMultiplier * 1.35,
            ),
          ),
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
          color: isValid ? Colors.grey.shade600 : Colors.orange.shade700,
          size: SizeConfig.textMultiplier * 1.55,
          applyTextScaling: false,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            phoneLabel,
            style: TextStyle(
              color: isValid ? Colors.grey.shade700 : Colors.orange.shade800,
              fontSize: SizeConfig.textMultiplier * 1.35,
              letterSpacing: 0.1,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
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
            color: wasReminded ? kPrimaryColor : Colors.grey.shade500,
            size: SizeConfig.textMultiplier * 1.65,
            applyTextScaling: false,
          ),
        ),
      ],
    );
  }
}
