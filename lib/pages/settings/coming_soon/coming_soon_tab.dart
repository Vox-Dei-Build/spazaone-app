import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/utils/support_util.dart';

class ComingSoonTab extends StatelessWidget {
  const ComingSoonTab({super.key});

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: SizeConfig.imageSizeMultiplier * 5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction,
              size: SizeConfig.imageSizeMultiplier * 18,
              color: Colors.orange,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 3),
            Text(
              'Coming Soon 🚧',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2.6,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Text(
              'We’re working on something exciting here.\nHang tight!',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 4),
            FilledButton.icon(
              onPressed: () => SupportUtil.sendWhatsAppMessage(
                  context, WhatsAppMessageType.feedback),
              icon: Icon(FontAwesomeIcons.whatsapp,
                  size: SizeConfig.textMultiplier * 2),
              label: Text(
                'Leave Feedback',
                style: TextStyle(fontSize: SizeConfig.textMultiplier * 2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
