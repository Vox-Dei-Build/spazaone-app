import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/config/size_config.dart';
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
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final double videoHeight = SizeConfig.heightMultiplier * 50;
    final double videoWidth = SizeConfig.imageSizeMultiplier * 90;
    final double spacing = SizeConfig.blockSizeVertical * 3;

    return Scaffold(
      appBar: CustomAppBar(
        title: widget.title.isNotEmpty ? widget.title : 'How to use Pasella',
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.blockSizeHorizontal * 5,
          vertical: SizeConfig.blockSizeVertical * 2,
        ),
        child: Column(
          children: [
            Center(
              child: SizedBox(
                height: videoHeight,
                width: videoWidth,
                child: WebViewWidget(controller: _controller),
              ),
            ),
            SizedBox(height: spacing),
            ElevatedButton.icon(
              icon: const Icon(FontAwesomeIcons.whatsapp),
              label: Text('Talk to support',
                  style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
              onPressed: () => SupportUtil.sendWhatsAppMessage(
                  context, WhatsAppMessageType.support),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: SizeConfig.blockSizeHorizontal * 5,
                  vertical: SizeConfig.blockSizeVertical * 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
