import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/contact/view_model/add_contact_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/confirm_dialog.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:pasella/widgets/private_region.dart';
import 'package:provider/provider.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/shared/widgets/custom_divider.dart';
import 'package:pasella/pages/contact/add_contact/widgets/section_card.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/permission_helper.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:url_launcher/url_launcher.dart';

class AddContactPage extends StatelessWidget {
  const AddContactPage({super.key});
  static const id = '/addContactPage';
  static const _privacyPolicyUrl =
      'https://docs.google.com/document/d/1Oz4M_j8u0YwQBzIyDB-IAl_wYBNdrQ5k_Fx6qR7uPAQ/edit?tab=t.0';

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final uri = Uri.parse(_privacyPolicyUrl);
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
                appBar: const CustomAppBar(title: 'Add Contact'),
                body: SafeArea(
                  child: Padding(
                    padding: LayoutConstants.padding10Horizontal,
                    child: Consumer<AppModel>(
                      builder: (context, model, child) {
                        // Coerce to string so the header always renders
                        // even if AppModel hasn't selected a category yet.
                        final categoryLabel =
                            model.selectedCustomerCategory.toString();

                        return Form(
                          key: viewModel.formKey,
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                // Consent moved above the contact picker so
                                // the gate is visible before the action,
                                // not enforced via a runtime snackbar
                                // surprise.
                                CheckboxListTile(
                                  value: viewModel.contactConsentAccepted,
                                  onChanged: (value) => viewModel
                                      .setContactConsent(value ?? false),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'I confirm I have consent to upload this contact and understand Pasella securely stores the details so I can message the customer later.',
                                  ),
                                  subtitle: GestureDetector(
                                    onTap: () => _openPrivacyPolicy(context),
                                    child: const Text(
                                      'View Privacy Policy',
                                      style: TextStyle(
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                    height: LayoutConstants.spaceSm),
                                CustomButton(
                                  isDisabled:
                                      !viewModel.contactConsentAccepted,
                                  onTap: () async {
                                    final granted = await PermissionHelper
                                        .requestContacts(context);
                                    if (!granted) return;

                                    try {
                                      final Contact? contact =
                                          await FlutterContacts
                                              .openExternalPick();
                                      if (contact != null) {
                                        // Re-fetch with full details to ensure
                                        // phones are populated (some OEMs
                                        // return a stub from the picker).
                                        final fullContact =
                                            await FlutterContacts.getContact(
                                          contact.id,
                                          withProperties: true,
                                        );
                                        final phones =
                                            fullContact?.phones ?? contact.phones;
                                        final String? phoneNumber =
                                            phones.isNotEmpty
                                                ? phones.first.number
                                                : null;
                                        if (phoneNumber != null &&
                                            phoneNumber.isNotEmpty) {
                                          // PAS-UX-08: previously
                                          // `cleanPhoneNumber` was used as
                                          // a silent fallback when the
                                          // contact wasn't a valid SA
                                          // mobile, which dumped raw
                                          // digits (or junk) into the
                                          // field with no error. Now: if
                                          // the picked contact normalises
                                          // cleanly, write it; otherwise
                                          // tell the user explicitly so
                                          // they can hand-enter or pick a
                                          // different contact.
                                          final normalized =
                                              normalizePhoneNumber(phoneNumber);
                                          viewModel.nameController.text =
                                              (fullContact ?? contact)
                                                  .displayName;
                                          if (normalized.isNotEmpty) {
                                            viewModel.numberController.text =
                                                normalized;
                                          } else {
                                            viewModel.numberController.text =
                                                '';
                                            SchedulerBinding.instance
                                                .addPostFrameCallback((_) {
                                              showErrorSnackBar(
                                                context,
                                                kSAOnlyPhoneMessage,
                                                isWarning: true,
                                              );
                                            });
                                          }
                                        } else {
                                          SchedulerBinding.instance
                                              .addPostFrameCallback((_) {
                                            showErrorSnackBar(context,
                                                "This contact does not have a number.",
                                                isWarning: true);
                                          });
                                        }
                                      }
                                    } catch (e) {
                                      SchedulerBinding.instance
                                          .addPostFrameCallback((_) {
                                        showErrorSnackBar(
                                          context,
                                          "Failed to get contact :(",
                                          isWarning: true,
                                        );
                                      });
                                    }
                                  },
                                  icon: Icons.contacts,
                                  title: 'Select Contact',
                                ),
                                const SizedBox(
                                    height: LayoutConstants.spaceMd),
                                Row(
                                  children: [
                                    const CustomDivider(),
                                    Text(
                                      'OR',
                                      style: TextStyle(
                                          color: kSecondaryColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize:
                                              SizeConfig.textMultiplier * 1.8),
                                    ),
                                    const CustomDivider(),
                                  ],
                                ),
                                const SizedBox(
                                    height: LayoutConstants.spaceMd),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    profilePicture(
                                      context,
                                      viewModel.nameController.text,
                                      null,
                                      viewModel.numberController.text,
                                      false,
                                      displayIcons: true,
                                      radius: SizeConfig.heightMultiplier * 9,
                                      profileImage: viewModel.profileImage,
                                    ),
                                    const SizedBox(
                                        height: LayoutConstants.spaceXs),
                                    IconButton(
                                      tooltip: 'Add profile photo',
                                      iconSize:
                                          SizeConfig.imageSizeMultiplier * 8,
                                      icon: const Icon(
                                        Icons.camera_alt,
                                        color: Colors.green,
                                      ),
                                      onPressed: () async {
                                        await viewModel
                                            .handleImagePick(context);
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                    height: LayoutConstants.spaceMd),
                                Text(
                                  '$categoryLabel Details',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize:
                                          SizeConfig.textMultiplier * 2),
                                ),
                                const SizedBox(
                                    height: LayoutConstants.spaceMd),
                                SectionCard(
                                  children: [
                                    PrivateRegion(
                                      child: CustomTextField(
                                        hintText: 'Customer Name',
                                        prefixIcon: Icons.person,
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
                                        hintText:
                                            'Change it later via "Edit Customer"',
                                        prefixIcon: Icons.call,
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
                                  ],
                                ),
                                const SizedBox(
                                    height: LayoutConstants.spaceMd),
                                // Real disabled state via the
                                // `isDisabled` prop — replaces the
                                // `onTap: isLoading ? () {} : ...`
                                // pattern that left the button looking
                                // tappable while no-oping.
                                CustomButton(
                                  isDisabled: viewModel.isLoading,
                                  onTap: () async {
                                    if (viewModel.formKey.currentState
                                            ?.validate() ??
                                        false) {
                                      await viewModel.addCustomerToFirestore(
                                          context, model);
                                    }
                                  },
                                  margin: const EdgeInsets.fromLTRB(
                                      10, 0, 10, 10.0),
                                  title: viewModel.isLoading
                                      ? 'Saving…'
                                      : 'Confirm',
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
            ),
          );
        },
      ),
    );
  }
}
