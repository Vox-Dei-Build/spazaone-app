import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

class MerchantOnboardingIntro extends StatefulWidget {
  const MerchantOnboardingIntro({super.key, required this.onOpenProducts});

  final VoidCallback onOpenProducts;

  @override
  State<MerchantOnboardingIntro> createState() =>
      _MerchantOnboardingIntroState();
}

class _MerchantOnboardingIntroState extends State<MerchantOnboardingIntro> {
  final PageController _controller = PageController();
  int _index = 0;

  static const List<_IntroSlide> _slides = [
    _IntroSlide(
      icon: Icons.storefront_outlined,
      title: 'WhatsApp Store setup',
      body:
          'Your WhatsApp Store is the customer-facing ordering surface. Only products you list for WhatsApp ordering appear there; everything else stays internal.',
      bullets: [
        'Start with products customers can actually order',
        'Keep internal-only stock unlisted',
        'Add a bank account before deposits or withdrawals',
      ],
    ),
    _IntroSlide(
      icon: Icons.inventory_2_outlined,
      title: 'Products',
      body:
          'Products are your stock and catalogue. Use them for prices, quantities, product photos, profit detail, and deciding what belongs in WhatsApp ordering.',
      bullets: [
        'Turn on WhatsApp listing only for customer-facing items',
        'Leave ingredients, supplies, or unavailable items internal',
      ],
    ),
    _IntroSlide(
      icon: Icons.contacts_outlined,
      title: 'Customers',
      body:
          'Customers are where pay-later balances, messages, and WhatsApp order history come together.',
      bullets: [
        'Save customers before running targeted promotions',
        'Use customer history when following up on balances or orders',
      ],
    ),
    _IntroSlide(
      icon: Icons.point_of_sale,
      title: 'Sales',
      body:
          'Sales is for cash revenue you want recorded. Many merchants add one total at day-end; itemize with products only when stock or profit detail matters.',
      bullets: [
        'Use one entry for daily revenue if that matches your workflow',
        'Add products for stock deduction and margin reporting',
      ],
    ),
    _IntroSlide(
      icon: Icons.campaign_outlined,
      title: 'Marketing',
      body:
          'Marketing is for approved WhatsApp or SMS promotions to saved customers. Templates need WhatsApp approval before they can be sent.',
      bullets: [
        'Create or approve a template first',
        'Run promotions when products and recipients are ready',
      ],
    ),
    _IntroSlide(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Billing and Wallet',
      body:
          'Billing shows the app balance used for messaging costs. Wallet sales balance is for online order funds and withdrawals where supported.',
      bullets: [
        'Top up app balance before paid messaging',
        'Add banking details for deposits and withdrawals',
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
    SizeConfig().init(context);
    final isLast = _index == _slides.length - 1;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          SizeConfig.imageSizeMultiplier * 5,
          SizeConfig.heightMultiplier * 2,
          SizeConfig.imageSizeMultiplier * 5,
          SizeConfig.heightMultiplier * 2,
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
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Text(
              'Set up Pasella clearly',
              style: TextStyle(
                fontSize: SizeConfig.textMultiplier * 2.3,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 1),
            SizedBox(
              height: SizeConfig.heightMultiplier * 38,
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) =>
                    _SlideView(slide: _slides[index]),
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
                    color: i == _index ? Colors.green : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            SizedBox(height: SizeConfig.heightMultiplier * 2),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Later'),
                ),
                const Spacer(),
                if (!isLast)
                  ElevatedButton(
                    onPressed: () {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                      );
                    },
                    child: const Text('Next'),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenProducts();
                    },
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Start with Products'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _IntroSlide slide;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: SizeConfig.imageSizeMultiplier * 1,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CircleAvatar(
            radius: SizeConfig.imageSizeMultiplier * 8,
            backgroundColor: Colors.green.withValues(alpha: 0.1),
            child: Icon(
              slide.icon,
              size: SizeConfig.imageSizeMultiplier * 8,
              color: Colors.green.shade700,
            ),
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 2),
          Text(
            slide.title,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 2.1,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: SizeConfig.heightMultiplier),
          Text(
            slide.body,
            style: TextStyle(
              fontSize: SizeConfig.textMultiplier * 1.55,
              height: 1.35,
              color: Colors.grey.shade800,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: SizeConfig.heightMultiplier * 1.5),
          ...slide.bullets.map(
            (text) => Padding(
              padding: EdgeInsets.only(
                bottom: SizeConfig.heightMultiplier * 0.7,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: SizeConfig.imageSizeMultiplier * 4,
                    color: Colors.green.shade700,
                  ),
                  SizedBox(width: SizeConfig.imageSizeMultiplier * 2),
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: SizeConfig.textMultiplier * 1.45,
                        color: Colors.grey.shade800,
                      ),
                    ),
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
