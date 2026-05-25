import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';
import 'package:pasella/shared/widgets/page_header.dart';

class SalesPageHeader extends StatelessWidget {
  const SalesPageHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return PageHeader(
      actionWidget: IconButton(
          icon: Icon(Icons.help_outline,
              color: Colors.black, size: SizeConfig.imageSizeMultiplier * 5),
          onPressed: () {
            final url = TutorialConfig.getTutorialUrl(
                TutorialConfig.TUTORIAL_CAPTURE_SALES);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => LoomVideoPage(
                  loomUrl: url,
                  title: 'How to Capture Sales',
                ),
              ),
            );
          }),
    );
  }
}
