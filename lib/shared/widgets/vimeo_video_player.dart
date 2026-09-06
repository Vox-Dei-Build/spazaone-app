import 'package:flutter/material.dart';
import 'package:pasella/shared/widgets/tutorial_page_body.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/support_util.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Vimeo video page implemented via webview_flutter directly. The previous
/// implementation used vimeo_player_flutter which depended on the legacy
/// webview_flutter 3.x and blocked migration to the 4.x API required for
/// Flutter 3.29 and 16 KB page size compliance.
class VimeoVideoPage extends StatefulWidget {
  final String videoId;
  final String title;

  const VimeoVideoPage({Key? key, required this.videoId, required this.title})
      : super(key: key);

  @override
  State<VimeoVideoPage> createState() => _VimeoVideoPageState();
}

class _VimeoVideoPageState extends State<VimeoVideoPage> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(
        Uri.parse('https://player.vimeo.com/video/${widget.videoId}'),
      );
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
