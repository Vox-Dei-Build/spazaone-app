import 'package:flutter/material.dart';
import 'package:pasella/shared/widgets/tutorial_page_body.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/support_util.dart';

class LoomVideoPage extends StatefulWidget {
  final String loomUrl; // Full Loom URL
  final String title;

  const LoomVideoPage({Key? key, required this.loomUrl, required this.title})
      : super(key: key);

  @override
  State<LoomVideoPage> createState() => _LoomVideoPageState();
}

class _LoomVideoPageState extends State<LoomVideoPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.loomUrl));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: CustomAppBar(
          title:
              widget.title.isNotEmpty ? widget.title : 'How to use Spaza One',
        ),
        body: TutorialPageBody(
          video: WebViewWidget(controller: _controller),
          onSupport: () => SupportUtil.sendWhatsAppMessage(
              context, WhatsAppMessageType.support),
        ),
      );
}
