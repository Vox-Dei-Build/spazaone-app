import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/contact/view_model/add_contact_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/utils/show_toast.dart';
import 'package:provider/provider.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/shared/widgets/custom_divider.dart';
import 'package:pasella/pages/contact/add_contact/widgets/section_card.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/shared/widgets/profile_image.dart';

class AddContactPage extends StatelessWidget {
  const AddContactPage({super.key});
  static const id = '/addContactPage';

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AddContactViewModel(),
      child: Consumer<AddContactViewModel>(
        builder: (context, viewModel, child) {
          return Scaffold(
            appBar: const CustomAppBar(title: 'Add Contact'),
            body: SafeArea(
              child: Padding(
                padding: LayoutConstants.padding10Horizontal,
                child: Consumer<AppModel>(
                  builder: (context, model, child) {
                    return Stack(
                      children: [
                        Form(
                          key: viewModel
                              .formKey, // Use formKey from the ViewModel
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                CustomButton(
                                  onTap: () async {
                                    PermissionStatus status =
                                        await Permission.contacts.status;

                                    if (status.isDenied) {
                                      status =
                                          await Permission.contacts.request();
                                    }

                                    if (status.isGranted) {
                                      try {
                                        Contact? contact = await ContactsService
                                            .openDeviceContactPicker();
                                        if (contact != null) {
                                          String? phoneNumber =
                                              contact.phones?.first.value;
                                          if (phoneNumber != null &&
                                              phoneNumber.isNotEmpty) {
                                            viewModel.nameController.text =
                                                contact.displayName ?? '';
                                            viewModel.numberController.text =
                                                phoneNumber;
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
                                    } else {
                                      SchedulerBinding.instance
                                          .addPostFrameCallback((_) {
                                        showErrorSnackBar(
                                          context,
                                          "Contacts permission not granted :(",
                                        );
                                      });
                                    }
                                  },
                                  icon: Icons.contacts,
                                  title: 'Select Contact',
                                ),
                                SizedBox(
                                    height: SizeConfig.heightMultiplier * 2),
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
                                SizedBox(
                                    height: SizeConfig.heightMultiplier * 2),
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
                                    SizedBox(
                                        height:
                                            SizeConfig.heightMultiplier * 1),
                                    IconButton(
                                      icon: Icon(
                                        Icons.camera_alt,
                                        size:
                                            SizeConfig.imageSizeMultiplier * 8,
                                        color: Colors.green,
                                      ),
                                      onPressed: () async {
                                        await viewModel
                                            .handleImagePick(context);
                                      },
                                    ),
                                  ],
                                ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                        height:
                                            SizeConfig.heightMultiplier * 2),
                                    Text(
                                      '${model.selectedCustomerCategory} Details',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize:
                                              SizeConfig.textMultiplier * 2),
                                    ),
                                    SizedBox(
                                        height:
                                            SizeConfig.heightMultiplier * 2),
                                    SizedBox(
                                        height: SizeConfig.heightMultiplier * 2)
                                  ],
                                ),
                                SectionCard(
                                  children: [
                                    CustomTextField(
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
                                    CustomTextField(
                                      hintText:
                                          'Change it later via "Edit Customer"',
                                      prefixIcon: Icons.call,
                                      label: 'Mobile Number (Optional)',
                                      textInputType: TextInputType.number,
                                      maxLength: 10,
                                      controller: viewModel.numberController,
                                    ),
                                  ],
                                ),
                                CustomButton(
                                  onTap: viewModel.isLoading
                                      ? () {}
                                      : () async {
                                          if (viewModel.formKey.currentState!
                                              .validate()) {
                                            await viewModel
                                                .addCustomerToFirestore(
                                                    context, model);
                                          }
                                        },
                                  margin: const EdgeInsets.fromLTRB(
                                      10, 0, 10, 10.0),
                                  title: 'Confirm',
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (viewModel.isLoading)
                          const Center(
                            child: CircularProgressIndicator(),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
