import 'package:flutter/material.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/pages/auth/widgets/auth_shell.dart';

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
    // Keep the completed-OTP registration gate unskippable.
    return PopScope(
      canPop: false,
      child: AuthShell(
        stepLabel: 'Last step',
        title: 'Set up your shop',
        subtitle: 'Add your name and the business name customers will see.',
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ProfileDetailsFields(
                  nameController: _nameController,
                  shopController: _shopController,
                  enabled: !_saving,
                  limitShopName: true,
                  onSubmitted: _onContinue,
                ),
                const SizedBox(height: 24),
                AuthPrimaryButton(
                  label: 'Continue',
                  isLoading: _saving,
                  loadingLabel: 'Saving your profile…',
                  onPressed: _onContinue,
                ),
                const SizedBox(height: 12),
                Text(
                  'You can edit these details later in Settings.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
