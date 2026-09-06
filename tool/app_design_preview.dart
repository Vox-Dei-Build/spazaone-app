// Local visual review. All data and callbacks are synthetic; no Firebase or SMS.
// flutter run -d web-server -t tool/app_design_preview.dart
import 'package:flutter/material.dart';
import 'package:pasella/constants/constants.dart';
import 'package:pasella/design/spaza_tokens.dart';
import 'package:pasella/pages/auth/widgets/login_ui.dart';
import 'package:pasella/pages/auth/widgets/otp_code_dialog.dart';
import 'package:pasella/pages/settings/settings.dart';
import 'package:pasella/pages/wallet/wallet.dart';
import 'package:pasella/pages/sales/widgets/marketing_overview.dart';
import 'package:pasella/pages/promote/widgets/promotions/promotions_tab.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';
import 'package:pasella/shared/widgets/forms/transaction_form_scaffold.dart';
import 'workspace_design_preview.dart';
import 'settings_design_previews.dart';
import 'customer_design_previews.dart';
import 'product_design_previews.dart';
import 'commerce_design_previews.dart';
import 'design_preview_gallery.dart';

void main() => runApp(const AppDesignPreview());

class AppDesignPreview extends StatelessWidget {
  const AppDesignPreview({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.maxWidth > 600 ? 420.0 : constraints.maxWidth;
          return ColoredBox(
            color: const Color(0xFFE9ECF0),
            child: Center(
              child: SizedBox(
                width: width,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    size: Size(width, constraints.maxHeight),
                  ),
                  child: MaterialApp(
                    title: 'Spaza One · App design preview',
                    debugShowCheckedModeBanner: false,
                    theme: kCustomThemeData,
                    home: const _PreviewHome(),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

enum _Screen {
  login,
  activity,
  products,
  sales,
  settings,
  form,
  wallet,
  marketing
}

class _PreviewHome extends StatefulWidget {
  const _PreviewHome();

  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  _Screen _screen = _Screen.login;
  final _phone = TextEditingController();
  final _loginKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  void _select(_Screen screen) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (screen == _Screen.form) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (routeContext) => _FormPreview(onSaved: () {
          Navigator.of(routeContext).pop();
          _select(_Screen.sales);
        }),
      ));
      return;
    }
    setState(() => _screen = screen);
  }

  Future<void> _continue() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final verified = await showOtpCodeDialog(
      context,
      maskedNumber: 'Demo number · code 123456',
      onVerify: (code) async => code == '123456',
    );
    if (mounted && verified) _select(_Screen.activity);
  }

  void _notice(String label) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label · Local preview only')),
      );

  Widget _body() {
    switch (_screen) {
      case _Screen.login:
        return PhoneAuthScreen(
          controller: _phone,
          formKey: _loginKey,
          isReturningUser: true,
          onContinue: _continue,
          onCreateAccount: () => _notice('Create account'),
        );
      case _Screen.activity:
      case _Screen.products:
      case _Screen.sales:
        return WorkspacePreviewPage(
          key: ValueKey(_screen),
          initialPage: _screen.index - 1,
          showPreviewLabel: false,
          onPageChanged: (page) => _select(_Screen.values[page + 1]),
          onSettingsTap: () => _select(_Screen.settings),
          onFormTap: () => _select(_Screen.form),
        );
      case _Screen.settings:
        return Scaffold(
          appBar: CustomAppBar(
              title: 'Settings',
              onBackPressed: () => _select(_Screen.activity)),
          body: SettingsMenu(
            onSelected: (destination) {
              if (destination == SettingsDestination.logout) {
                _select(_Screen.login);
              } else if (destination == SettingsDestination.wallet) {
                _select(_Screen.wallet);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${destination.name} · Local preview only'),
                ));
              }
            },
          ),
        );
      case _Screen.wallet:
        return Scaffold(
          appBar: CustomAppBar(
              title: 'Wallet', onBackPressed: () => _select(_Screen.settings)),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: WalletHubMenu(
              campaignBalance: 250,
              sharedCampaignCredits: false,
              hasPendingPayment: false,
              overview: null,
              overviewLoading: false,
              overviewHasError: false,
              showBalance: true,
              showOnlinePayments: true,
              showCosts: true,
              onAddMoney: () => _notice('Add money'),
              onBalance: () => _notice('Balance activity'),
              onOnlinePayments: () => _notice('Online payments'),
              onCosts: () => _notice('Costs & limits'),
            ),
          ),
        );
      case _Screen.marketing:
        return Scaffold(
          appBar: CustomAppBar(
              title: 'Marketing', onBackPressed: () => _select(_Screen.sales)),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: MarketingOverview(
              onChooseProduct: () => _select(_Screen.products),
              campaignHistory: ListView(children: [
                PromotionHistoryCard(
                  name: 'Weekend essentials',
                  dateLabel: '4 Sep 2026',
                  status: 'sent',
                  onOpen: () => _notice('Promotion details'),
                  onRunAgain: () => _notice('Review promotion'),
                ),
                PromotionHistoryCard(
                  name: 'Fresh dairy offers',
                  dateLabel: '1 Sep 2026',
                  status: 'sent',
                  onOpen: () => _notice('Promotion details'),
                  onRunAgain: () => _notice('Review promotion'),
                ),
              ]),
            ),
          ),
        );
      case _Screen.form:
        return _FormPreview(onSaved: () => _select(_Screen.sales));
    }
  }

  void _showGallery() {
    final main = <String, WidgetBuilder>{
      for (final screen in _Screen.values)
        _screenLabels[screen.index]: (_) => const SizedBox.shrink(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (galleryContext) => DesignPreviewGallery(
        groups: {
          'Main screens': main,
          'Customers & transactions': customerDesignPreviews(),
          'Products & stock': productDesignPreviews(),
          'Orders, money & marketing': commerceDesignPreviews(),
          'Account & shop setup': settingsDesignPreviews(),
        },
        onOpen: (label, builder) {
          final mainIndex = _screenLabels.indexOf(label);
          if (mainIndex >= 0) {
            Navigator.of(galleryContext).pop();
            _select(_Screen.values[mainIndex]);
          } else {
            Navigator.of(galleryContext)
                .push(MaterialPageRoute<void>(builder: builder));
          }
        },
      ),
    ));
  }

  static const _screenLabels = [
    'Login',
    'Activity',
    'Products',
    'Sales',
    'Settings',
    'Record sale',
    'Wallet',
    'Marketing',
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Material(
                color: SpazaColors.subtle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('preview-all-screens'),
                          onPressed: _showGallery,
                          icon: const Icon(Icons.grid_view_rounded, size: 18),
                          label: const Text('All screens'),
                        ),
                      ),
                    ),
                    DropdownButton<_Screen>(
                      key: const ValueKey('preview-screen-selector'),
                      value: _screen,
                      underline: const SizedBox.shrink(),
                      style: Theme.of(context).textTheme.labelLarge,
                      onChanged: (screen) {
                        if (screen != null) _select(screen);
                      },
                      items: [
                        for (final screen in _Screen.values)
                          DropdownMenuItem(
                            value: screen,
                            child: Text(_screenLabels[screen.index]),
                          ),
                      ],
                    ),
                  ]),
                ),
              ),
              if (_screen == _Screen.login)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                      'Example data only · Try 082 123 4567, code 123456',
                      style: TextStyle(fontSize: 11, color: SpazaColors.muted)),
                ),
              Expanded(child: _body()),
            ],
          ),
        ),
      );
}

class _FormPreview extends StatefulWidget {
  const _FormPreview({required this.onSaved});
  final VoidCallback onSaved;

  @override
  State<_FormPreview> createState() => _FormPreviewState();
}

class _FormPreviewState extends State<_FormPreview> {
  final _key = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _stock = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _stock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TransactionFormScaffold(
        title: 'Record sale',
        formKey: _key,
        primaryActionLabel: 'Record sale',
        onPrimaryAction: widget.onSaved,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Example form · entries stay in this preview.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            CustomTextField(
              label: 'Sales amount',
              hintText: '0.00',
              prefixIcon: SpazaIcons.sales,
              textInputType:
                  const TextInputType.numberWithOptions(decimal: true),
              controller: _amount,
              validator: (value) => (double.tryParse(value ?? '') ?? 0) <= 0
                  ? 'Enter a sales amount greater than zero'
                  : null,
            ),
            CustomTextField(
              label: 'Stock purchased (optional)',
              hintText: '0.00',
              prefixIcon: SpazaIcons.products,
              controller: _stock,
              textInputType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
      );
}
