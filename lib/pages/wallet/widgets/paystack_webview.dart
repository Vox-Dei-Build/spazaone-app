import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/widgets/private_region.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'payment_response_screen.dart';

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
  _PaystackWebViewState createState() => _PaystackWebViewState();
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
              if (mounted) Navigator.pop(context, true); // Payment successful
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url == 'https://standard.paystack.co/close') {
              if (mounted) Navigator.of(context).pop(); // close webview
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  /// 🟢 Handle Payment Result and Navigate to Response Screen
  // ignore: unused_element
  void _handlePaymentResult(bool success) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => PaymentResponseScreen(
          isSuccess: success,
          message: success
              ? 'Your payment was successfully processed!'
              : 'Oops! Something went wrong with your payment.',
          amount: widget.amount,
          reference: widget.reference,
        ),
      ),
    );
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
                  Navigator.of(context).pop(); //close webview
                  Navigator.of(context).pop(); //close paystack form
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
