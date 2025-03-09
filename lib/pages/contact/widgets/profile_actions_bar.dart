import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/contact/edit_contact/edit_contact.dart';
import 'package:pasella/pages/contact/view_model/customer_management_view_model.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/widgets/profile_image.dart';
import 'package:pasella/utils/auth_util.dart';
import 'package:provider/provider.dart';

class ProfileAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String customerName;
  final String customerId;
  final CustomerBalanceSummaryProvider customerBalanceSummaryProvider;
  final String? mobileNumber;
  final Function(String?) onProfileUpdated;

  const ProfileAppBar({
    Key? key,
    required this.customerId,
    required this.customerName,
    required this.customerBalanceSummaryProvider,
    this.mobileNumber,
    required this.onProfileUpdated,
  }) : super(key: key);

  @override
  _ProfileAppBarState createState() => _ProfileAppBarState();

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight); // Default AppBar height
}

class _ProfileAppBarState extends State<ProfileAppBar> {
  Future<void> _navigateToEditIfAllowed(
      BuildContext context, Widget page, Function(dynamic)? onResult) async {
    bool shouldProceed = await isAnonymousGate(context);
    if (!shouldProceed) return;

    final result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => page));

    if (result != null && onResult != null) {
      onResult(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    String name = widget.customerName;
    String number = widget.mobileNumber ?? '';

    return ChangeNotifierProvider(
      create: (_) => CustomerManagementViewModel(
        widget.customerId,
        widget.customerName,
        widget.customerBalanceSummaryProvider,
        widget.mobileNumber,
      ),
      child: Consumer<CustomerManagementViewModel>(
        builder: (context, viewModel, child) {
          return AppBar(
            leadingWidth: 30,
            title: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                profilePicture(
                    context, name, viewModel.profileImageUrl, number, true,
                    displayIcons: false),
                SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      _navigateToEditIfAllowed(
                        context,
                        EditCustomerPage(
                          customerId: widget.customerId,
                          customerName: widget.customerName,
                          customerBalanceSummaryProvider:
                              widget.customerBalanceSummaryProvider,
                          mobileNumber: widget.mobileNumber,
                        ),
                        (result) => widget.onProfileUpdated(result),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.customerName,
                          style: TextStyle(
                            fontSize: SizeConfig.textMultiplier *
                                2, // Responsive font size
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
                              widget.mobileNumber != null &&
                                      widget.mobileNumber!.isNotEmpty
                                  ? Icons.check_circle
                                  : Icons.error,
                              color: widget.mobileNumber != null &&
                                      widget.mobileNumber!.isNotEmpty
                                  ? Colors.green
                                  : Colors.red,
                              size: SizeConfig.textMultiplier * 1.5,
                            ),
                            SizedBox(width: SizeConfig.imageSizeMultiplier * 1),
                            Expanded(
                              child: Text(
                                widget.mobileNumber != null &&
                                        widget.mobileNumber!.isNotEmpty
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
                        customerId: widget.customerId,
                        customerName: widget.customerName,
                        customerBalanceSummaryProvider:
                            widget.customerBalanceSummaryProvider,
                        mobileNumber: widget.mobileNumber,
                      ),
                      (result) => widget.onProfileUpdated(result),
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
                          fontSize: SizeConfig.textMultiplier *
                              2, // Responsive font size
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
                          fontSize: SizeConfig.textMultiplier *
                              2, // Responsive font size
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
        },
      ),
    );
  }
}
