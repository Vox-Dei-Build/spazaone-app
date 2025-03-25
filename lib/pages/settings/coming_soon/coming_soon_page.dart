import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/page_header.dart';
import 'package:pasella/utils/support_util.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key});

  static const id = '/comingSoon';

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 4),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const PageHeader(),
                SizedBox(height: SizeConfig.heightMultiplier * 15),
                Icon(Icons.construction,
                    size: SizeConfig.imageSizeMultiplier * 15,
                    color: Colors.orange),
                SizedBox(height: SizeConfig.heightMultiplier * 3),
                Text(
                  '🚧 Big things are coming!',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 3,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 2),
                Text(
                  'We’re working on something exciting. This section will be live very soon!',
                  style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: SizeConfig.heightMultiplier * 5),
                FilledButton.icon(
                  onPressed: () => SupportUtil.sendWhatsAppMessage(
                      context, WhatsAppMessageType.feedback),
                  icon: Icon(FontAwesomeIcons.whatsapp,
                      size: SizeConfig.textMultiplier * 2),
                  label: Text(
                    "Leave Feedback",
                    style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
