import 'dart:async';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/services/message_queue.dart';
import 'package:pasella/services/sms_messaging_service.dart';

class ConnectivityIndicator extends StatefulWidget {
  const ConnectivityIndicator({super.key});

  @override
  _ConnectivityIndicatorState createState() => _ConnectivityIndicatorState();
}

class _ConnectivityIndicatorState extends State<ConnectivityIndicator> {
  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  DateTime? _lastSendAttempt;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    ConnectivityResult result = ConnectivityResult.none;
    try {
      result = await _connectivity.checkConnectivity();
    } catch (e) {
      print("Couldn't check connectivity status: $e");
    }
    if (!mounted) return;
    return _updateConnectionStatus(result);
  }

  Future<void> _updateConnectionStatus(ConnectivityResult result) async {
    final now = DateTime.now();
    if (_lastSendAttempt == null ||
        now.difference(_lastSendAttempt!) > const Duration(seconds: 10)) {
      if (result != ConnectivityResult.none) {
        final smsService = await SMSMessagingService.create();
        sendQueuedSMSMessages(smsService);
      }
      _lastSendAttempt = now;
    }

    if (!mounted) return;
    setState(() {
      _connectionStatus = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final bool isOffline = _connectionStatus == ConnectivityResult.none;
    final IconData icon =
        isOffline ? Icons.cloud_off_outlined : Icons.cloud_done_outlined;
    final Color color = isOffline ? Colors.red : Colors.green;
    final String tooltip = isOffline
        ? 'Offline — changes are saved on this device and will sync when you reconnect.'
        : 'Online — changes are syncing to the cloud.';

    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
      child: Icon(
        icon,
        color: color,
        size: SizeConfig.imageSizeMultiplier * 5,
        semanticLabel: isOffline ? 'Offline' : 'Online',
      ),
    );
  }
}
