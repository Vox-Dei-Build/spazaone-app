import 'dart:async';

import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pasella/config/size_config.dart';
import 'package:pasella/services/message_queue.dart';
import 'package:pasella/services/sms_messaging_service.dart';
import 'package:http/http.dart' as http;

enum _ConnectionState { offline, checking, online }

class ConnectivityIndicator extends StatefulWidget {
  const ConnectivityIndicator({super.key});

  @override
  _ConnectivityIndicatorState createState() => _ConnectivityIndicatorState();
}

class _ConnectivityIndicatorState extends State<ConnectivityIndicator> {
  _ConnectionState _connectionState = _ConnectionState.checking;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _probeTimer;
  DateTime? _lastSendAttempt;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectionStatus,
    );
    _probeTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _initConnectivity(),
    );
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _probeTimer?.cancel();
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
    if (result == ConnectivityResult.none) {
      if (mounted) {
        setState(() => _connectionState = _ConnectionState.offline);
      }
      return;
    }

    if (mounted) {
      setState(() => _connectionState = _ConnectionState.checking);
    }

    final hasBackendAccess = await _canReachBackend();
    if (!mounted) return;
    setState(() {
      _connectionState =
          hasBackendAccess ? _ConnectionState.online : _ConnectionState.offline;
    });
    if (!hasBackendAccess) return;

    final now = DateTime.now();
    if (_lastSendAttempt == null ||
        now.difference(_lastSendAttempt!) > const Duration(seconds: 10)) {
      final smsService = await SMSMessagingService.create();
      sendQueuedSMSMessages(smsService);
      _lastSendAttempt = now;
    }
  }

  Future<bool> _canReachBackend() async {
    try {
      final response = await http
          .get(Uri.https('firestore.googleapis.com', '/'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode > 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    final isChecking = _connectionState == _ConnectionState.checking;
    final isOnline = _connectionState == _ConnectionState.online;
    final IconData icon =
        isChecking
            ? Icons.cloud_sync_outlined
            : isOnline
            ? Icons.cloud_done_outlined
            : Icons.cloud_off_outlined;
    final Color color =
        isChecking
            ? Colors.orange.shade700
            : isOnline
            ? Colors.green
            : Colors.red;
    final String label =
        isChecking
            ? 'Checking connection'
            : isOnline
            ? 'Online and synced'
            : 'Offline or unable to sync';
    final String tooltip =
        isChecking
            ? 'Checking whether Pasella can reach the cloud.'
            : isOnline
            ? 'Online — changes can sync to the cloud.'
            : 'Offline — changes stay on this device until Pasella can reach the cloud.';

    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
      child: Icon(
        icon,
        color: color,
        size: SizeConfig.imageSizeMultiplier * 5,
        semanticLabel: label,
      ),
    );
  }
}
