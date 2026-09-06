import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/pages/auth/phone_entry/phone_entry_page.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';
import 'package:pasella/pages/auth/widgets/auth_shell.dart';
import 'package:pasella/pages/auth/widgets/login_ui.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/utils/support_util.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({Key? key}) : super(key: key);
  static const id = '/registerPage';

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  late AuthViewModel authViewModel;
  late String? referrerUserId;

  @override
  void initState() {
    super.initState();
    authViewModel = AuthViewModel();
    loadInitialData();
    // PAS-UX-22: compat-shim redirect. When number-first onboarding is on,
    // `/registerPage` (reached via the legacy "Create a new account" link
    // on `/loginPage` or any external deep link) bounces to
    // `/phoneEntryPage`. Same rationale as the LoginPage shim.
    if (FeatureFlags.enableNumberFirstOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(PhoneEntryPage.id);
      });
    }
  }

  void loadInitialData() async {
    var box = Hive.box('deepLinkBox');
    referrerUserId = box.get('referrerUserId', defaultValue: null);
  }

  void _register() {
    if (authViewModel.isLoading.value) return;
    if (authViewModel.registrationFormKey.currentState!.validate()) {
      authViewModel.registerUser(context, referrerUserId: referrerUserId);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: authViewModel.isLoading,
        builder: (context, isLoading, _) => AuthShell(
          title: 'Create your account',
          subtitle:
              'Add your details, then verify your mobile number with an SMS code.',
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton(
                onPressed: isLoading
                    ? null
                    : () => Navigator.pushNamed(context, '/loginPage'),
                child: const Text('Already have an account? Sign in'),
              ),
              if (FeatureFlags.enableAnonymousGate)
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () => authViewModel.signInAnonymously(context),
                  child: const Text('Explore before signing up'),
                ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () => SupportUtil.sendWhatsAppMessage(
                          context,
                          WhatsAppMessageType.support,
                        ),
                child: const Text('Chat with support'),
              ),
            ],
          ),
          child: AutofillGroup(
            child: Form(
              key: authViewModel.registrationFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileDetailsFields(
                    nameController: authViewModel.nameController,
                    shopController: authViewModel.shopNameController,
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 16),
                  AuthPhoneField(
                    controller: authViewModel.registrationMobileNoController,
                    enabled: !isLoading,
                    onSubmitted: _register,
                  ),
                  const SizedBox(height: 24),
                  AuthPrimaryButton(
                    label: 'Create account',
                    isLoading: isLoading,
                    loadingLabel: 'Sending code…',
                    onPressed: _register,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
