import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';
import 'package:pasella/shared/widgets/primary_workspace_header.dart';

class SalesPageHeader extends StatelessWidget {
  const SalesPageHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const PrimaryWorkspaceHeader(shareSource: 'sales_header');
  }
}

class SalesHelpAction extends StatelessWidget {
  const SalesHelpAction({
    super.key,
    required this.showMarketingHelp,
  });

  final bool showMarketingHelp;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        icon: Icon(
          Icons.help_outline,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: SizeConfig.imageSizeMultiplier * 5,
        ),
        onPressed: () {
          final url = TutorialConfig.getTutorialUrl(
            showMarketingHelp
                ? TutorialConfig.TUTORIAL_RUN_PROMOTIONS
                : TutorialConfig.TUTORIAL_CAPTURE_SALES,
          );
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => LoomVideoPage(
                loomUrl: url,
                title: showMarketingHelp
                    ? 'How to Run Promotions'
                    : 'How to Capture Sales',
              ),
            ),
          );
        },
        tooltip: showMarketingHelp ? 'Marketing help' : 'Sales help',
      ),
    );
  }
}
