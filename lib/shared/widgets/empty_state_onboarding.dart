import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';

/// PAS-AUTH-03: A reusable empty-state widget that mirrors the Stock
/// onboarding pattern (icon → headline → subtitle → primary CTA →
/// secondary video-walkthrough CTA). Hoisted out of
/// `lib/pages/stock/product_group_page/widgets/product_list.dart` so the
/// same affordances can be applied across Sales, Transactions,
/// Customers, Promotions and Templates without each page reinventing
/// (or skipping) the pattern.
///
/// - [icon]: the large muted glyph at the top. Caller picks something
///   contextual (inventory_2_outlined, point_of_sale, person_add, etc.).
/// - [headline]: short one-liner. The "why nothing is here" sentence.
/// - [subtitle]: the value-prop sentence. Optional but strongly
///   recommended — this is where the empty state earns its keep.
/// - [ctaLabel] + [onCtaTap]: the primary recovery action. If either is
///   null the button is omitted (e.g. when the CTA lives on a parent FAB
///   like Templates).
/// - [ctaIcon]: optional leading icon for the primary CTA. Defaults to
///   [Icons.add].
/// - [tutorialKey]: a constant from [TutorialConfig]. When non-null and
///   the remote config returns a non-empty URL, a "Watch a 2-min
///   walkthrough" TextButton renders below the primary CTA and opens
///   [LoomVideoPage]. Empty/missing config silently hides the link so
///   the widget never shows a button that goes nowhere.
/// - [tutorialTitle]: the title used by the LoomVideoPage app bar.
class EmptyStateOnboarding extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String? subtitle;
  final String? ctaLabel;
  final VoidCallback? onCtaTap;
  final IconData ctaIcon;
  final String? tutorialKey;
  final String tutorialTitle;

  const EmptyStateOnboarding({
    Key? key,
    required this.icon,
    required this.headline,
    this.subtitle,
    this.ctaLabel,
    this.onCtaTap,
    this.ctaIcon = Icons.add,
    this.tutorialKey,
    this.tutorialTitle = 'How to use Spaza One',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final hasCta = ctaLabel != null && onCtaTap != null;

    // Resolve the tutorial URL lazily — if remote config hasn't seeded a
    // URL for this surface yet we just hide the secondary CTA rather
    // than showing a button that opens a blank WebView.
    String? tutorialUrl;
    if (tutorialKey != null) {
      final url = TutorialConfig.getTutorialUrl(tutorialKey!);
      if (url.isNotEmpty) tutorialUrl = url;
    }

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: SizeConfig.imageSizeMultiplier * 6,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: SizeConfig.imageSizeMultiplier * 18,
              color: Colors.grey.withOpacity(0.5),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Text(
              headline,
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2.2,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              SizedBox(height: SizeConfig.heightMultiplier * 1),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: SizeConfig.textMultiplier * 1.6,
                  color: Colors.grey[700],
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (hasCta) ...[
              SizedBox(height: SizeConfig.heightMultiplier * 3),
              ElevatedButton.icon(
                onPressed: onCtaTap,
                icon: Icon(ctaIcon),
                label: Text(ctaLabel!),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: SizeConfig.imageSizeMultiplier * 6,
                    vertical: SizeConfig.heightMultiplier * 1.5,
                  ),
                ),
              ),
            ],
            if (tutorialUrl != null) ...[
              SizedBox(height: SizeConfig.heightMultiplier * 1),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LoomVideoPage(
                        loomUrl: tutorialUrl!,
                        title: tutorialTitle,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Watch a 2-min walkthrough'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
