import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/config/size_config.dart';
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
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final double videoHeight = SizeConfig.heightMultiplier * 70;
    final double videoWidth = SizeConfig.imageSizeMultiplier * 90;
    final double spacing = SizeConfig.blockSizeVertical * 3;

    return Scaffold(
      appBar: CustomAppBar(
        title: widget.title.isNotEmpty ? widget.title : 'How to use Spaza One',
      ),
      body: Padding(
        padding: LayoutConstants.padding10Horizontal,
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
