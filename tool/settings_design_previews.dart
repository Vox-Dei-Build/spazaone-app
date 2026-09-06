// Production presentation with isolated example state and callbacks.
import 'package:flutter/material.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/pages/auth/widgets/auth_shell.dart';
import 'package:pasella/pages/profile/business_name_page.dart';
import 'package:pasella/pages/profile/widgets/business_type.dart';
import 'package:pasella/pages/profile/widgets/business_category.dart';
import 'package:pasella/pages/settings/help/help.dart';
import 'package:pasella/pages/settings/order_options/order_options_page.dart';
import 'package:pasella/pages/settings/privacy/privacy_page.dart';
import 'package:pasella/pages/settings/setup/your_shop_page.dart';
import 'package:pasella/pages/settings/share/share.dart';
import 'package:pasella/pages/settings/stores/store_management_page.dart';
import 'package:pasella/services/merchant_ordering_options_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_setup_card.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_setup_state.dart';
import 'package:pasella/shared/widgets/onboarding/merchant_onboarding_intro.dart';
import 'package:provider/provider.dart';

void _notice(BuildContext context, String action) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('$action · Example only, nothing is sent or saved')),
    );

Map<String, WidgetBuilder> settingsDesignPreviews() => {
      'Finish profile': (_) => const _ProfilePreview(),
      'First steps': (context) => Scaffold(
            appBar: const CustomAppBar(title: 'Welcome'),
            body: MerchantOnboardingIntro(
              onOpenCustomers: () => _notice(context, 'Add customer'),
              onOpenProducts: () => _notice(context, 'Add product'),
              onExplore: () => Navigator.of(context).maybePop(),
            ),
          ),
      'Business name': (_) => const _BusinessNamePreview(),
      'Business type': (_) => ChangeNotifierProvider(
            create: (_) => AppModel(),
            child: const BusinessTypePage(),
          ),
      'Business category': (_) => ChangeNotifierProvider(
            create: (_) => AppModel(),
            child: const BusinessCategoryPage(),
          ),
      'Your shop': (context) => Scaffold(
            appBar: const CustomAppBar(title: 'Your shop'),
            body: YourShopOverview(
              showStoresAndTeam: true,
              onShopLink: () => _open(context, 'Ordering link'),
              onStoreDetails: () => _open(context, 'Business name'),
              onStoresAndTeam: () => _open(context, 'Active store'),
              onOrderOptions: () => _open(context, 'Order options'),
              onOnlinePayments: () => _notice(context, 'Online payments'),
            ),
          ),
      'Shop setup': (context) => Scaffold(
            appBar: const CustomAppBar(title: 'Shop setup'),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                MerchantSetupCard.fromState(
                  userId: 'preview-shop',
                  allowCompletedLinkDismissal: false,
                  state: const MerchantSetupState(
                    hasCustomers: true,
                    hasProducts: true,
                    hasListedProduct: false,
                    hasOrderingLink: true,
                    hasOrderingOptions: false,
                    hasApprovedTemplate: false,
                    hasBank: false,
                    shopName: 'Neighbourhood Store',
                    orderingUrl: 'https://example.com/shop/demo',
                    orderingCode: 'DEMO123',
                    fallbackText: 'Shop DEMO123',
                    loading: false,
                  ),
                  actions: MerchantSetupActions(
                    onAddCustomer: () => _notice(context, 'Add customer'),
                    onAddProduct: () => _notice(context, 'Add product'),
                    onChooseWhatsAppProducts: () =>
                        _notice(context, 'List products'),
                    onOpenOrderingLink: () => _open(context, 'Ordering link'),
                    onOpenOrderOptions: () => _open(context, 'Order options'),
                    onOpenBanking: () => _notice(context, 'Bank details'),
                    onCreateTemplate: () => _notice(context, 'Create template'),
                  ),
                ),
              ],
            ),
          ),
      'Ordering link': (context) => Scaffold(
            appBar: const CustomAppBar(title: 'Ordering link'),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: OrderingLinkPanel(
                shopName: 'Neighbourhood Store',
                code: 'DEMO123',
                orderingUrl: 'https://example.com/shop/demo',
                pasellaWhatsappNumber: 'Example WhatsApp number',
                fallbackText: 'Shop DEMO123',
                regenerating: false,
                hasListedProduct: true,
                onAddProduct: () => _notice(context, 'Add product'),
                onCopyCode: () => _notice(context, 'Copy shop code'),
                onCopyLink: () => _notice(context, 'Copy ordering link'),
                onShare: () => _notice(context, 'Share link'),
                onWhatsApp: () => _notice(context, 'Share on WhatsApp'),
                onRegenerate: () => _notice(context, 'Regenerate code'),
              ),
            ),
          ),
      'Order options': (_) => OrderOptionsPage(
            loader: () async => const MerchantOrderingOptions(
              configured: true,
              payLaterEnabled: true,
              deliveryEnabled: true,
              deliveryFlatFeeMinor: 2000,
              deliveryServiceAreaText: 'Within 5 km of the shop',
            ),
            saver: (
                    {required payLaterEnabled,
                    required deliveryEnabled,
                    required deliveryFlatFeeMinor,
                    required deliveryServiceAreaText}) async =>
                MerchantOrderingOptions(
              configured: true,
              payLaterEnabled: payLaterEnabled,
              deliveryEnabled: deliveryEnabled,
              deliveryFlatFeeMinor: deliveryFlatFeeMinor,
              deliveryServiceAreaText: deliveryServiceAreaText,
            ),
          ),
      'Active store': (_) => Scaffold(
            appBar: const CustomAppBar(title: 'Active store'),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                ActiveStoreSummary(
                    storeName: 'Neighbourhood Store', role: 'Owner'),
                SizedBox(height: 16),
                Text(
                    'This preview shows the shared store summary. Team access and store switching require a signed-in session.'),
              ],
            ),
          ),
      'Privacy': (_) => const _PrivacyPreview(),
      'Help': (context) => Scaffold(
            appBar: const CustomAppBar(title: 'Help'),
            body: HelpMenu(
              onTutorial: (label, _) => _notice(context, label),
              onPrivacy: () => _notice(context, 'Privacy policy'),
              onSupport: () => _notice(context, 'Chat with support'),
            ),
          ),
    };

void _open(BuildContext context, String label) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: settingsDesignPreviews()[label]!),
    );

class _BusinessNamePreview extends StatefulWidget {
  const _BusinessNamePreview();
  @override
  State<_BusinessNamePreview> createState() => _BusinessNamePreviewState();
}

class _BusinessNamePreviewState extends State<_BusinessNamePreview> {
  final _controller = TextEditingController(text: 'Neighbourhood Store');
  final _key = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const CustomAppBar(title: 'Business name'),
        body: BusinessNameForm(
          controller: _controller,
          formKey: _key,
          onSave: () {
            if (_key.currentState!.validate()) {
              _notice(context, 'Save business name');
            }
          },
        ),
      );
}

class _ProfilePreview extends StatefulWidget {
  const _ProfilePreview();
  @override
  State<_ProfilePreview> createState() => _ProfilePreviewState();
}

class _ProfilePreviewState extends State<_ProfilePreview> {
  final _name = TextEditingController();
  final _shop = TextEditingController();
  final _key = GlobalKey<FormState>();
  @override
  void dispose() {
    _name.dispose();
    _shop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AuthShell(
        title: 'Tell us about your shop',
        subtitle: 'A few details to make your account feel like yours.',
        stepLabel: 'Finish your profile',
        child: Form(
          key: _key,
          child: Column(children: [
            ProfileDetailsFields(nameController: _name, shopController: _shop),
            const SizedBox(height: 24),
            AuthPrimaryButton(
                label: 'Continue',
                onPressed: () {
                  if (_key.currentState!.validate()) {
                    _notice(context, 'Finish profile');
                  }
                }),
            TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Back to screens')),
          ]),
        ),
      );
}

class _PrivacyPreview extends StatefulWidget {
  const _PrivacyPreview();
  @override
  State<_PrivacyPreview> createState() => _PrivacyPreviewState();
}

class _PrivacyPreviewState extends State<_PrivacyPreview> {
  bool _analytics = false;
  bool _crash = true;
  bool _dirty = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: const CustomAppBar(title: 'Privacy'),
        body: PrivacySettingsForm(
          analytics: _analytics,
          crash: _crash,
          saving: false,
          dirty: _dirty,
          onAnalyticsChanged: (v) => setState(() {
            _analytics = v;
            _dirty = true;
          }),
          onCrashChanged: (v) => setState(() {
            _crash = v;
            _dirty = true;
          }),
          onSave: () {
            setState(() => _dirty = false);
            _notice(context, 'Save privacy choices');
          },
          onOpenPolicy: () => _notice(context, 'Privacy policy'),
        ),
      );
}
