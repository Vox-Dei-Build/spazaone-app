import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/contact/contact_management.dart';
import 'package:pasella/utils/currency_util.dart';
import 'package:pasella/utils/date_util.dart';

class CustomersWithBadLoansTile extends StatelessWidget {
  final Future<List<dynamic>>? customersWithBadLoansFuture;

  const CustomersWithBadLoansTile(
      {super.key, required this.customersWithBadLoansFuture});

  bool reminderSentRecently(customer) {
    if (customer['lastReminderSent'] != null) {
      DateTime? lastReminderSent =
          convertMapToDateTime(customer['lastReminderSent']);
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
            children: customers.map((customer) {
              final balance = customer['balance'].toDouble();
              final name = customer['name'];
              final number = customer['number'];
              final id = customer['id'];

              return ListTile(
                contentPadding: const EdgeInsets.all(0.0),
                visualDensity: const VisualDensity(horizontal: -2),
                leading: _buildLeadingIcon(kTertiaryColor.value, name, number),
                title: _buildTitle(name, balance),
                subtitle: Text(
                  CurrencyUtil.format(balance),
                  style: TextStyle(
                    color: balance >= 0 ? kPrimaryColor : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: SizeConfig.textMultiplier * 1.8,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    number != null && number.isNotEmpty
                        ? (reminderSentRecently(customer)
                            ? Tooltip(
                                message: 'Reminder sent within the last month',
                                child: Icon(
                                  Icons.notifications_active_outlined,
                                  color: Colors.green,
                                  size: SizeConfig.imageSizeMultiplier * 5,
                                ),
                              )
                            : Tooltip(
                                message:
                                    'No reminder sent within the last month',
                                child: Icon(
                                  Icons.notifications_off_outlined,
                                  color: Colors.red,
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
                            builder: (context) => CustomerManagementPage(
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
              );
            }).toList(),
          );
        }
      },
    );
  }

  Widget _buildLeadingIcon(color, name, number) {
    return Stack(
      children: [
        Container(
          height: SizeConfig.imageSizeMultiplier * 10,
          width: SizeConfig.imageSizeMultiplier * 10,
          decoration: BoxDecoration(
            color: Color(color),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0] : '',
              style: TextStyle(
                color: Colors.white,
                fontSize: SizeConfig.textMultiplier * 2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        if (number == null || number.isEmpty)
          Positioned(
            left: 0,
            bottom: 0,
            child: Icon(
              Icons.phone_disabled,
              color: Colors.red,
              size: SizeConfig.imageSizeMultiplier * 3,
            ),
          )
        else
          Positioned(
            left: 0,
            bottom: 0,
            child: Icon(
              Icons.phone_enabled,
              color: Colors.green,
              size: SizeConfig.imageSizeMultiplier * 3,
            ),
          ),
      ],
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
        ],
      ),
    );
  }
}
