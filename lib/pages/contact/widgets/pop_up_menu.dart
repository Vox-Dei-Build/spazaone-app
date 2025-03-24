import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

enum CustomerActions { edit, sendReminder, viewReport }

class CustomerActionsMenu extends StatelessWidget {
  final Function(CustomerActions action) onSelected;

  const CustomerActionsMenu({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CustomerActions>(
      onSelected: onSelected,
      icon: Icon(Icons.more_vert, color: Theme.of(context).iconTheme.color),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<CustomerActions>>[
        PopupMenuItem<CustomerActions>(
          value: CustomerActions.edit,
          child: Row(
            children: [
              const Icon(Icons.edit,
                  size: 20.0, color: Colors.grey), // Adjust icon size and color
              const SizedBox(width: 10.0), // Space between icon and text
              Text('Edit Customer',
                  style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
            ],
          ),
        ),
        PopupMenuItem<CustomerActions>(
          value: CustomerActions.sendReminder,
          child: Row(
            children: [
              const Icon(Icons.notifications, size: 20.0, color: Colors.grey),
              const SizedBox(width: 10.0),
              Text('Send Reminder',
                  style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
            ],
          ),
        ),
      ],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      elevation: 2.0,
      color: Theme.of(context).cardColor,
    );
  }
}
