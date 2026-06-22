import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';

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

class _MerchantOnboardingIntroState extends State<MerchantOnboardingIntro> {
  final PageController _controller = PageController();
  int _index = 0;

  static const List<_IntroSlide> _slides = [
    _IntroSlide(
      icon: Icons.person_add_alt_1_outlined,
      title: 'Start with one customer',
      body:
          'Save one real customer so you can record Pay Later credit immediately.',
      bullets: [
        'Pasella guides you from Customers',
        'Pay Later opens after saving',
      ],
    ),
    _IntroSlide(
      icon: Icons.groups_2_outlined,
      title: 'Build to 10 customers',
      body:
          'Ten customers gives you a useful audience for reminders and follow-ups.',
      bullets: [
        'Import contacts when it is faster',
        'Pasella tracks progress on Customers',
      ],
    ),
    _IntroSlide(
      icon: Icons.inventory_2_outlined,
      title: 'Add your first product',
      body: 'One product connects stock, sales, profit, and WhatsApp ordering.',
      bullets: [
        'Start with an item customers buy often',
        'List customer-facing items for WhatsApp',
      ],
    ),
    _IntroSlide(
      icon: Icons.link_outlined,
      title: 'Link a product to credit',
      body:
          'When a customer takes goods on account, attach the product on Add Credit.',
      bullets: [
        'Stock and customer history update together',
        'Reports show product-linked credits',
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
            if (!isLast)
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Later'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                      );
                    },
                    child: const Text('Next'),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onOpenCustomers();
                    },
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Add Customer'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Later'),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onOpenProducts();
                        },
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Products'),
                      ),
                    ],
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
