import 'package:flutter/material.dart';
import 'package:pasella/app_imports.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/pages/contact/connect/widgets/message_list_view.dart';
import 'package:pasella/pages/contact/view_model/connect_management_view_model.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';

class ConnectManagementPage extends StatefulWidget {
  final String customerId;
  final String? profileImageUrl;
  final String customerName;
  final String? mobileNumber;

  const ConnectManagementPage({
    super.key,
    required this.customerId,
    this.profileImageUrl,
    required this.customerName,
    this.mobileNumber,
  });

  @override
  _ConnectManagementPageState createState() => _ConnectManagementPageState();
}

class _ConnectManagementPageState extends State<ConnectManagementPage> {
  late ConnectManagementViewModel connectManagementViewModel;
  late CustomerBalanceSummaryProvider customerBalanceSummaryProvider;

  @override
  void initState() {
    super.initState();
    // Initialize the view model
    connectManagementViewModel = ConnectManagementViewModel(widget.customerId);
    // ✅ Call markMessagesAsRead when navigating to the page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.mobileNumber != null) {
        connectManagementViewModel.markMessagesAsRead(widget.mobileNumber);
      }
    });
  }

  @override
  void dispose() {
    connectManagementViewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return ValueListenableBuilder<bool>(
      valueListenable: connectManagementViewModel.loadingNotifier,
      builder: (context, isLoading, child) {
        return Stack(
          children: [
            child!,
            if (isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black45,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
      child: Scaffold(
        backgroundColor: WaBrandColour.chatBackground,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: SizeConfig.imageSizeMultiplier * 2.5,
              vertical: 0,
            ),
            child: Column(
              children: [
                ValueListenableBuilder<String?>(
                  valueListenable:
                      connectManagementViewModel.conversationWarningNotifier,
                  builder: (context, warning, _) {
                    if (warning == null || warning.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Material(
                      color: Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: Colors.orange.shade900,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                warning,
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: connectManagementViewModel.streamMessages(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Could not load messages. Please try again.',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: SizeConfig.textMultiplier * 2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return Center(
                          child: Text(
                            'No messages available.',
                            style: TextStyle(
                              fontSize: SizeConfig.textMultiplier * 2,
                            ),
                          ),
                        );
                      } else {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Expanded(
                              child: MessagesListView(
                                messages: snapshot.data!,
                                profileImageUrl: widget.profileImageUrl,
                                customerName: widget.customerName,
                              ),
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
