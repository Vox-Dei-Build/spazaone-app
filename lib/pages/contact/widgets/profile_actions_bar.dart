import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/pages/contact/edit_contact/edit_contact.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:pasella/widgets/private_region.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

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
              displayIcons: true, profileImage: viewModel.profileImage),
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
              // Customer name in the AppBar pairs with balances elsewhere on
              // this page; mask the visible identity but keep tap handling.
              child: PrivateRegion(
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
                  SizedBox(height: SizeConfig.heightMultiplier * 0.3),
                  if (viewModel.isLoading)
                    Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: SizeConfig.heightMultiplier * 0.5,
                              horizontal: SizeConfig.imageSizeMultiplier * 2),
                          child: Shimmer.fromColors(
                            baseColor: Colors.black12,
                            highlightColor: Colors.black26,
                            child: Container(
                              width: SizeConfig.imageSizeMultiplier * 15,
                              height: SizeConfig.heightMultiplier * 1,
                              decoration: BoxDecoration(
                                color: Colors.grey,
                                borderRadius: BorderRadius.all(Radius.circular(
                                    SizeConfig.imageSizeMultiplier * 2)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (!viewModel.isLoading)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          mobileNumber.isNotEmpty
                              ? viewModel.hasWhatsApp
                                  ? FontAwesomeIcons.whatsapp
                                  : Icons.sms_outlined
                              : Icons.error,
                          color: mobileNumber.isNotEmpty
                              ? viewModel.hasWhatsApp
                                  ? WaBrandColour.tealGreenLighter
                                  : Colors.blue
                              : Colors.red,
                          size: SizeConfig.textMultiplier * 1.5,
                        ),
                        SizedBox(width: SizeConfig.imageSizeMultiplier * 1),
                        Expanded(
                          child: Text(
                            mobileNumber.isNotEmpty
                                ? viewModel.hasWhatsApp
                                    ? "Uses WhatsApp"
                                    : "Likely Only SMS"
                                : "No mobile number",
                            style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 1.5,
                              color: Colors.grey,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                ],
                ),
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
