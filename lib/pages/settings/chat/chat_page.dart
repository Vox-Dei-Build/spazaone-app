import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/phone_util.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Support chat page. Was previously implemented with `flutter_tawk` which
/// pinned webview_flutter 3.x and blocked the migration to webview_flutter
/// 4.x required for Flutter 3.29 / 16 KB page size compliance. We embed the
/// Tawk direct-chat URL directly in a WebViewWidget; visitor name/email are
/// pre-populated via Tawk's standard `?name=&email=` query parameters.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  static const id = '/chatPage';

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const String _baseChatUrl =
      'https://tawk.to/chat/661f559e1ec1082f04e34d2e/1hrl6ctgl';

  String name = '';
  String mobileNumber = '';
  String shopName = '';
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(_baseChatUrl));
    fetchUserDetails();
  }

  Future<void> fetchUserDetails() async {
    final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    shopName = await fetchShopNameForUser(userId) ?? '';
    mobileNumber = await fetchNumberForUser(userId) ?? '';
    name = await fetchNameForUser(userId) ?? '';
    if (!mounted) return;
    final uri = Uri.parse(_baseChatUrl).replace(queryParameters: {
      if (name.isNotEmpty) 'name': name,
      if (mobileNumber.isNotEmpty) 'email': mobileNumber,
    });
    _controller?.loadRequest(uri);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Support Chat'),
      body: _controller == null
          ? const Center(child: CircularProgressIndicator())
          : WebViewWidget(controller: _controller!),
    );
  }
}
