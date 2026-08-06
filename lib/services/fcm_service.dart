import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/config/firebase_environment.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/utils/show_toast.dart';

class FCMService {
  @visibleForTesting
  static bool messagingEnabled({bool? emulatorMode}) {
    return !(emulatorMode ?? FirebaseEnvironment.useEmulators);
  }

  @visibleForTesting
  static bool shouldPromptForPermission(AuthorizationStatus status) {
    return status == AuthorizationStatus.notDetermined;
  }

  /// Requests notification permission only when the operating system has not
  /// received a decision yet. This keeps the prompt contextual without
  /// repeatedly interrupting merchants who already declined it.
  Future<void> requestPermissionIfNeeded(BuildContext context) async {
    if (!messagingEnabled()) return;
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
    if (!messagingEnabled()) return;
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
    if (!messagingEnabled()) return;
    try {
      // Token registration is best-effort. A Firebase Installations or network
      // failure must never block store switching, store creation, or login.
      final newToken = await FirebaseMessaging.instance.getToken();
      if (newToken == null) {
        print('FCM Token is null. Cannot store token.');
        return;
      }
      if (StoreSession.instance.storeId.isEmpty) {
        print('User is not logged in. Cannot store FCM token.');
        return;
      }
      await _writeTokenToAssignedStores(newToken);
    } catch (error, stack) {
      // Non-fatal: the next launch retries token registration.
      await CrashService.instance.recordNonFatal(
        error,
        stack,
        reason: 'fcm handleToken update failed',
      );
    }
  }

  void listenToTokenRefresh(context) {
    if (!messagingEnabled()) return;
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      // Never print device tokens; they are credentials for a notification
      // destination and should not enter logs or crash reports.
      print('FCM token refreshed.');
      updateTokenOnServer(newToken, context);
    });
  }

  Future<void> updateTokenOnServer(String newToken, context) async {
    if (!messagingEnabled()) return;
    try {
      if (StoreSession.instance.storeId.isNotEmpty) {
        await _writeTokenToAssignedStores(newToken);
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

  Future<void> _writeTokenToAssignedStores(String token) async {
    final activeStoreId = StoreSession.instance.storeId;
    final storeIds = <String>{
      if (activeStoreId.isNotEmpty) activeStoreId,
      ...StoreSession.instance.stores
          .map((membership) => membership.storeId)
          .where((storeId) => storeId.isNotEmpty),
    };

    for (final storeId in storeIds) {
      // Keep the legacy scalar for older functions and an array for
      // multi-device delivery. arrayUnion is idempotent.
      await FirebaseFirestore.instance.collection('users').doc(storeId).set({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
      }, SetOptions(merge: true));
      await _writeMembershipToken(storeId, token);
    }
  }

  Future<void> _writeMembershipToken(String storeId, String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .collection('operators')
          .doc(uid)
          .set({
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
        'notificationUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (error) {
      // Legacy stores may not have v2 metadata yet; the root token write above
      // remains valid until bootstrap or migration creates a membership.
      if (error.code != 'permission-denied' && error.code != 'not-found') {
        rethrow;
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
