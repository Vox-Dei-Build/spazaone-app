import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PaystackWebView extends StatefulWidget {
  final String url;
  final String reference;

  const PaystackWebView({
    Key? key,
    required this.url,
    required this.reference,
  }) : super(key: key);

  @override
  _PaystackWebViewState createState() => _PaystackWebViewState();
}

class _PaystackWebViewState extends State<PaystackWebView> {
  final Completer<WebViewController> _controller =
      Completer<WebViewController>();
  bool isLoading = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Complete Payment',
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () async {
            final controller = await _controller.future;
            controller.reload(); // Refresh the page
          },
        ),
      ),
      body: Stack(
        children: [
          SizedBox(height: SizeConfig.heightMultiplier * 2),
          WebView(
            initialUrl: widget.url,
            javascriptMode: JavascriptMode.unrestricted,
            onWebViewCreated: (WebViewController webViewController) {
              _controller.complete(webViewController);
            },
            onPageStarted: (String url) {
              setState(() => isLoading = true);
            },
            onPageFinished: (String url) {
              setState(() => isLoading = false);
            },
            navigationDelegate: (NavigationRequest request) {
              if (request.url == "https://standard.paystack.co/close") {
                Navigator.of(context)
                    .pop(); // Close WebView when payment completes
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            gestureNavigationEnabled: true,
          ),
          if (isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
