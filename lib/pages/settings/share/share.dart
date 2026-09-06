import 'package:pasella/design/spaza_tokens.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:pasella/services/store_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/models/common/app_model.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

class SharePage extends StatefulWidget {
  const SharePage({Key? key, this.source = 'settings'}) : super(key: key);
  static const id = '/sharePage';

  final String source;

  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  String get userId => StoreSession.instance.storeId;

  bool _loading = true;
  bool _regenerating = false;
  String? _error;
  String? _shopName;
  String? _code;
  String? _orderingUrl;
  String? _pasellaWhatsappNumber;
  String? _fallbackText;
  bool? _hasListedProduct;

  @override
  void initState() {
    super.initState();
    _loadMerchantProfile();
    _loadCatalogReadiness();
    _loadOrderingLink();
  }

  Future<void> _loadMerchantProfile() async {
    if (userId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (!mounted) return;
      final data = doc.data() ?? const <String, dynamic>{};
      setState(() {
        _shopName =
            (data['shopName'] ?? data['name'] ?? 'your shop').toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _shopName = 'your shop';
      });
    }
  }

  Future<void> _loadCatalogReadiness() async {
    if (userId.isEmpty) return;
    try {
      final products = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('products')
          .where('whatsappListed', isEqualTo: true)
          .limit(1)
          .get();
      if (!mounted) return;
      setState(() => _hasListedProduct = products.docs.isNotEmpty);
    } catch (_) {
      // Link creation remains independent of catalogue readiness. If this
      // optional check is unavailable, keep the link actions usable instead
      // of presenting a false "no products" warning.
    }
  }

  Future<void> _loadOrderingLink({String action = 'get'}) async {
    if (userId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Sign in again to create your ordering link.';
      });
      return;
    }

    setState(() {
      _loading = action == 'get';
      _regenerating = action == 'regenerate';
      _error = null;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'getMerchantOrderingLink',
      );
      final result = await callable.call(<String, dynamic>{
        'action': action,
        'storeId': userId,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final created = data['created'] == true;
      final regenerated = data['regenerated'] == true;
      if (!mounted) return;
      setState(() {
        _code = data['code'] as String?;
        _orderingUrl = data['orderingUrl'] as String?;
        _pasellaWhatsappNumber = data['pasellaWhatsappNumber'] as String?;
        _fallbackText = data['fallbackText'] as String?;
      });
      if (created) {
        await TelemetryService.instance.capture(
          OrderingLinkCreated(source: widget.source, regenerated: regenerated),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = orderingLinkErrorMessage(error.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = orderingLinkErrorMessage('unknown');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _regenerating = false;
        });
      }
    }
  }

  void _openProducts() {
    context.read<AppModel>().updateCurrentIndex(1);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  String _shareMessage() {
    final shop = (_shopName ?? 'my shop').trim();
    final url = _orderingUrl ?? '';
    final fallback = _fallbackText ?? '';
    return [
      'You can order from $shop on WhatsApp:',
      url,
      '',
      'Open the link to place an order.',
      fallback,
    ].where((line) => line.trim().isNotEmpty).join('\n');
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    await TelemetryService.instance.capture(
      OrderingLinkShared(channel: label == 'Code' ? 'copy_code' : 'copy_link'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied.')));
  }

  Future<void> _shareToWhatsApp() async {
    final url = Uri.parse(
      'whatsapp://send?text=${Uri.encodeComponent(_shareMessage())}',
    );
    if (await canLaunchUrl(url)) {
      await TelemetryService.instance.capture(
        const OrderingLinkShared(channel: 'whatsapp'),
      );
      await launchUrl(url);
      return;
    }
    await TelemetryService.instance.capture(
      const OrderingLinkShared(channel: 'native_share'),
    );
    await Share.share(_shareMessage());
  }

  Future<void> _shareNative() async {
    await TelemetryService.instance.capture(
      const OrderingLinkShared(channel: 'native_share'),
    );
    await Share.share(_shareMessage());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpazaColors.canvas,
      appBar: const CustomAppBar(title: 'Ordering link'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading)
                const SizedBox(
                  height: 280,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _ErrorPanel(message: _error!, onRetry: _loadOrderingLink)
              else
                OrderingLinkPanel(
                  shopName: _shopName ?? 'your shop',
                  code: _code ?? '',
                  orderingUrl: _orderingUrl ?? '',
                  pasellaWhatsappNumber: _pasellaWhatsappNumber ?? '',
                  fallbackText: _fallbackText ?? '',
                  regenerating: _regenerating,
                  hasListedProduct: _hasListedProduct ?? true,
                  onAddProduct: _openProducts,
                  onCopyCode: () => _copy(_code ?? '', 'Code'),
                  onCopyLink: () => _copy(_orderingUrl ?? '', 'Link'),
                  onShare: _shareNative,
                  onWhatsApp: _shareToWhatsApp,
                  onRegenerate: () => _loadOrderingLink(action: 'regenerate'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
String orderingLinkErrorMessage(String code) => switch (code) {
      'unauthenticated' => 'Sign in again to open your shop link.',
      'permission-denied' =>
        'You do not have permission to manage this shop link.',
      'not-found' =>
        'This shop could not be found. Switch shops and try again.',
      'failed-precondition' =>
        'Shop link setup is not ready yet. Please try again later.',
      'unavailable' ||
      'deadline-exceeded' =>
        'SpazaOne could not be reached. Check your connection and try again.',
      _ => 'Could not load your shop link. Please try again.',
    };

class OrderingLinkPanel extends StatelessWidget {
  const OrderingLinkPanel({
    super.key,
    required this.shopName,
    required this.code,
    required this.orderingUrl,
    required this.pasellaWhatsappNumber,
    required this.fallbackText,
    required this.regenerating,
    required this.hasListedProduct,
    required this.onAddProduct,
    required this.onCopyCode,
    required this.onCopyLink,
    required this.onShare,
    required this.onWhatsApp,
    required this.onRegenerate,
  });

  final String shopName;
  final String code;
  final String orderingUrl;
  final String pasellaWhatsappNumber;
  final String fallbackText;
  final bool regenerating;
  final bool hasListedProduct;
  final VoidCallback onAddProduct;
  final VoidCallback onCopyCode;
  final VoidCallback onCopyLink;
  final VoidCallback onShare;
  final VoidCallback onWhatsApp;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const green = SpazaColors.action;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: SpazaColors.surface,
            borderRadius: BorderRadius.circular(SpazaRadius.surface),
            border: Border.all(color: SpazaColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SpazaColors.surface,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  FontAwesomeIcons.whatsapp,
                  color: green,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Take orders on WhatsApp',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Share one link and customers can start an order with $shopName.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: SpazaColors.muted,
                  height: 1.4,
                ),
              ),
              if (!hasListedProduct) ...[
                const SizedBox(height: 16),
                EmptyOrderingCatalogNotice(onAddProduct: onAddProduct),
              ],
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: orderingUrl.isEmpty ? null : onWhatsApp,
                icon: const Icon(FontAwesomeIcons.whatsapp),
                label: Text(
                  hasListedProduct
                      ? 'Share on WhatsApp'
                      : 'Share anyway on WhatsApp',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: SpazaColors.surface,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SpazaRadius.control),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: orderingUrl.isEmpty ? null : onShare,
                icon: const Icon(Icons.ios_share_outlined),
                label: Text(
                  hasListedProduct
                      ? 'Share another way'
                      : 'Share anyway another way',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: green,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Your link',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Copy these details when you need to paste them somewhere manually.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: SpazaColors.muted,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        _CopyableField(
          label: 'Ordering link',
          value: orderingUrl,
          icon: Icons.link,
          onCopy: orderingUrl.isEmpty ? null : onCopyLink,
        ),
        const SizedBox(height: 10),
        _CopyableField(
          label: 'Shop code',
          value: code,
          icon: Icons.tag_outlined,
          emphasize: true,
          onCopy: code.isEmpty ? null : onCopyCode,
        ),
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            color: SpazaColors.surface,
            border: Border.all(color: SpazaColors.border),
            borderRadius: BorderRadius.circular(SpazaRadius.control),
          ),
          child: ExpansionTile(
            leading: const Icon(Icons.tune_outlined),
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            title: const Text(
              'Link details and reset',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            children: [
              _DetailRow(
                label: 'Spaza One WhatsApp',
                value: pasellaWhatsappNumber,
              ),
              _DetailRow(label: 'Manual fallback', value: fallbackText),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: regenerating ? null : onRegenerate,
                  icon: regenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Regenerate code'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class EmptyOrderingCatalogNotice extends StatelessWidget {
  const EmptyOrderingCatalogNotice({
    super.key,
    required this.onAddProduct,
  });

  final VoidCallback onAddProduct;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('ordering-link-empty-catalogue'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(SpazaRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add a product before sharing',
            style: TextStyle(
              color: colors.onTertiaryContainer,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your shop link is ready, but customers will not see products yet.',
            style: TextStyle(
              color: colors.onTertiaryContainer,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: onAddProduct,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Add product'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyableField extends StatelessWidget {
  const _CopyableField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onCopy,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onCopy;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SpazaColors.subtle,
        borderRadius: BorderRadius.circular(SpazaRadius.control),
        border: Border.all(color: SpazaColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: SpazaColors.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: SpazaColors.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  maxLines: emphasize ? 1 : 3,
                  style: TextStyle(
                    color: SpazaColors.ink,
                    fontSize: emphasize ? 16 : 14,
                    fontWeight: emphasize ? FontWeight.w500 : FontWeight.w500,
                    height: 1.25,
                    letterSpacing: emphasize ? 1.0 : 0,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy $label',
            onPressed: onCopy,
            icon: const Icon(Icons.copy),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: SpazaColors.muted,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(value, style: const TextStyle(height: 1.25)),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
