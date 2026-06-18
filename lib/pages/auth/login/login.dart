import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/app_imports.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';
import 'package:pasella/pages/auth/widgets/login_ui.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/widgets/consent_modal.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  static const id = '/loginPage';

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late AuthViewModel authViewModel;
  bool _consentPromptScheduled = false;
  // Deep link subscription removed along with Branch SDK.

  @override
  void initState() {
    super.initState();
    authViewModel = AuthViewModel();
    // PAS-UX-22: compat-shim redirect. When number-first onboarding is on,
    // any navigation to `/loginPage` (post-logout, stale deep link, FCM
    // notification routing) bounces to `/phoneEntryPage`. We use
    // pushReplacementNamed so back-stack doesn't strand the merchant on a
    // dead screen. Done in a post-frame callback so the redirect runs
    // after the first build and respects the navigator lifecycle.
    if (FeatureFlags.enableNumberFirstOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(PhoneEntryPage.id);
      });
      return;
    }
    // PAS-GROWTH-03: surface the first-run telemetry consent modal before
    // the user can interact with the login form. Doing this pre-login
    // (rather than from Dashboard's initState) closes a small window where
    // anonymous Firebase auth and screen-view events could fire to PostHog
    // / Firebase Analytics before the user had decided. The modal
    // short-circuits via `ConsentService.state.hasDecided`, so repeat
    // launches are no-ops.
    //
    // Skipped when the number-first flag is on: the same modal is
    // scheduled from `PhoneEntryPage.initState` so consent still gates
    // any pre-auth telemetry.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showConsentModalIfNeeded();
    });
    // Deep link listening via Branch removed.
  }

  Future<void> _showConsentModalIfNeeded() async {
    if (_consentPromptScheduled) return;
    _consentPromptScheduled = true;
    if (!mounted) return;
    await ConsentModal.showIfNeeded(context);
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
            return const Dashboard();
          }
        }
        return const CircularProgressIndicator();
      },
    );
  }
}
