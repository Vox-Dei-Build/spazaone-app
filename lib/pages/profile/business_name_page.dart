import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/services/crash_service.dart';
import 'package:pasella/services/store_session.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:pasella/utils/show_toast.dart';

/// PAS-UX-09 follow-up: a focused recovery/edit screen for the merchant's
/// `shopName` (Business Name).
///
/// Two modes:
///   * Default (`requireValue: false`) — opened from Settings to edit/rename.
///     Back navigation is allowed; user can leave without saving.
///   * Soft-gate (`requireValue: true`) — opened automatically by
///     [BusinessNameGate] when an authenticated merchant has no shopName
///     stored (legacy blanks from when the field was optional). Back / system
///     pop is suppressed; the only way out is to save a valid name.
///
/// Background: business name was made optional during phone-OTP signup, with
/// the register screen telling the user "You can add this later in Settings".
/// That settings entry was never wired up, leaving merchants with a blank
/// `shopName` no way to set it — and that empty value then leaks into
/// outbound SMS / WhatsApp / promotion templates as a blank substitution.
/// The field is now required again at signup; this page handles legacy
/// recovery + rename.
class BusinessNamePage extends StatefulWidget {
  const BusinessNamePage({
    super.key,
    this.requireValue = false,
    this.onSaved,
  });

  /// When true, the screen is rendered as an unskippable gate: back gestures
  /// are blocked, the AppBar has no leading button, and copy is tailored to
  /// "you must set this to continue".
  final bool requireValue;

  /// Optional callback fired after a successful save. Used by the soft-gate
  /// to dismiss itself and reveal the wrapped child (e.g. the Dashboard).
  /// When null, the page calls `Navigator.pop()` instead.
  final VoidCallback? onSaved;

  static const id = '/businessNamePage';

  @override
  State<BusinessNamePage> createState() => _BusinessNamePageState();
}

class _BusinessNamePageState extends State<BusinessNamePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _controller = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _initialValue = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    try {
      final existing =
          await fetchShopNameForUser(StoreSession.instance.storeId);
      _initialValue = (existing ?? '').trim();
      _controller.text = _initialValue;
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'BusinessNamePage load failed',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showErrorSnackBar(context, 'You need to be signed in to save changes.');
      return;
    }
    final newValue = _controller.text.trim();
    if (newValue == _initialValue && !widget.requireValue) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(StoreSession.instance.storeId)
          .set(
        {'shopName': newValue},
        SetOptions(merge: true),
      );
      if (!mounted) return;
      showSnackbar(context, 'Business name saved', SpazaColors.action);
      if (widget.onSaved != null) {
        widget.onSaved!();
      } else {
        Navigator.of(context).pop();
      }
    } catch (e, st) {
      await CrashService.instance.recordNonFatal(
        e,
        st,
        reason: 'BusinessNamePage save failed',
      );
      if (!mounted) return;
      showErrorSnackBar(context, 'Could not save business name. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      appBar: widget.requireValue
          // Soft-gate: no back arrow, no chance to escape without saving.
          ? AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Add your business name'),
            )
          : const CustomAppBar(title: 'Business name'),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : BusinessNameForm(
                controller: _controller,
                formKey: _formKey,
                requireValue: widget.requireValue,
                saving: _saving,
                onSave: _save,
              ),
      ),
    );

    // Block Android back / iOS swipe-back when used as a gate.
    if (widget.requireValue) {
      return PopScope(canPop: false, child: scaffold);
    }
    return scaffold;
  }
}

/// Form presentation shared by the authenticated route and local design review.
class BusinessNameForm extends StatelessWidget {
  const BusinessNameForm({
    super.key,
    required this.controller,
    required this.formKey,
    required this.onSave,
    this.requireValue = false,
    this.saving = false,
  });
  final TextEditingController controller;
  final GlobalKey<FormState> formKey;
  final VoidCallback onSave;
  final bool requireValue;
  final bool saving;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(SpazaSpace.lg),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                requireValue
                    ? 'Before you continue, please add your business name. Customers see this on every receipt, SMS and WhatsApp message we send on your behalf.'
                    : 'Your business name appears on receipts and on SMS / WhatsApp messages we send to your customers on your behalf. Keep it short and recognisable.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: SpazaSpace.xl),
              CustomTextField(
                label: 'Business name',
                hintText: 'e.g. The Corner Shop',
                prefixIcon: SpazaIcons.shop,
                controller: controller,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  final name = (value ?? '').trim();
                  if (name.isEmpty) return 'Enter a business name';
                  if (name.length < 2) return 'Business name is too short';
                  return null;
                },
              ),
              const SizedBox(height: SpazaSpace.sm),
              CustomButton(
                onTap: onSave,
                isDisabled: saving,
                margin: EdgeInsets.zero,
                title:
                    saving ? 'Saving…' : (requireValue ? 'Continue' : 'Save'),
              ),
            ],
          ),
        ),
      );
}
