import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/services/analytics_event.dart';
import 'package:pasella/services/telemetry_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SharePage extends StatefulWidget {
  const SharePage({Key? key, this.source = 'settings'}) : super(key: key);
  static const id = '/sharePage';

  final String source;

  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  final String userId = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _loading = true;
  bool _regenerating = false;
  String? _error;
  String? _shopName;
  String? _code;
  String? _orderingUrl;
  String? _pasellaWhatsappNumber;
  String? _fallbackText;

  @override
  void initState() {
    super.initState();
    _loadMerchantProfile();
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
      final result = await callable.call(<String, dynamic>{'action': action});
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your ordering link. Please try again.';
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
    SizeConfig().init(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
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
                _OrderingLinkPanel(
                  shopName: _shopName ?? 'your shop',
                  code: _code ?? '',
                  orderingUrl: _orderingUrl ?? '',
                  pasellaWhatsappNumber: _pasellaWhatsappNumber ?? '',
                  fallbackText: _fallbackText ?? '',
                  regenerating: _regenerating,
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

class _OrderingLinkPanel extends StatelessWidget {
  const _OrderingLinkPanel({
    required this.shopName,
    required this.code,
    required this.orderingUrl,
    required this.pasellaWhatsappNumber,
    required this.fallbackText,
    required this.regenerating,
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
  final VoidCallback onCopyCode;
  final VoidCallback onCopyLink;
  final VoidCallback onShare;
  final VoidCallback onWhatsApp;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);
    final theme = Theme.of(context);
    final green = Colors.green.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                green.withValues(alpha: 0.14),
                green.withValues(alpha: 0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: green.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  FontAwesomeIcons.whatsapp,
                  color: green,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Take orders on WhatsApp',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Share one link and customers can start an order with $shopName.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: orderingUrl.isEmpty ? null : onWhatsApp,
                icon: const Icon(FontAwesomeIcons.whatsapp),
                label: const Text('Share on WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: orderingUrl.isEmpty ? null : onShare,
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Share another way'),
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
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Copy these details when you need to paste them somewhere manually.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade700,
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
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ExpansionTile(
            leading: const Icon(Icons.tune_outlined),
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            title: const Text(
              'Link details and reset',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            children: [
              _DetailRow(
                label: 'Pasella WhatsApp',
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
    SizeConfig().init(context);
    final textSize = SizeConfig.textMultiplier;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: textSize * 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  maxLines: emphasize ? 1 : 3,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: emphasize ? textSize * 2.0 : textSize * 1.35,
                    fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
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
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
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
