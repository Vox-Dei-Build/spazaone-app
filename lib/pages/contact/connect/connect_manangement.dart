import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/contact/connect/widgets/message_list_view.dart';
import 'package:pasella/pages/contact/view_model/connect_management_view_model.dart';
import 'package:pasella/providers/customer_balance_summary_provider.dart';
import 'package:pasella/shared/widgets/spaza_shimmer.dart';

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
  State<ConnectManagementPage> createState() => _ConnectManagementPageState();
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
    return ValueListenableBuilder<bool>(
      valueListenable: connectManagementViewModel.loadingNotifier,
      builder: (context, isLoading, child) {
        return Stack(
          children: [
            child!,
            if (isLoading)
              const Positioned.fill(
                child: ColoredBox(
                  color: SpazaColors.canvas,
                  child: SpazaListSkeleton(
                    semanticsLabel: 'Loading customer messages',
                    itemCount: 5,
                  ),
                ),
              ),
          ],
        );
      },
      child: Scaffold(
        backgroundColor: SpazaColors.canvas,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
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
                        return const SpazaListSkeleton(
                          semanticsLabel: 'Loading customer messages',
                          itemCount: 5,
                        );
                      } else if (snapshot.hasError) {
                        return const Center(
                          child: Text(
                            'Could not load messages. Please try again.',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Center(
                          child: Text(
                            'No messages available.',
                            style: TextStyle(
                              fontSize: 18,
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
