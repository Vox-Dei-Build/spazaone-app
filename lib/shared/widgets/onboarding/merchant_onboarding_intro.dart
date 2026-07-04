import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';

/// One-time onboarding intro bottom sheet.
///
/// Two slides — customer, then product — that mirror the first two
/// steps of the [MerchantSetupCard] the merchant will see when the
/// sheet dismisses. The old 4-slide version taught contradictory
/// ordering (customer, then a growth aspirational slide, then
/// product, then a "link product to a transaction" usage tip that
/// jumped ahead of setup) and shipped two equal-weight terminal CTAs
/// that broke the customer-first rule the sheet had just taught.
///
/// The sheet is an ad for the setup card, not a rival to it.
class MerchantOnboardingIntro extends StatefulWidget {
  const MerchantOnboardingIntro({
    super.key,
    required this.onOpenCustomers,
    required this.onOpenProducts,
  });

  final VoidCallback onOpenCustomers;
  final VoidCallback onOpenProducts;

  @override
  State<MerchantOnboardingIntro> createState() =>
      _MerchantOnboardingIntroState();
}

enum MerchantOnboardingIntroAction { openCustomers, openProducts }

class _MerchantOnboardingIntroState extends State<MerchantOnboardingIntro> {
  final PageController _controller = PageController();
  int _index = 0;

  static const List<_IntroSlide> _slides = [
    _IntroSlide(
      icon: Icons.person_add_alt_1_outlined,
      title: 'Start with one customer',
      body:
          'Save one real customer so you can record Pay Later transactions and send WhatsApp confirmations right away.',
      bullets: [
        'Pasella guides you from Customers',
        'Pay Later opens after saving',
      ],
    ),
    _IntroSlide(
      icon: Icons.inventory_2_outlined,
      title: 'Then add your first product',
      body:
          'One product unlocks item-level sales, stock detail and WhatsApp ordering. Start with the item you sell most often.',
      bullets: [
        'Products power sales, stock and reports',
        'List items for WhatsApp ordering next',
      ],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isLast = _index == _slides.length - 1;
    final mediaSize = MediaQuery.sizeOf(context);
    // 38% of viewport height — a fixed proportion that keeps the
    // sheet's PageView roomy on phones and sensible on tablets, with
    // an absolute floor and ceiling so extreme viewports don't crush
    // or bloat the slide.
    final slideHeight = (mediaSize.height * 0.38).clamp(240.0, 380.0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LayoutConstants.spaceXl,
          LayoutConstants.spaceLg,
          LayoutConstants.spaceXl,
          LayoutConstants.spaceLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: LayoutConstants.spaceLg),
            Text(
              'Set up your shop',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LayoutConstants.spaceXs),
            Text(
              'Two quick steps unlock the whole app.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(
                  alpha: 0.75,
                ),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(
              height: slideHeight,
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder:
                    (context, index) => _SlideView(slide: _slides[index]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: i == _index ? 18 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color:
                        i == _index
                            ? primary
                            : theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            const SizedBox(height: LayoutConstants.spaceLg),
            if (!isLast)
              Row(
                children: [
                  TextButton(onPressed: _dismiss, child: const Text('Later')),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      // Explicit min size — `Size.fromHeight(44)` sets
                      // min width to infinity, which explodes inside a
                      // Row. Keep the 44-dp touch target height and a
                      // sensible min width instead.
                      minimumSize: const Size(
                        96,
                        LayoutConstants.minTouchTarget,
                      ),
                      backgroundColor: primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Next'),
                  ),
                ],
              )
            else
              // Terminal slide: a single primary CTA that opens
              // Customers — the setup card takes over from there.
              // "Later" stays available for merchants who want to
              // browse first.
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      _dismiss(MerchantOnboardingIntroAction.openCustomers);
                    },
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Start with a customer'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        LayoutConstants.minTouchTarget,
                      ),
                      backgroundColor: primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: LayoutConstants.spaceSm),
                  Center(
                    child: TextButton(
                      onPressed: _dismiss,
                      child: const Text('Later'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _dismiss([MerchantOnboardingIntroAction? action]) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop(action);
      return;
    }

    // Tests and any future inline render can mount the intro outside a modal
    // route. Preserve the existing callback contract in that case only.
    switch (action) {
      case MerchantOnboardingIntroAction.openCustomers:
        widget.onOpenCustomers();
      case MerchantOnboardingIntroAction.openProducts:
        widget.onOpenProducts();
      case null:
        break;
    }
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _IntroSlide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: LayoutConstants.spaceXs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: LayoutConstants.spaceLg),
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(slide.icon, size: 44, color: primary),
            ),
          ),
          const SizedBox(height: LayoutConstants.spaceLg),
          Text(
            slide.title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: LayoutConstants.spaceSm),
          Text(
            slide.body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.85),
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: LayoutConstants.spaceLg),
          ...slide.bullets.map(
            (text) => Padding(
              padding: const EdgeInsets.only(bottom: LayoutConstants.spaceSm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_outline, size: 20, color: primary),
                  const SizedBox(width: LayoutConstants.spaceSm),
                  Expanded(
                    child: Text(text, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroSlide {
  const _IntroSlide({
    required this.icon,
    required this.title,
    required this.body,
    required this.bullets,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;
}
