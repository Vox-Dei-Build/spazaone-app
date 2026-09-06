import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/design/spaza_tokens.dart';

/// Keep support reachable below the native player on short screens and large text.
class TutorialPageBody extends StatelessWidget {
  const TutorialPageBody(
      {super.key, required this.video, required this.onSupport});
  final Widget video;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final height = (constraints.maxHeight * .72).clamp(180.0, 560.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(SpazaRadius.surface),
                  child: SizedBox(height: height, child: video),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: onSupport,
                  icon: const Icon(FontAwesomeIcons.whatsapp),
                  label: const Text('Talk to support'),
                ),
              ],
            ),
          );
        }),
      );
}
