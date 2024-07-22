import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pasella/utils/show_toast.dart';

class FCMService {
  void requestPermission(BuildContext context) async {
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
      handleToken();
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      print('User granted provisional permission');
      // Handle provisional permission if necessary
      // You can still get the token and send it to the server
      handleToken();
    } else {
      print('User declined or has not accepted permission');
      // Show a SnackBar if permission is declined
      showErrorSnackBar(context,
          "You won't receive notifications as permission was declined.");
    }
  }

  void handleToken() async {
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

      // Get the current token from Firestore
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      // Cast the data to a Map<String, dynamic> and check if 'fcmToken' exists
      Map<String, dynamic>? userData = userDoc.data() as Map<String, dynamic>?;
      String? currentToken =
          userData != null && userData.containsKey('fcmToken')
              ? userData['fcmToken']
              : null;

      // If the current token is different from the new token, update the Firestore document
      if (currentToken != newToken) {
        FirebaseFirestore.instance.collection('users').doc(userId).set({
          'fcmToken': newToken,
        }, SetOptions(merge: true)).then((_) {
          print('FCM Token updated in Firestore for user $userId');
        }).catchError((error) {
          print('Error updating FCM Token for user $userId: $error');
        });
      } else {
        print('FCM Token is up-to-date for user $userId');
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
        // Update the user's document in Firestore with the new FCM token
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .update({
          'fcmToken': newToken,
        });
        showSnackbar(context, 'Notification settings updated successfully :)',
            Colors.green);
      }
    } catch (e) {
      print('Error updating FCM Token: $e');
      showErrorSnackBar(context, "Failed to update notification settings.");
    }
  }

  Future<void> showPermissionExplanationDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap a button to dismiss.
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Notification Permission'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('We would like to send you notifications for:'),
                Text('- Payment reminders'),
                Text('- Account updates'),
                Text('- Special offers'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Decline'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('Allow'),
              onPressed: () {
                Navigator.of(context).pop();
                requestPermission(context);
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
