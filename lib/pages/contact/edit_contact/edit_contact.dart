import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:provider/provider.dart';

class EditCustomerPage extends StatelessWidget {
  final String customerId;
  final String customerName;
  final CustomerBalanceSummaryProvider customerBalanceSummaryProvider;
  final String? mobileNumber;

  EditCustomerPage(
      {required this.customerId,
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
            appBar: CustomAppBar(title: 'Edit Customer'),
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
                      ),
                      CustomTextField(
                        controller: viewModel.numberController,
                        hintText: 'Mobile Number',
                        prefixIcon: Icons.phone,
                        label: 'Mobile Number',
                        textInputType: TextInputType.phone,
                        maxLength: 20,
                      ),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomButton(
                            title: 'Save Changes',
                            onTap: viewModel.isLoading
                                ? () => null
                                : () async {
                                    await viewModel
                                        .updateCustomerDetails(context);
                                  },
                            icon: Icons.save,
                          ),
                          if (viewModel.isLoading)
                            CircularProgressIndicator(
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
        InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return Dialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Container(
                          padding: EdgeInsets.all(
                              SizeConfig.imageSizeMultiplier * 4),
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height * 0.8,
                            maxWidth: MediaQuery.of(context).size.width * 0.8,
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                viewModel.profileImage != null
                                    ? Image.file(viewModel.profileImage!)
                                    : viewModel.profileImageUrl != null
                                        ? Image.network(
                                            viewModel.profileImageUrl!)
                                        : CircleAvatar(
                                            radius:
                                                SizeConfig.imageSizeMultiplier *
                                                    15, // Responsive radius
                                            child: Icon(Icons.person,
                                                size: SizeConfig
                                                        .imageSizeMultiplier *
                                                    15),
                                          ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                  },
                                  child: Text('Close'),
                                )
                              ],
                            ),
                          )));
                },
              );
            },
            child: viewModel.profileImage != null
                ? CircleAvatar(
                    radius: SizeConfig.imageSizeMultiplier *
                        15, // Responsive radius
                    backgroundImage: FileImage(viewModel.profileImage!),
                  )
                : CircleAvatar(
                    radius: SizeConfig.imageSizeMultiplier *
                        15, // Responsive radius
                    backgroundImage: viewModel.profileImageUrl != null
                        ? CachedNetworkImageProvider(viewModel.profileImageUrl!)
                        : null,
                    backgroundColor: viewModel.profileImageUrl == null
                        ? Colors.grey[200]
                        : null,
                    child: viewModel.profileImageUrl == null
                        ? Icon(Icons.person,
                            size: SizeConfig.imageSizeMultiplier * 15)
                        : null,
                  )),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.camera_alt,
                  size: SizeConfig.imageSizeMultiplier * 8),
              onPressed: () => viewModel.handleImagePick(context),
            ),
          ],
        ),
      ],
    );
  }
}
