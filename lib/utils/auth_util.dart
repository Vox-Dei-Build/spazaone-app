import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/telemetry_service.dart';
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
  final FirebaseAuth auth = FirebaseAuth.instance;
  try {
    await auth.signOut();
    // Fire signout BEFORE reset() so the event still has the identified user.
    // TelemetryService.reset() also runs in main.dart's auth listener but
    // that happens after this -- we only need to make sure the event is
    // captured while we still have an identity.
    await TelemetryService.instance.capture(const SignoutCompleted());
    await TelemetryService.instance.reset();
    Provider.of<AppModel>(context, listen: false).updateCurrentIndex(0);
    Navigator.pushReplacementNamed(context, '/loginPage');
  } catch (e, st) {
    await CrashService.instance.recordNonFatal(
      e,
      st,
      reason: 'logout failed',
    );
  }
}

Future<bool> _promptForRegistration(BuildContext context) async {
  if (FirebaseAuth.instance.currentUser?.isAnonymous ?? false) {
    bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Register',
              style: TextStyle(fontSize: SizeConfig.textMultiplier * 2.5)),
          content: const Text(
            'Enjoying our app? To fully utilize our features and secure your data, please register. '
            'It’s quick and easy! Note: Data for anonymous users will be cleared after 30 days.',
            textAlign: TextAlign.justify,
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Later',
                  style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: Text('Register',
                  style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
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
