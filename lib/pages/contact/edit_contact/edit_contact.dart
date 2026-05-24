import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/widgets/private_region.dart';

class EditCustomerPage extends StatefulWidget {
  final CustomerManagementViewModel viewModel;

  const EditCustomerPage({super.key, required this.viewModel});

  @override
  _EditCustomerPageState createState() => _EditCustomerPageState();
}

class _EditCustomerPageState extends State<EditCustomerPage> {
  @override
  Widget build(BuildContext context) {
    var viewModel = widget.viewModel;
    return Scaffold(
      appBar: const CustomAppBar(title: 'Edit Customer'),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: LayoutConstants.padding10Horizontal,
            child: Column(
              children: [
                _buildProfileImageSection(context, viewModel),
                PrivateRegion(
                  child: CustomTextField(
                    controller: viewModel.nameController,
                    hintText: 'Customer Name',
                    prefixIcon: Icons.person,
                    label: 'Customer Name',
                    textInputType: TextInputType.name,
                    maxLength: 20,
                    validator: (_) => viewModel.validateName(),
                  ),
                ),
                PrivateRegion(
                  child: CustomTextField(
                    controller: viewModel.numberController,
                    hintText: 'Mobile Number',
                    prefixIcon: Icons.phone,
                    label: 'Mobile Number',
                    textInputType: TextInputType.phone,
                    maxLength: 20,
                    validator: (_) => viewModel.validateNumber(),
                  ),
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomButton(
                      title: 'Save Changes',
                      onTap: widget.viewModel.isLoading
                          ? () {} // Prevent multiple taps while loading
                          : () async {
                              setState(
                                  () {}); // 🔥 Ensure UI reflects loading state
                              await widget.viewModel
                                  .updateCustomerDetails(context);
                            },
                      icon: Icons.save,
                    ),
                    if (viewModel.isLoading)
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileImageSection(
      BuildContext context, CustomerManagementViewModel viewModel) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            profilePicture(context, viewModel.customerName,
                viewModel.profileImageUrl, viewModel.mobileNumber, true,
                displayIcons: true,
                radius: SizeConfig.heightMultiplier * 9,
                profileImage: viewModel.profileImage),
          ],
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 2),
        Text(
          "Upload Profile Picture",
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 2,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: SizeConfig.heightMultiplier * 1),
        Text(
          "Profile picture will only be saved when you tap 'Save'",
          style: TextStyle(
            fontSize: SizeConfig.textMultiplier * 1.5,
            color: Colors.grey[600],
            fontStyle: FontStyle.italic,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(width: SizeConfig.imageSizeMultiplier * 2), // Adds spacing
            IconButton(
              icon: Icon(
                Icons.camera_alt,
                size: SizeConfig.imageSizeMultiplier * 8,
                color: Colors.green, // Make icon color pop
              ),
              onPressed: () async {
                await widget.viewModel.handleImagePick(context);
                if (!mounted) return;
                setState(() {}); // 🔥 Force UI to rebuild after selecting an image
              },
            ),
          ],
        ),
      ],
    );
  }
}
