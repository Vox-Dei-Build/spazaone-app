import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pasella/shared/widgets/tutorial_page_body.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/utils/support_util.dart';

class LoomVideoPage extends StatefulWidget {
  final String loomUrl; // Full Loom URL
  final String title;

  const LoomVideoPage({Key? key, required this.loomUrl, required this.title})
      : super(key: key);

  /// Remote Config values are outside the app's type system, so validate them
  /// before handing them to the native WebView. A missing scheme used to throw
  /// synchronously from `loadRequest` and terminate the screen.
  @visibleForTesting
  static Uri? parseVideoUri(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return null;

    final hasWebScheme =
        RegExp(r'^https?://', caseSensitive: false).hasMatch(raw);
    final hasAnotherScheme =
        RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(raw);
    if (hasAnotherScheme && !hasWebScheme) return null;

    final candidate = hasWebScheme ? raw : 'https://$raw';
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.trim().isEmpty ||
        !uri.host.contains('.')) {
      return null;
    }
    return uri;
  }

  @override
  State<LoomVideoPage> createState() => _LoomVideoPageState();
}

class _LoomVideoPageState extends State<LoomVideoPage> {
  WebViewController? _controller;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    final uri = LoomVideoPage.parseVideoUri(widget.loomUrl);
    if (uri == null) {
      _loadFailed = true;
      return;
    }

    try {
      final controller = WebViewController();
      _controller = controller;
      unawaited(_configureAndLoadVideo(controller, uri));
    } catch (_) {
      // Native WebView setup can fail on unsupported devices. Keep the Help
      // screen usable and leave the support action available below.
      _loadFailed = true;
    }
  }

  Future<void> _configureAndLoadVideo(
    WebViewController controller,
    Uri uri,
  ) async {
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.loadRequest(uri);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: CustomAppBar(
          title:
              widget.title.isNotEmpty ? widget.title : 'How to use Spaza One',
        ),
        body: TutorialPageBody(
          video: _loadFailed || _controller == null
              ? const _UnavailableTutorialVideo()
              : WebViewWidget(controller: _controller!),
          onSupport: () => SupportUtil.sendWhatsAppMessage(
              context, WhatsAppMessageType.support),
        ),
      );
}

class _UnavailableTutorialVideo extends StatelessWidget {
  const _UnavailableTutorialVideo();

  @override
  Widget build(BuildContext context) => ColoredBox(
        key: const Key('tutorial-video-unavailable'),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.videocam_off_outlined, size: 40),
                SizedBox(height: 12),
                Text(
                  'This tutorial is temporarily unavailable.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
}
