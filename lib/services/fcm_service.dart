import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/utils/show_toast.dart';

class FCMService {
  @visibleForTesting
  static bool shouldPromptForPermission(AuthorizationStatus status) {
    return status == AuthorizationStatus.notDetermined;
  }

  /// Requests notification permission only when the operating system has not
  /// received a decision yet. This keeps the prompt contextual without
  /// repeatedly interrupting merchants who already declined it.
  Future<void> requestPermissionIfNeeded(BuildContext context) async {
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        await handleToken();
        return;
      }

      if (!shouldPromptForPermission(settings.authorizationStatus) ||
          !context.mounted) {
        return;
      }

      await showPermissionExplanationDialog(context);
    } catch (error, stack) {
      await CrashService.instance.recordNonFatal(
        error,
        stack,
        reason: 'fcm permission check failed',
      );
    }
  }

  Future<void> requestPermission(BuildContext context) async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');
      // Get the token and send it to the server
      await handleToken();
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      print('User granted provisional permission');
      // Handle provisional permission if necessary
      // You can still get the token and send it to the server
      await handleToken();
    } else {
      print('User declined or has not accepted permission');
      // Show a SnackBar if permission is declined
      if (context.mounted) {
        showErrorSnackBar(context,
            "You won't receive notifications as permission was declined.");
      }
    }
  }

  Future<void> handleToken() async {
    // Obtain the new token
    String? newToken = await FirebaseMessaging.instance.getToken();

    // Check if the token is not null
    if (newToken != null) {
      // Obtain the user ID from Firebase Authentication
      String userId = FirebaseAuth.instance.currentUser?.uid ?? '';

      // If the user is not logged in, you might want to handle this case differently
      if (userId.isEmpty) {
        print('User is not logged in. Cannot store FCM token.');
        return;
      }

      try {
        // Keep the legacy scalar for older functions and an array for
        // multi-device delivery. arrayUnion is idempotent.
        await FirebaseFirestore.instance.collection('users').doc(userId).set({
          'fcmToken': newToken,
          'fcmTokens': FieldValue.arrayUnion([newToken]),
        }, SetOptions(merge: true)).then((_) {
          print('FCM Token updated in Firestore for user $userId');
        });
      } catch (error, stack) {
        // Non-fatal: the next launch retries token registration.
        await CrashService.instance.recordNonFatal(
          error,
          stack,
          reason: 'fcm handleToken update failed',
        );
      }
    } else {
      print('FCM Token is null. Cannot store token.');
    }
  }

  void listenToTokenRefresh(context) {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print("New FCM Token: $newToken");
      updateTokenOnServer(newToken, context);
    });
  }

  Future<void> updateTokenOnServer(String newToken, context) async {
    try {
      String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (userId.isNotEmpty) {
        // Keep both token representations in sync for old and new functions.
        await FirebaseFirestore.instance.collection('users').doc(userId).set({
          'fcmToken': newToken,
          'fcmTokens': FieldValue.arrayUnion([newToken]),
        }, SetOptions(merge: true));
        if (context is BuildContext && context.mounted) {
          showSnackbar(context, 'Notification settings updated successfully :)',
              Colors.green);
        }
      }
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'fcm updateTokenOnServer failed',
      );
      if (context is BuildContext && context.mounted) {
        showErrorSnackBar(context, "Failed to update notification settings.");
      }
    }
  }

  Future<void> showPermissionExplanationDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap a button to dismiss.
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Stay on top of your business'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'Allow notifications so you do not miss:',
                ),
                SizedBox(height: 12),
                Text('• New customer messages'),
                Text('• New orders and order updates'),
                Text('• Payment and account updates'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Not now'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Allow notifications'),
              onPressed: () async {
                Navigator.of(context).pop();
                await requestPermission(context);
              },
            ),
          ],
        );
      },
    );
  }

  Future<NotificationSettings> getNotificationSettings() async {
    return await FirebaseMessaging.instance.getNotificationSettings();
  }
}
