import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/contact/edit_contact/edit_contact.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:provider/provider.dart';

class ProfileAppBar extends StatefulWidget implements PreferredSizeWidget {
  final CustomerBalanceSummaryProvider customerBalanceSummaryProvider;

  const ProfileAppBar({
    Key? key,
    required this.customerBalanceSummaryProvider,
  }) : super(key: key);

  @override
  _ProfileAppBarState createState() => _ProfileAppBarState();

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight); // Default AppBar height
}

class _ProfileAppBarState extends State<ProfileAppBar> {
  Future<void> _navigateToEditIfAllowed(
      BuildContext context, Widget page) async {
    bool shouldProceed = await isAnonymousGate(context);
    if (!shouldProceed) return;

    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => page));
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final viewModel =
        Provider.of<CustomerManagementViewModel>(context, listen: true);
    String customerName = viewModel.customerName;
    String mobileNumber = viewModel.mobileNumber ?? '';

    return AppBar(
      leadingWidth: 30,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          profilePicture(context, customerName, viewModel.profileImageUrl,
              mobileNumber, true,
              displayIcons: false, profileImage: viewModel.profileImage),
          SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
          Expanded(
            child: InkWell(
              onTap: () {
                _navigateToEditIfAllowed(
                  context,
                  EditCustomerPage(
                    viewModel: viewModel,
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customerName,
                    style: TextStyle(
                      fontSize:
                          SizeConfig.textMultiplier * 2, // Responsive font size
                      fontWeight: FontWeight.w900,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign
                        .start, // Changed to start for better alignment
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        mobileNumber.isNotEmpty
                            ? Icons.check_circle
                            : Icons.error,
                        color:
                            mobileNumber.isNotEmpty ? Colors.green : Colors.red,
                        size: SizeConfig.textMultiplier * 1.5,
                      ),
                      SizedBox(width: SizeConfig.imageSizeMultiplier * 1),
                      Expanded(
                        child: Text(
                          mobileNumber.isNotEmpty
                              ? "Mobile number available"
                              : "No mobile number",
                          style: TextStyle(
                            fontSize: SizeConfig.textMultiplier * 1.5,
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (String value) async {
            if (value == 'reminder') {
              bool shouldProceed = await isAnonymousGate(context);
              if (shouldProceed) {
                viewModel.handleReminderTap(context);
              }
            } else if (value == 'edit') {
              _navigateToEditIfAllowed(
                context,
                EditCustomerPage(
                  viewModel: viewModel,
                ),
              );
            } else if (value == 'delete') {
              viewModel.deleteCustomer(context);
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'reminder',
              child: ListTile(
                leading: const Icon(Icons.sms_outlined),
                title: Text(
                  'Send Payment Reminder',
                  style: TextStyle(
                    fontSize:
                        SizeConfig.textMultiplier * 2, // Responsive font size
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            PopupMenuItem<String>(
              value: 'edit',
              child: ListTile(
                leading: const Icon(Icons.create_outlined),
                title: Text(
                  'Edit Customer',
                  style: TextStyle(
                    fontSize:
                        SizeConfig.textMultiplier * 2, // Responsive font size
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  'Delete Customer',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2,
                    fontWeight: FontWeight.w900,
                    color: Colors.red, // Highlight delete option in red
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
