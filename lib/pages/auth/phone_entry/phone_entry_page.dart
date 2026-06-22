import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hive_local_storage/hive_local_storage.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';
import 'package:pasella/pages/auth/widgets/logo_display.dart';
import 'package:pasella/pages/dashboard/dashboard.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/utils/feature_flags.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/widgets/consent_modal.dart';
import 'package:pasella/widgets/private_region.dart';

/// PAS-UX-22: number-first onboarding entry screen.
///
/// One field. One CTA. No Login/Register toggle.
///
/// The user enters their SA mobile number; on Continue we look the number
/// up against `users` (server source) and route to OTP-as-login or
/// OTP-as-registration. The branching happens in
/// [AuthViewModel.lookupAndRoute] so this screen does not need to know
/// whether the user is new or returning.
///
/// Behaviour notes:
///   * Wrapped in a [StreamBuilder] on `authStateChanges()` so a still-signed
///     in user is bounced straight to the dashboard — matches what
///     `LoginPage` did, so the post-logout redirect to `/loginPage` (which
///     itself redirects here while the flag is on) still resolves correctly.
///   * When deferred auth consent is off, schedules the POPIA consent modal
///     in `initState` exactly like `LoginPage` does. When deferred consent is
///     on, Dashboard owns the prompt after auth and telemetry remains disabled
///     until the merchant chooses.
///   * Reads `referrerUserId` from the existing `deepLinkBox` Hive box and
///     threads it through `lookupAndRoute` so referral-sourced installs are
///     still credited on the registration write.
class PhoneEntryPage extends StatefulWidget {
  const PhoneEntryPage({super.key});

  static const id = '/phoneEntryPage';

  @override
  State<PhoneEntryPage> createState() => _PhoneEntryPageState();
}

class _PhoneEntryPageState extends State<PhoneEntryPage> {
  late final AuthViewModel _authViewModel;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();
  bool _consentPromptScheduled = false;
  bool _authFlowInProgress = false;
  String? _referrerUserId;

  @override
  void initState() {
    super.initState();
    _authViewModel = AuthViewModel();
    _loadReferrer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showConsentModalIfNeeded();
    });
  }

  void _loadReferrer() {
    try {
      final box = Hive.box('deepLinkBox');
      _referrerUserId =
          box.get('referrerUserId', defaultValue: null) as String?;
    } catch (_) {
      // deepLinkBox not open — non-fatal, just means no referral credit.
      _referrerUserId = null;
    }
  }

  Future<void> _showConsentModalIfNeeded() async {
    if (_consentPromptScheduled) return;
    _consentPromptScheduled = true;
    if (FeatureFlags.enableDeferAuthConsent) return;
    if (!mounted) return;
    await ConsentModal.showIfNeeded(context);
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _authViewModel.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _authFlowInProgress = true);
    try {
      await _authViewModel.lookupAndRoute(
        context,
        _phoneController.text,
        referrerUserId: _referrerUserId,
      );
    } finally {
      if (mounted) {
        setState(() => _authFlowInProgress = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authViewModel.auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.active) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user != null) {
          // Firebase emits the signed-in user before the number-first view
          // model has finished routing. Do not mount a transient Dashboard
          // here: a registration must reach FinishProfilePage first, and a
          // temporary Dashboard can trigger one-time post-login effects such
          // as the merchant onboarding intro behind that route.
          if (_authFlowInProgress) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          // Already signed in (e.g. session restore, post-logout race).
          // Defer to the dashboard's own gates (`BusinessNameGate` etc.)
          // to decide whether the merchant needs to finish profile.
          return const Dashboard();
        }
        return _buildEntryScaffold(context);
      },
    );
  }

  Widget _buildEntryScaffold(BuildContext context) {
    SizeConfig().init(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 6,
              vertical: SizeConfig.heightMultiplier * 3,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  SizedBox(height: SizeConfig.heightMultiplier * 5),
                  const LogoDisplay(),
                  SizedBox(height: SizeConfig.heightMultiplier * 6),
                  // Mirrors PAS-AUTH-01 copy pattern: make it explicit that
                  // the mobile number is the account and an SMS code is on
                  // the way. Avoids any "where do I sign up?" ambiguity.
                  Text(
                    'Enter your mobile number to start',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 2.4,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 1),
                  Text(
                    "We'll text you a 6-digit code. No password needed.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: SizeConfig.textMultiplier * 1.6,
                      color: Colors.grey[700],
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 3),
                  PrivateRegion(
                    child: CustomTextField(
                      label: 'Mobile Number',
                      hintText: 'e.g. 082 123 4567',
                      prefixIcon: Icons.phone,
                      controller: _phoneController,
                      textInputType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _onContinue(),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'This field is required';
                        }
                        if (!isValidSAPhoneNumber(value)) {
                          return kSAOnlyPhoneMessage;
                        }
                        return null;
                      },
                    ),
                  ),
                  SizedBox(height: SizeConfig.heightMultiplier * 2),
                  ValueListenableBuilder<bool>(
                    valueListenable: _authViewModel.isLoading,
                    builder: (context, isLoading, _) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomButton(
                            title: 'Continue',
                            onTap: isLoading ? () {} : _onContinue,
                            color: Colors.green,
                            icon: Icons.arrow_forward,
                            fontSize: SizeConfig.textMultiplier * 2,
                          ),
                          if (isLoading)
                            const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
