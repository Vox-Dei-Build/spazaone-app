import 'package:flutter/material.dart';

void showSnackbar(BuildContext context, String message, Color color) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text(
      message,
      style: TextStyle(
        fontSize:
            MediaQuery.of(context).size.width * 0.04, // Responsive text size
      ),
    ),
    backgroundColor: color,
    behavior: SnackBarBehavior.floating, // Make the snackbar float above the UI
    shape: RoundedRectangleBorder(
      borderRadius:
          BorderRadius.circular(10), // Rounded corners for the snackbar
    ),
    margin: EdgeInsets.symmetric(
      horizontal: MediaQuery.of(context).size.width * 0.1, // Responsive margin
      vertical: MediaQuery.of(context).size.height *
          0.02, // Responsive vertical margin
    ),
  ));
}

void showSnackbarWithNavigation(
    BuildContext context, String message, Color color, SnackBarAction action) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(
        message,
        style: TextStyle(
          fontSize:
              MediaQuery.of(context).size.width * 0.04, // Responsive text size
        ),
      ),
      backgroundColor: color,
      behavior:
          SnackBarBehavior.floating, // Make the snackbar float above the UI
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(10), // Rounded corners for the snackbar
      ),
      duration: Duration(seconds: 10),
      action: action));
}

void showErrorSnackBar(BuildContext context, String message,
    {bool isWarning = false}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(
          fontSize:
              MediaQuery.of(context).size.width * 0.04, // Responsive text size
        ),
      ),
      backgroundColor: isWarning ? Colors.orangeAccent : Colors.red,
      duration: Duration(seconds: 3),
      behavior:
          SnackBarBehavior.floating, // Make the snackbar float above the UI
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(10), // Rounded corners for the snackbar
      ),
      margin: EdgeInsets.symmetric(
        horizontal:
            MediaQuery.of(context).size.width * 0.1, // Responsive margin
        vertical: MediaQuery.of(context).size.height *
            0.02, // Responsive vertical margin
      ),
    ),
  );
}

void showSMSSnackBar(BuildContext context, String message, bool success) {
  if (!context.mounted) return;
  final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  if (scaffoldMessenger == null) return;
  scaffoldMessenger.showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(
          fontSize:
              MediaQuery.of(context).size.width * 0.04, // Responsive text size
        ),
      ),
      backgroundColor: success ? Colors.green : Colors.red,
      behavior:
          SnackBarBehavior.floating, // Make the snackbar float above the UI
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(10), // Rounded corners for the snackbar
      ),
      margin: EdgeInsets.symmetric(
        horizontal:
            MediaQuery.of(context).size.width * 0.1, // Responsive margin
        vertical: MediaQuery.of(context).size.height *
            0.02, // Responsive vertical margin
      ),
    ),
  );
}
