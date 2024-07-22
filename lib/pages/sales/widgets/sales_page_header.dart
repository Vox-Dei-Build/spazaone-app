import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/shared/widgets/vimeo_video_player.dart';

class SalesPageHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PageHeader(
      actionWidget: IconButton(
        icon: Icon(Icons.help_outline,
            color: Colors.black, size: SizeConfig.imageSizeMultiplier * 7),
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => VimeoVideoPage(
                videoId: '951892750',
                title: 'How to Capture Sales & Credit',
              ),
            ),
          );
        },
      ),
    );
  }
}
