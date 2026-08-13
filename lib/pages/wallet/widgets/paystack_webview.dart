import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/widgets/private_region.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum HostedCheckoutOutcome { returned, closed, failed }

class PaystackWebView extends StatefulWidget {
  final String url;
  final String reference;
  final double amount;

  const PaystackWebView({
    Key? key,
    required this.url,
    required this.reference,
    required this.amount,
  }) : super(key: key);

  @override
  State<PaystackWebView> createState() => _PaystackWebViewState();
}

class _PaystackWebViewState extends State<PaystackWebView> {
  late final WebViewController _controller;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => isLoading = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => isLoading = false);
            if (url == 'https://standard.paystack.co/close') {
              if (mounted) {
                Navigator.pop(context, HostedCheckoutOutcome.returned);
              }
            }
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              Navigator.of(context).pop(HostedCheckoutOutcome.failed);
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url == 'https://standard.paystack.co/close') {
              if (mounted) {
                Navigator.of(context).pop(HostedCheckoutOutcome.returned);
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
          title: 'Complete Payment',
          trailing: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _controller.reload(),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  Navigator.of(context).pop(HostedCheckoutOutcome.closed);
                },
              ),
            ],
          )),
      body: Stack(
        children: [
          SizedBox(height: SizeConfig.heightMultiplier * 2),
          // Mask the Paystack card form -- PAN, CVV, expiry must never appear
          // in session replay. Wrapping just the WebView (not the AppBar /
          // spinner) keeps the chrome visible for diagnosing UX issues.
          PrivateRegion(
            child: WebViewWidget(controller: _controller),
          ),
          if (isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
