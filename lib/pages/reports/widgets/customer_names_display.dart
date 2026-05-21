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
          return Text('Error: ${snapshot.error}');
        } else {
          List<dynamic> customers = snapshot.data!;
          customers.sort((a, b) => a['balance'].compareTo(b['balance']));
          return Column(
            children:
                customers.map((customer) {
                  final balance = customer['balance'].toDouble();
                  final name = customer['name'];
                  final number = customer['number'];
                  final id = customer['id'];
                  final profileImageUrl = customer['profileImageUrl'];
                  final avatarSize = SizeConfig.heightMultiplier * 6;

                  return PrivateRegion(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(0.0),
                      visualDensity: const VisualDensity(horizontal: -2),
                      leading: SizedBox(
                        width: avatarSize,
                        height: avatarSize,
                        child: profilePicture(
                          context,
                          name,
                          profileImageUrl,
                          number,
                          true,
                        ),
                      ),
                      title: _buildTitle(name, balance),
                      // PAS-UX-06A: surface the phone number directly in the
                      // reports flow. Merchants chasing debt previously had to
                      // tap into each profile just to see a number; the bare
                      // icon-only signal hid the value that makes follow-up
                      // possible. Formatted via formatPhoneNumber so what's
                      // shown is exactly what WhatsApp/SMS will be sent to.
                      subtitle: _buildPhoneLine(context, number),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // PAS-WA-V1: this badge is purely informational.
                          // It surfaces "have I nudged this customer
                          // recently?" — it does NOT gate the next send.
                          // There is no monthly cap; merchants pay per
                          // message and can re-send at any time. The
                          // wording below is deliberate: no "cannot",
                          // no "blocked", and the off-state uses a
                          // muted grey instead of the previous red so
                          // it doesn't read as a denial.
                          number != null && number.isNotEmpty
                              ? (reminderSentRecently(customer)
                                  ? Tooltip(
                                    message:
                                        'Reminder sent in the last 30 days',
                                    triggerMode: TooltipTriggerMode.tap,
                                    child: Icon(
                                      Icons.notifications_active_outlined,
                                      color: Colors.green,
                                      size: SizeConfig.imageSizeMultiplier * 5,
                                    ),
                                  )
                                  : Tooltip(
                                    message:
                                        'No reminder in the last 30 days — you can send one now',
                                    triggerMode: TooltipTriggerMode.tap,
                                    child: Icon(
                                      Icons.notifications_none_outlined,
                                      color: Colors.grey.shade600,
                                      size: SizeConfig.imageSizeMultiplier * 5,
                                    ),
                                  ))
                              : Tooltip(
                                message:
                                    'No number available, cannot send reminder',
                                child: Icon(
                                  Icons.phone_disabled_outlined,
                                  color: Colors.grey,
                                  size: SizeConfig.imageSizeMultiplier * 5,
                                ),
                              ),
                          IconButton(
                            icon: Icon(
                              Icons.visibility,
                              size: SizeConfig.imageSizeMultiplier * 5,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => CustomerManagementPage(
                                        customerName: name,
                                        customerId: id,
                                        mobileNumber: number,
                                      ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          );
        }
      },
    );
  }

  Widget _buildTitle(name, balance) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              name,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: SizeConfig.textMultiplier * 2,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          // PAS-UX-06A: pair name with what they owe on the same row.
          // This is the single piece of info merchants need at a glance,
          // and putting it next to the name removes the prior need to
          // visually map the subtitle amount back up to the title.
          SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
          Text(
            CurrencyUtil.format(balance),
            style: TextStyle(
              color: balance >= 0 ? kPrimaryColor : Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: SizeConfig.textMultiplier * 1.8,
            ),
          ),
        ],
      ),
    );
  }

  /// PAS-UX-06A: render the formatted phone number under the name. Uses
  /// the same `formatPhoneNumber` the SMS/WhatsApp pipeline uses, so what
  /// the merchant sees is precisely what a reminder would be sent to.
  /// If the stored number cannot be confidently formatted as SA-valid
  /// the raw value is shown with a "not SA-valid" hint, rather than
  /// silently being blanked — silent blanking was a contributor to the
  /// trust break this lane addresses.
  Widget _buildPhoneLine(BuildContext context, dynamic number) {
    final String raw = (number ?? '').toString().trim();
    if (raw.isEmpty) {
      return Text(
        'No phone number',
        style: TextStyle(
          color: Colors.grey,
          fontStyle: FontStyle.italic,
          fontSize: SizeConfig.textMultiplier * 1.5,
        ),
      );
    }
    final String formatted = formatPhoneNumber(raw);
    if (formatted.isEmpty) {
      return Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: SizeConfig.textMultiplier * 1.5,
            color: Colors.orange,
          ),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 1),
          Flexible(
            child: Text(
              '$raw  (not SA-valid)',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontSize: SizeConfig.textMultiplier * 1.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return Text(
      formatted,
      style: TextStyle(
        color: Colors.black87,
        fontSize: SizeConfig.textMultiplier * 1.6,
        letterSpacing: 0.2,
      ),
    );
  }
}
