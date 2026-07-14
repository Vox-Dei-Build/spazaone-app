import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/app_urls.dart';
import 'package:pasella/pages/contact/view_model/add_contact_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/confirm_dialog.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/widgets/private_region.dart';
import 'package:provider/provider.dart';
import 'package:pasella/constants/constants.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/permission_helper.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:url_launcher/url_launcher.dart';

/// Add Customer (a.k.a. "Add Contact") screen.
///
/// Visual redesign (PAS-UX-DESIGN):
///   * Avatar-led hero: profile picture is the visual anchor at the top of
///     the form and is itself the tap target for picking/changing the photo
///     (with a small edit chip overlay). Replaces the previous "avatar +
///     external green camera IconButton" pattern which read as two separate
///     controls for one action.
///   * Contact-picker as a single tappable card row (no `OR` divider). The
///     manual form below is the natural fallback, so we don't need an
///     either/or signpost.
///   * Form fields are no longer wrapped in a boxed `SectionCard` — they
///     sit on the page with consistent rhythm driven by [LayoutConstants].
///   * Consent moved from the top of the screen to a compact row directly
///     above the Confirm button. It now gates the Confirm action (the
///     actual persistence step) instead of the contact picker. Same POPIA
///     coverage — nothing is saved without consent — with less legal-first
///     framing.
class AddContactPage extends StatelessWidget {
  const AddContactPage({super.key});
  static const id = '/addContactPage';

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    // PAS-UX-10: routed through AppUrls so privacy-policy hosting can
    // move from the legacy public Google Doc to a spazaone.com URL
    // by changing one constant.
    final uri = Uri.parse(AppUrls.privacyPolicy);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      showErrorSnackBar(
        context,
        "Could not open the privacy policy. Please check your connection.",
        isWarning: true,
      );
    }
  }

  Future<void> _pickFromContacts(
    BuildContext context,
    AddContactViewModel viewModel,
  ) async {
    final granted = await PermissionHelper.requestContacts(context);
    if (!granted) return;

    try {
      final Contact? contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;

      // Re-fetch with full details to ensure phones are populated (some
      // OEMs return a stub from the picker).
      final fullContact = await FlutterContacts.getContact(
        contact.id,
        withProperties: true,
      );
      final phones = fullContact?.phones ?? contact.phones;
      final String? phoneNumber =
          phones.isNotEmpty ? phones.first.number : null;

      if (phoneNumber == null || phoneNumber.isEmpty) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          showErrorSnackBar(
            context,
            'This contact does not have a number.',
            isWarning: true,
          );
        });
        return;
      }

      // PAS-UX-08: previously `cleanPhoneNumber` was used as a silent
      // fallback when the contact wasn't a valid SA mobile, which
      // dumped raw digits (or junk) into the field with no error. Now:
      // if the picked contact normalises cleanly, write it; otherwise
      // tell the user explicitly so they can hand-enter or pick a
      // different contact.
      final normalized = normalizePhoneNumber(phoneNumber);
      viewModel.nameController.text = (fullContact ?? contact).displayName;
      if (normalized.isNotEmpty) {
        viewModel.numberController.text = normalized;
      } else {
        viewModel.numberController.text = '';
        SchedulerBinding.instance.addPostFrameCallback((_) {
          showErrorSnackBar(context, kSAOnlyPhoneMessage, isWarning: true);
        });
      }
    } catch (_) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        showErrorSnackBar(context, 'Failed to get contact :(', isWarning: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AddContactViewModel(),
      child: Consumer<AddContactViewModel>(
        builder: (context, viewModel, child) {
          return PopScope(
            canPop: !viewModel.isDirty,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              final shouldPop = await ConfirmDialog.showDestructive(
                context,
                title: 'Discard contact?',
                message:
                    'You have unsaved changes. Leaving now will discard them.',
                confirmLabel: 'Discard',
                cancelLabel: 'Keep editing',
              );
              if (shouldPop && context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: Scaffold(
                backgroundColor: Colors.white,
                appBar: const CustomAppBar(title: 'Add Customer'),
                body: SafeArea(
                  child: Consumer<AppModel>(
                    builder: (context, model, child) {
                      final categoryLabel =
                          model.selectedCustomerCategory.toString();

                      return Form(
                        key: viewModel.formKey,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _AvatarHero(viewModel: viewModel),
                              const SizedBox(height: 8),
                              _NamePreview(
                                viewModel: viewModel,
                                categoryLabel: categoryLabel,
                              ),
                              const SizedBox(height: 24),
                              _ImportFromContactsCard(
                                onTap: () =>
                                    _pickFromContacts(context, viewModel),
                              ),
                              const SizedBox(height: 24),
                              _FieldLabel(label: '$categoryLabel details'),
                              const SizedBox(height: 8),
                              PrivateRegion(
                                child: CustomTextField(
                                  hintText: 'Customer Name',
                                  prefixIcon: Icons.person_outline,
                                  label: 'Name *',
                                  textInputType: TextInputType.name,
                                  maxLength: 20,
                                  controller: viewModel.nameController,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'This field is required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              PrivateRegion(
                                child: CustomTextField(
                                  hintText: 'Enter an SA mobile number',
                                  prefixIcon: Icons.call_outlined,
                                  label: 'Mobile Number (Optional)',
                                  textInputType: TextInputType.number,
                                  maxLength: 10,
                                  controller: viewModel.numberController,
                                  validator: (value) {
                                    final v = value?.trim() ?? '';
                                    if (v.isEmpty) return null;
                                    if (!isValidSAPhoneNumber(v)) {
                                      return kSAOnlyPhoneMessage;
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              _ConsentRow(
                                accepted: viewModel.contactConsentAccepted,
                                onChanged: viewModel.setContactConsent,
                                onTapPrivacy: () => _openPrivacyPolicy(context),
                              ),
                              const SizedBox(height: 20),
                              // Disabled when loading OR when consent has
                              // not been given. The view model also guards
                              // server-side, so this is purely a UX cue.
                              CustomButton(
                                isDisabled: viewModel.isLoading ||
                                    !viewModel.contactConsentAccepted,
                                onTap: () async {
                                  if (viewModel.formKey.currentState
                                          ?.validate() ??
                                      false) {
                                    await viewModel.addCustomerToFirestore(
                                      context,
                                      model,
                                    );
                                  }
                                },
                                margin: EdgeInsets.zero,
                                title:
                                    viewModel.isLoading ? 'Saving…' : 'Confirm',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Hero avatar with an inline edit chip. Tapping anywhere on the avatar
/// triggers the image picker; the chip is a visual affordance, not a
/// separate hit target (the [InkWell] inside [ProfileImageWidget] already
/// covers the full circle).
class _AvatarHero extends StatelessWidget {
  const _AvatarHero({required this.viewModel});
  final AddContactViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final radius = SizeConfig.heightMultiplier * 8;
    return Center(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Use the existing profilePicture composer so the phone-status
            // status icon (no-phone indicator) keeps rendering — preserves
            // PAS-AUTH-02 affordance.
            Positioned.fill(
              child: GestureDetector(
                onTap: () => viewModel.handleImagePick(context),
                behavior: HitTestBehavior.opaque,
                child: profilePicture(
                  context,
                  viewModel.nameController.text,
                  null,
                  viewModel.numberController.text,
                  false,
                  displayIcons: true,
                  radius: radius,
                  profileImage: viewModel.profileImage,
                ),
              ),
            ),
            Positioned(
              right: -8,
              bottom: -8,
              child: Semantics(
                button: true,
                label: 'Change customer photo',
                child: GestureDetector(
                  onTap: () => viewModel.handleImagePick(context),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: kPrimaryColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NamePreview extends StatelessWidget {
  const _NamePreview({required this.viewModel, required this.categoryLabel});
  final AddContactViewModel viewModel;
  final String categoryLabel;

  @override
  Widget build(BuildContext context) {
    final hasName = viewModel.nameController.text.trim().isNotEmpty;
    return Column(
      children: [
        Text(
          hasName ? viewModel.nameController.text : 'New $categoryLabel',
          textAlign: TextAlign.center,
          style: kSectionHeaderStyle.copyWith(
            color: hasName ? Colors.black87 : kSecondaryAccent,
          ),
        ),
        const SizedBox(height: 2),
        Text(categoryLabel, textAlign: TextAlign.center, style: kSubTitleStyle),
      ],
    );
  }
}

class _ImportFromContactsCard extends StatelessWidget {
  const _ImportFromContactsCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kHighLightColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kPrimaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.contacts_outlined,
                  color: kPrimaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Import from phone contacts',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Pick a contact to auto-fill the form',
                      style: kSubTitleStyle,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: kSecondaryAccent),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: kLabelStyle.copyWith(fontSize: 13, letterSpacing: 0.3),
    );
  }
}

/// Compact consent row directly above the Confirm button. Replaces the
/// previous full-width [CheckboxListTile] block at the top of the form.
///
/// Implemented as a [StatefulWidget] so the inline "Privacy policy"
/// [TapGestureRecognizer] is owned by the State and disposed correctly —
/// constructing a recognizer inline inside [TextSpan] leaks it on every
/// rebuild.
class _ConsentRow extends StatefulWidget {
  const _ConsentRow({
    required this.accepted,
    required this.onChanged,
    required this.onTapPrivacy,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTapPrivacy;

  @override
  State<_ConsentRow> createState() => _ConsentRowState();
}

class _ConsentRowState extends State<_ConsentRow> {
  late final TapGestureRecognizer _privacyTap;

  @override
  void initState() {
    super.initState();
    _privacyTap = TapGestureRecognizer()..onTap = () => widget.onTapPrivacy();
  }

  @override
  void dispose() {
    _privacyTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Checkbox(
            value: widget.accepted,
            onChanged: (v) => widget.onChanged(v ?? false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => widget.onChanged(!widget.accepted),
            behavior: HitTestBehavior.opaque,
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Colors.black87,
                ),
                children: [
                  const TextSpan(
                    text:
                        "I have this customer's consent to save their details. ",
                  ),
                  TextSpan(
                    text: 'Privacy policy',
                    style: const TextStyle(
                      color: kPrimaryColor,
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: _privacyTap,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
