import 'package:pasella/config/remote_config.dart';
import 'package:twilio_flutter/twilio_flutter.dart';

class SMSMessagingService {
  final TwilioFlutter twilioFlutter;

  SMSMessagingService._(this.twilioFlutter);

  static Future<SMSMessagingService> create() async {
    final remoteConfigService =
        await RemoteConfigService.getInstance(); // 🔥 Reuse instance

    final twilioFlutter = TwilioFlutter(
      accountSid: remoteConfigService.getString('TWILIO_ACCOUNT_SID'),
      authToken: remoteConfigService.getString('TWILIO_AUTH_TOKEN'),
      twilioNumber: remoteConfigService.getString('TWILIO_NUMBER'),
    );

    return SMSMessagingService._(twilioFlutter);
  }

  Future<int> sendSMS(String phoneNumber, String message) async {
    return await twilioFlutter.sendSMS(
      toNumber: phoneNumber,
      messageBody: message,
    );
  }
}
