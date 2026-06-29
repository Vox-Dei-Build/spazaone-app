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
import 'package:pasella/shared/widgets/onboarding/activation_coachmark.dart';
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
    final textSize = SizeConfig.textMultiplier * 1.8;
    final titleSize = SizeConfig.textMultiplier * 2.1;

    return Scaffold(
      appBar: const CustomAppBar(title: 'Share ordering link'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(SizeConfig.blockSizeHorizontal * 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Share your ordering link',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: SizeConfig.blockSizeVertical * 0.7),
              Text(
                'Share this link with anyone. They can open WhatsApp and place an order with ${_shopName ?? 'your shop'}.',
                style: TextStyle(
                  fontSize: textSize,
                  color: Colors.grey.shade700,
                  height: 1.35,
                ),
              ),
              SizedBox(height: SizeConfig.blockSizeVertical * 1.8),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                _ErrorPanel(message: _error!, onRetry: _loadOrderingLink)
              else
                _OrderingLinkPanel(
                  userId: userId,
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
    required this.userId,
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

  final String userId;
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
    final green = Colors.green.shade700;
    final textSize = SizeConfig.textMultiplier;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.all(SizeConfig.blockSizeHorizontal * 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      FontAwesomeIcons.whatsapp,
                      color: green,
                      size: 22,
                    ),
                  ),
                  SizedBox(width: SizeConfig.blockSizeHorizontal * 3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ready to send',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: textSize * 1.7,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Send it on WhatsApp, copy it, or share it in any channel.',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: textSize * 1.35,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: SizeConfig.blockSizeVertical * 1.6),
              _CopyableField(
                label: 'Ordering link',
                value: orderingUrl,
                icon: Icons.link,
                onCopy: orderingUrl.isEmpty ? null : onCopyLink,
              ),
              SizedBox(height: SizeConfig.blockSizeVertical),
              _CopyableField(
                label: 'Shop code',
                value: code,
                icon: Icons.tag_outlined,
                emphasize: true,
                onCopy: code.isEmpty ? null : onCopyCode,
              ),
            ],
          ),
        ),
        SizedBox(height: SizeConfig.blockSizeVertical * 1.5),
        ActivationCoachmark(
          userId: userId,
          coachmarkKey: 'share_ordering_link',
          title: 'Share this with anyone',
          message: 'Anyone with the link can open WhatsApp and start an order.',
          icon: FontAwesomeIcons.whatsapp,
          accentColor: green,
          child: ElevatedButton.icon(
            onPressed: orderingUrl.isEmpty ? null : onWhatsApp,
            icon: const Icon(FontAwesomeIcons.whatsapp),
            label: const Text('Share on WhatsApp'),
            style: ElevatedButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        SizedBox(height: SizeConfig.blockSizeVertical),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: orderingUrl.isEmpty ? null : onCopyLink,
                icon: const Icon(Icons.link),
                label: const Text('Copy link'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            SizedBox(width: SizeConfig.blockSizeHorizontal * 2),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: orderingUrl.isEmpty ? null : onShare,
                icon: const Icon(Icons.ios_share),
                label: const Text('Share'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: SizeConfig.blockSizeVertical * 1.5),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            title: const Text(
              'Advanced details',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            children: [
              _DetailRow(label: 'Customer command', value: 'shop $code'),
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
