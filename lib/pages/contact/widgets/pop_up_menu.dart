import 'package:flutter/material.dart';

enum CustomerActions { edit, sendReminder, viewReport }

class CustomerActionsMenu extends StatelessWidget {
  final Function(CustomerActions action) onSelected;

  CustomerActionsMenu({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CustomerActions>(
      onSelected: onSelected,
      icon: Icon(Icons.more_vert, color: Theme.of(context).iconTheme.color),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<CustomerActions>>[
        const PopupMenuItem<CustomerActions>(
          value: CustomerActions.edit,
          child: Row(
            children: [
              Icon(Icons.edit,
                  size: 20.0, color: Colors.grey), // Adjust icon size and color
              SizedBox(width: 10.0), // Space between icon and text
              Text('Edit Customer', style: TextStyle(fontSize: 16.0)),
            ],
          ),
        ),
        const PopupMenuItem<CustomerActions>(
          value: CustomerActions.sendReminder,
          child: Row(
            children: [
              Icon(Icons.notifications, size: 20.0, color: Colors.grey),
              SizedBox(width: 10.0),
              Text('Send Reminder', style: TextStyle(fontSize: 16.0)),
            ],
          ),
        ),
        /* const PopupMenuItem<CustomerActions>(
          value: CustomerActions.viewReport,
          child: Row(
            children: [
              Icon(Icons.article, size: 20.0, color: Colors.grey),
              SizedBox(width: 10.0),
              Text('View Report', style: TextStyle(fontSize: 16.0)),
            ],
          ),
        ), */
      ],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
      elevation: 2.0,
      color: Theme.of(context).cardColor,
    );
  }
}
