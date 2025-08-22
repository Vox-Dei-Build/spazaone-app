import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class ErrorEmpty extends StatelessWidget {
  const ErrorEmpty(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.icon});
  final String title;
  final String subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: SizeConfig.imageSizeMultiplier * 12,
                color: Theme.of(context).colorScheme.primary),
            SizedBox(height: SizeConfig.heightMultiplier * 1.2),
            Text(title,
                style: TextStyle(
                    fontSize: SizeConfig.textMultiplier * 2.2,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: SizeConfig.textMultiplier * 1.7)),
          ],
        ),
      ),
    );
  }
}
