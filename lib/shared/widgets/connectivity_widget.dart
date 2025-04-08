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
  DateTime? _lastSendAttempt;

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  Future<void> _initConnectivity() async {
    ConnectivityResult? result;
    try {
      result = await _connectivity.checkConnectivity();
    } catch (e) {
      print("Couldn't check connectivity status: $e");
    }
    return _updateConnectionStatus(result!);
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

    setState(() {
      _connectionStatus = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    SizeConfig().init(context);

    return Material(
      borderRadius: BorderRadius.circular(SizeConfig.imageSizeMultiplier * 3),
      elevation: 5.0, // Optional: adds shadow for a lifted effect
      color: _connectionStatus == ConnectivityResult.none
          ? Colors.red
          : Colors.green, // Background color
      child: Padding(
        padding: EdgeInsets.all(SizeConfig.imageSizeMultiplier * 0.5),
        child: Container(
          width: SizeConfig.imageSizeMultiplier * 1.5, // Adjust width as needed
          height:
              SizeConfig.imageSizeMultiplier * 1.5, // Adjust height as needed
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
