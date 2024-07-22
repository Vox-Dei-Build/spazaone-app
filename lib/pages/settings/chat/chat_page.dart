import 'package:flutter/material.dart';
import 'package:flutter_tawk/flutter_tawk.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/phone_util.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  static const id = '/chatPage';

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  String name = '';
  String mobileNumber = '';
  String shopName = '';

  @override
  void initState() {
    super.initState();
    fetchUserDetails();
  }

  Future<void> fetchUserDetails() async {
    final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    shopName = await fetchShopNameForUser(userId) ?? '';
    mobileNumber = await fetchNumberForUser(userId) ?? '';
    name = await fetchNameForUser(userId) ?? '';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(title: 'Support Chat'),
      body: Tawk(
        directChatLink:
            'https://tawk.to/chat/661f559e1ec1082f04e34d2e/1hrl6ctgl',
        visitor: TawkVisitor(
          name: name,
          email: mobileNumber,
        ),
        onLoad: () {
          print('Hello $name! How can we help you today?');
        },
        onLinkTap: (String url) {
          print('There is a link $url');
        },
      ),
    );
  }
}
