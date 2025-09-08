import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
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
  // Deep link subscription removed along with Branch SDK.

  @override
  void initState() {
    super.initState();
    authViewModel = AuthViewModel();
    // Deep link listening via Branch removed.
  }

  @override
  void dispose() {
    authViewModel.dispose();
    super.dispose();
    // No deep link subscription to cancel.
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
