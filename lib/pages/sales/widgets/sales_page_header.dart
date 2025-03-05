import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/shared/widgets/vimeo_video_player.dart';

class SalesPageHeader extends StatelessWidget {
  const SalesPageHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return PageHeader(
      actionWidget: Expanded(
        child: IconButton(
          icon: Icon(Icons.help_outline,
              color: Colors.black, size: SizeConfig.imageSizeMultiplier * 5),
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
      ),
    );
  }
}
