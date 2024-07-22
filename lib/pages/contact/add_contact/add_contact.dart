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
            appBar: CustomAppBar(title: 'Add Contact'),
            body: SafeArea(
              child: Padding(
                padding: LayoutConstants.padding20Horizontal,
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
                                          if (phoneNumber != null) {
                                            viewModel.nameController.text =
                                                contact.displayName ?? '';
                                            viewModel.numberController.text =
                                                phoneNumber;
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
                                    CustomDivider(),
                                    Text(
                                      'OR',
                                      style: TextStyle(
                                          color: kSecondaryColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize:
                                              SizeConfig.textMultiplier * 1.8),
                                    ),
                                    CustomDivider(),
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
                                    GestureDetector(
                                      onTap: () => viewModel.pickImage(context),
                                      child: CircleAvatar(
                                        radius: 50,
                                        backgroundImage: viewModel
                                                    .profileImage !=
                                                null
                                            ? FileImage(viewModel.profileImage!)
                                            : null,
                                        child: viewModel.profileImage == null &&
                                                viewModel.profileImageUrl ==
                                                    null
                                            ? Icon(Icons.camera_alt,
                                                size:
                                                    SizeConfig.textMultiplier *
                                                        3,
                                                color: Colors.grey)
                                            : null,
                                      ),
                                    ),
                                    SizedBox(
                                        height: SizeConfig.heightMultiplier * 2)
                                  ],
                                ),
                                SectionCard(
                                  children: [
                                    CustomTextField(
                                      hintText: 'User name',
                                      prefixIcon: Icons.person,
                                      label: 'Name*',
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
                                      hintText: 'XXXXXXXXXX (Optional)',
                                      prefixIcon: Icons.call,
                                      label: 'Number',
                                      textInputType: TextInputType.number,
                                      maxLength: 10,
                                      controller: viewModel.numberController,
                                    ),
                                  ],
                                ),
                                CustomButton(
                                  onTap: viewModel.isLoading
                                      ? () => null
                                      : () async {
                                          if (viewModel.formKey.currentState!
                                              .validate()) {
                                            await viewModel
                                                .uploadProfileImage();
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
                          Center(
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
