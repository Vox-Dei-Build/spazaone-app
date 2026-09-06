import 'package:flutter/material.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';
import 'package:pasella/pages/auth/widgets/auth_shell.dart';
import 'package:pasella/utils/phone_util.dart';

Widget buildLoginUI(BuildContext context, AuthViewModel authViewModel) =>
    ValueListenableBuilder<bool>(
      valueListenable: authViewModel.isLoading,
      builder: (context, isLoading, _) => PhoneAuthScreen(
        controller: authViewModel.mobileNoController,
        formKey: authViewModel.formKey,
        isLoading: isLoading,
        isReturningUser: true,
        onContinue: () => authViewModel.handleLogin(context),
        onCreateAccount: () =>
            Navigator.pushReplacementNamed(context, '/registerPage'),
      ),
    );

/// The production phone form, independent of Firebase for previews and tests.
class PhoneAuthScreen extends StatelessWidget {
  const PhoneAuthScreen({
    super.key,
    required this.controller,
    required this.formKey,
    required this.onContinue,
    this.isLoading = false,
    this.isReturningUser = false,
    this.onCreateAccount,
  });

  final TextEditingController controller;
  final GlobalKey<FormState> formKey;
  final VoidCallback onContinue;
  final bool isLoading;
  final bool isReturningUser;
  final VoidCallback? onCreateAccount;

  void _submit() {
    if (isLoading) return;
    if (formKey.currentState?.validate() ?? false) onContinue();
  }

  @override
  Widget build(BuildContext context) => AuthShell(
        title: isReturningUser ? 'Sign in' : 'Get started',
        subtitle: isReturningUser
            ? 'Access your shop with the mobile number linked to your account.'
            : 'Use your mobile number to create your Spaza One account.',
        footer: onCreateAccount == null
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'New to Spaza One?',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 2),
                  TextButton(
                    onPressed: isLoading ? null : onCreateAccount,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(48, 44),
                    ),
                    child: const Text('Create a business account'),
                  ),
                ],
              ),
        child: AutofillGroup(
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthPhoneField(
                  controller: controller,
                  enabled: !isLoading,
                  onSubmitted: _submit,
                ),
                const SizedBox(height: 20),
                AuthPrimaryButton(
                  label: 'Send sign-in code',
                  loadingLabel: 'Sending code…',
                  isLoading: isLoading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 14),
                Text(
                  'We’ll send a secure 6-digit code. No password required.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
}

class AuthPhoneField extends StatelessWidget {
  const AuthPhoneField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) => AuthField(
        label: 'Mobile number',
        hint: '082 123 4567',
        helper: 'South African numbers only · +27 also works',
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => onSubmitted?.call(),
        validator: (value) {
          if ((value ?? '').trim().isEmpty) return 'Enter your mobile number';
          if (!isValidSAPhoneNumber(value)) return kSAOnlyPhoneMessage;
          return null;
        },
      );
}
