import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/shared/services/period_filter_services.dart';
import 'package:provider/provider.dart';

Future<bool> isAnonymousGate(BuildContext context) async {
  if (FirebaseAuth.instance.currentUser?.isAnonymous ?? false) {
    bool shouldNavigate = await _promptForRegistration(context);
    if (shouldNavigate) {
      Navigator.of(context).pushNamed('/registerAnonymousPage');
      return false; // Indicates that navigation has been handled and further action should halt.
    }
  }
  return true; // Indicates that no navigation took place and further action can proceed.
}

bool isUserAnonymous() {
  return FirebaseAuth.instance.currentUser?.isAnonymous ?? true;
}

void logout(BuildContext context) async {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  try {
    await _auth.signOut();
    Provider.of<AppModel>(context, listen: false).updateCurrentIndex(0);
    final periodFilterService =
        Provider.of<PeriodFilterService>(context, listen: false);
    periodFilterService.resetPeriodFilter();
    Navigator.pushReplacementNamed(context, '/loginPage');
  } catch (e) {
    print("Error logging out: $e");
  }
}

Future<bool> _promptForRegistration(BuildContext context) async {
  if (FirebaseAuth.instance.currentUser?.isAnonymous ?? false) {
    bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Register'),
          content: Text(
            'Enjoying our app? To fully utilize our features and secure your data, please register. '
            'It’s quick and easy! Note: Data for anonymous users will be cleared after 30 days.',
            textAlign: TextAlign.justify,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Later'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Register'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
  return false; // If the user is not anonymous, no need to show the prompt.
}
