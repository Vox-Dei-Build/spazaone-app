import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/support_util.dart'; // <- Add this
import 'package:vimeo_player_flutter/vimeo_player_flutter.dart';

class VimeoVideoPage extends StatelessWidget {
  final String videoId;
  final String title;

  const VimeoVideoPage({Key? key, required this.videoId, required this.title})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final double videoHeight = SizeConfig.heightMultiplier * 50;
    final double videoWidth = SizeConfig.imageSizeMultiplier * 90;
    final double spacing = SizeConfig.blockSizeVertical * 3;

    return Scaffold(
      appBar: CustomAppBar(
        title: title.isNotEmpty ? title : 'How to use Pasella',
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
                child: VimeoPlayer(videoId: videoId),
              ),
            ),
            SizedBox(height: spacing),
            ElevatedButton.icon(
              icon: const Icon(FontAwesomeIcons.whatsapp),
              label: Text('Talk to support',
                  style: TextStyle(fontSize: SizeConfig.textMultiplier * 2)),
              onPressed: () => SupportUtil.sendSupportWhatsAppMessage(context),
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
