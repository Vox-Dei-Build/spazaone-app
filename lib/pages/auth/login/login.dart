import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/app_imports.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';
import 'package:pasella/pages/auth/widgets/login_ui.dart';

import '../../dashboard/dashboard.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  static const id = '/loginPage';

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late AuthViewModel authViewModel;
  StreamSubscription<Map>? streamSubscriptionDeepLink;

  @override
  void initState() {
    super.initState();
    authViewModel = AuthViewModel();
    // Initialize deep link listening only if user is not already logged in
    Future.delayed(Duration.zero, () {
      if (FirebaseAuth.instance.currentUser == null) {
        listenDeepLinkData(context);
      }
    });
  }

  @override
  void dispose() {
    authViewModel.dispose();
    super.dispose();
    streamSubscriptionDeepLink?.cancel();
  }

  void listenDeepLinkData(BuildContext context) async {
    streamSubscriptionDeepLink = FlutterBranchSdk.initSession().listen((data) {
      if (data.containsKey("+clicked_branch_link") &&
          data["+clicked_branch_link"] == true) {
        var referrerUserId = data['userId'];
        print("Referrer User ID: $referrerUserId");
        // Save referrerUserId for later use when the user decides to register
        saveDeepLinkData(referrerUserId);
      }
    }, onError: (error) {
      PlatformException platformException = error as PlatformException;
      print('${platformException.code} - ${platformException.message}');
    });
  }

  Future<void> saveDeepLinkData(String referrerUserId) async {
    var box = Hive.box('deepLinkBox');
    await box.put('referrerUserId', referrerUserId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authViewModel.auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          if (user == null) {
            return buildLoginUI(context, authViewModel);
          } else {
            return Dashboard();
          }
        }
        return CircularProgressIndicator();
      },
    );
  }
}
