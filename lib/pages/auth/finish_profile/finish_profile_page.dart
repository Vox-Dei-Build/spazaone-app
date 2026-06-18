import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/auth/view_model/auth_view_model.dart';
import 'package:pasella/pages/auth/widgets/logo_display.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
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
    SizeConfig().init(context);

    // PopScope blocks Android system back + iOS swipe-back. The AppBar
    // has `automaticallyImplyLeading: false` to suppress the visual
    // back arrow. The merchant must complete the form to proceed.
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Tell us about your business'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: SizeConfig.imageSizeMultiplier * 6,
                vertical: SizeConfig.heightMultiplier * 2,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    SizedBox(height: SizeConfig.heightMultiplier * 2),
                    const LogoDisplay(),
                    SizedBox(height: SizeConfig.heightMultiplier * 3),
                    Text(
                      "Customers see your business name on every receipt, "
                      "SMS and WhatsApp message we send for you.",
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
                        label: 'Full Name',
                        hintText: 'Enter Full Name',
                        prefixIcon: Icons.person,
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Full Name is required';
                          }
                          return null;
                        },
                      ),
                    ),
                    PrivateRegion(
                      child: CustomTextField(
                        label: 'Business Name',
                        hintText: 'e.g. The Corner Shop',
                        prefixIcon: Icons.store,
                        controller: _shopController,
                        textCapitalization: TextCapitalization.words,
                        maxLength: 40,
                        // Validator copy mirrors register.dart so the
                        // experience is identical to the legacy form
                        // for merchants who happen to see both during
                        // the rollout window.
                        validator: (value) {
                          final v = (value ?? '').trim();
                          if (v.isEmpty) {
                            return 'Business Name is required';
                          }
                          if (v.length < 2) {
                            return 'Business name is too short';
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomButton(
                          title: _saving ? 'Saving…' : 'Continue',
                          onTap: _saving ? () {} : _onContinue,
                          isDisabled: _saving,
                          color: Colors.green,
                          icon: Icons.arrow_forward,
                          fontSize: SizeConfig.textMultiplier * 2,
                        ),
                        if (_saving)
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: SizeConfig.heightMultiplier * 1),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
