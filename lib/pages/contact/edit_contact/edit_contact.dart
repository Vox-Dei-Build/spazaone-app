import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:provider/provider.dart';

class EditCustomerPage extends StatelessWidget {
  final String customerId;
  final String customerName;
  final CustomerBalanceSummaryProvider customerBalanceSummaryProvider;
  final String? mobileNumber;

  const EditCustomerPage(
      {super.key,
      required this.customerId,
      required this.customerName,
      required this.customerBalanceSummaryProvider,
      this.mobileNumber});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CustomerManagementViewModel(customerId, customerName,
          customerBalanceSummaryProvider, mobileNumber),
      child: Consumer<CustomerManagementViewModel>(
        builder: (context, viewModel, child) {
          return Scaffold(
            appBar: const CustomAppBar(title: 'Edit Customer'),
            body: SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: LayoutConstants.padding20Horizontal,
                  child: Column(
                    children: [
                      _buildProfileImageSection(context, viewModel),
                      CustomTextField(
                        controller: viewModel.nameController,
                        hintText: 'Customer Name',
                        prefixIcon: Icons.person,
                        label: 'Customer Name',
                        textInputType: TextInputType.name,
                        maxLength: 20,
                        validator: (_) => viewModel.validateName(),
                      ),
                      CustomTextField(
                        controller: viewModel.numberController,
                        hintText: 'Mobile Number',
                        prefixIcon: Icons.phone,
                        label: 'Mobile Number',
                        textInputType: TextInputType.phone,
                        maxLength: 20,
                        validator: (_) => viewModel.validateNumber(),
                      ),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomButton(
                            title: 'Save Changes',
                            onTap: viewModel.isLoading
                                ? () {}
                                : () async {
                                    await viewModel
                                        .updateCustomerDetails(context);
                                  },
                            icon: Icons.save,
                          ),
                          if (viewModel.isLoading)
                            const CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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
            profilePicture(context, customerName, viewModel.profileImageUrl,
                mobileNumber, true,
                displayIcons: false, radius: SizeConfig.heightMultiplier * 9),
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
            fontSize: SizeConfig.textMultiplier * 1.6,
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
              onPressed: () => viewModel.handleImagePick(context),
            ),
          ],
        ),
      ],
    );
  }
}
