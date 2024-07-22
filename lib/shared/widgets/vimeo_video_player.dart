import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:vimeo_player_flutter/vimeo_player_flutter.dart';

class VimeoVideoPage extends StatelessWidget {
  final String videoId;
  final String title;

  VimeoVideoPage({Key? key, required this.videoId, required this.title})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Scaffold(
      appBar:
          CustomAppBar(title: title.isNotEmpty ? title : 'How to use Pasella'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final videoHeight =
              SizeConfig.heightMultiplier * 50; // 50% of the screen height
          final videoWidth =
              SizeConfig.imageSizeMultiplier * 90; // 90% of the screen width

          return Center(
            child: Container(
              height: videoHeight,
              width: videoWidth,
              child: VimeoPlayer(
                videoId: videoId,
              ),
            ),
          );
        },
      ),
    );
  }
}
