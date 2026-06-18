import 'package:flutter/material.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/widgets/private_region.dart';

/// PAS-UX-22: collects Full Name + Business Name after a number-first
/// registration's OTP step has already succeeded.
///
/// Mirrors the unskippable-gate pattern from `BusinessNamePage`
/// (`requireValue: true`): the AppBar has no back affordance and system
/// back / iOS swipe-back is blocked by [PopScope]. The merchant must
/// either submit valid values or kill the app — in the latter case
/// they're already an authenticated Firebase user with the auth-keyed
/// minimum doc written, and the post-auth `BusinessNameGate` will pull
/// them back here (or to its own one-field recovery) on next resume.
///
/// Why this isn't just `BusinessNamePage`:
///   * Collects two fields instead of one (Full Name was also deferred
///     by `PhoneEntryPage` to keep that screen single-input).
///   * Writes via [AuthViewModel.completeProfileForNumberFirst] which
///     uses `merge: true` against the doc seeded at OTP success — so
///     this page never has to know how to create a `users/{uid}` doc
///     from scratch, only how to fill it in.
class FinishProfilePage extends StatefulWidget {
  const FinishProfilePage({super.key});

  static const id = '/finishProfilePage';

  @override
  State<FinishProfilePage> createState() => _FinishProfilePageState();
}

class _FinishProfilePageState extends State<FinishProfilePage> {
  late final AuthViewModel _authViewModel;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _shopController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _authViewModel = AuthViewModel();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shopController.dispose();
    _authViewModel.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await _authViewModel.completeProfileForNumberFirst(
        context,
        name: _nameController.text,
        shopName: _shopController.text,
      );
      // On success, completeProfileForNumberFirst() navigates to the
      // dashboard via handleSuccessfulLogin(); nothing more to do here.
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'FinishProfilePage save failed',
      );
      if (!mounted) return;
      showErrorSnackBar(
        context,
        "Couldn't save your details. Please try again.",
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // PopScope blocks Android system back + iOS swipe-back. This is the
    // final required registration step, so there is deliberately no back
    // affordance or skip action.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.storefront_outlined,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'FINAL STEP',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Set up your profile',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tell us what to call you and what customers should see '
                    'on receipts and WhatsApp messages.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.grey.shade700,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PrivateRegion(
                          child: TextFormField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: _fieldDecoration(
                              label: 'Full name',
                              hint: 'e.g. Thandi Mokoena',
                              icon: Icons.person_outline,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter your full name';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                        PrivateRegion(
                          child: TextFormField(
                            controller: _shopController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.done,
                            maxLength: 40,
                            onFieldSubmitted: (_) => _onContinue(),
                            decoration: _fieldDecoration(
                              label: 'Business name',
                              hint: 'e.g. The Corner Shop',
                              icon: Icons.storefront_outlined,
                            ).copyWith(counterText: ''),
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (v.isEmpty) {
                                return 'Enter your business name';
                              }
                              if (v.length < 2) {
                                return 'Business name is too short';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.visibility_outlined,
                              size: 18,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Customers will see the business name, not '
                                'your full name.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _onContinue,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        disabledBackgroundColor: Colors.green.shade200,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_forward),
                      label:
                          Text(_saving ? 'Saving your profile…' : 'Continue'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You can update these details later in Settings.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.green.shade600, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade400),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.red.shade400, width: 2),
      ),
    );
  }
}
