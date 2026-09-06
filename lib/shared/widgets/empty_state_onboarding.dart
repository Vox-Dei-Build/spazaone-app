import 'package:flutter/material.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/config/tutorial_config.dart';
import 'package:pasella/shared/widgets/loom_video_page.dart';
import 'package:pasella/shared/widgets/responsive_app_layout.dart';

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
    final theme = Theme.of(context);

    final hasCta = ctaLabel != null && onCtaTap != null;

    // Resolve the tutorial URL lazily — if remote config hasn't seeded a
    // URL for this surface yet we just hide the secondary CTA rather
    // than showing a button that opens a blank WebView.
    String? tutorialUrl;
    if (tutorialKey != null) {
      final url = TutorialConfig.getTutorialUrl(tutorialKey!);
      if (url.isNotEmpty) tutorialUrl = url;
    }

    return ScrollableCenteredContent(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: SpazaColors.muted,
          ),
          const SizedBox(height: 16),
          Text(
            headline,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: SpazaColors.muted),
              textAlign: TextAlign.center,
            ),
          ],
          if (hasCta) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onCtaTap,
              icon: Icon(ctaIcon),
              label: Text(ctaLabel!),
            ),
          ],
          if (tutorialUrl != null) ...[
            const SizedBox(height: 8),
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
    );
  }
}
